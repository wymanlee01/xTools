import AppKit
import CoreImage

/// 箭头几何：整支箭头是一个填充多边形，尾部细、往箭头方向逐渐变宽
/// 外形参照 iShot：箭头大小 h，颈部半宽 0.4h，两翼半宽 0.8h，两翼比颈部再往后 0.1h
public enum ArrowGeometry {
    /// 箭头大小 h：随线宽变大，但不超过总长的 60%
    public static func headSize(length: CGFloat, lineWidth: CGFloat) -> CGFloat {
        min(lineWidth * 3 + 6, length * 0.6)
    }

    /// 多边形顶点（按顺序连线后填充）：尾部 → 一侧颈部 → 一侧翼尖 → 尖端 → 另一侧翼尖 → 另一侧颈部
    public static func outline(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> [CGPoint] {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return [] }
        let h = headSize(length: length, lineWidth: lineWidth)
        // 先在“起点为原点、指向 +x”的坐标里算，再旋转平移回去
        let local: [CGPoint] = [
            CGPoint(x: 0, y: 0.5),
            CGPoint(x: length - h, y: 0.4 * h),
            CGPoint(x: length - 1.1 * h, y: 0.8 * h),
            CGPoint(x: length, y: 0),
            CGPoint(x: length - 1.1 * h, y: -0.8 * h),
            CGPoint(x: length - h, y: -0.4 * h),
            CGPoint(x: 0, y: -0.5),
        ]
        let cosA = (end.x - start.x) / length, sinA = (end.y - start.y) / length
        return local.map { p in
            CGPoint(x: start.x + p.x * cosA - p.y * sinA, y: start.y + p.x * sinA + p.y * cosA)
        }
    }
}

/// 把标注画进 CGContext；屏幕显示和导出图片共用，保证所见即所得
/// 坐标是选区内的点坐标（原点左下），导出时由调用方先按像素倍率缩放
final class AnnotationRenderer {
    /// 选区原图（像素），马赛克要用
    private let baseImage: CGImage
    /// 选区的点尺寸
    private let canvasSize: CGSize
    /// 马赛克图缓存：按“像素化/毛玻璃 + 块大小”懒生成整张选区图（思路同 iShot：先整图处理，再按区域裁出来贴）
    private var mosaicCache: [String: CGImage] = [:]

    init(baseImage: CGImage, canvasSize: CGSize) {
        self.baseImage = baseImage
        self.canvasSize = canvasSize
    }

    /// 导出：原图 + 全部标注，按像素尺寸输出
    func render(_ items: [Annotation]) -> CGImage? {
        let width = baseImage.width, height = baseImage.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / canvasSize.width, y: CGFloat(height) / canvasSize.height)
        draw(items, in: context)
        return context.makeImage()
    }

    /// 画全部标注：先画聚光灯遮罩，再按顺序画其他元素
    func draw(_ items: [Annotation], in context: CGContext) {
        drawHighlights(items, in: context)
        for item in items {
            context.saveGState()
            draw(item, in: context)
            context.restoreGState()
        }
    }

    private func draw(_ item: Annotation, in context: CGContext) {
        let style = item.style
        let color = style.color.cgColor(alpha: style.opacity)
        let width = style.lineWidth
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch item.shape {
        case .rectangle(let rect):
            // 圆角半径随大小变化；实心就填充，否则描边
            let radius = style.rounded ? min(4 + style.size * 0.2, rect.width / 2, rect.height / 2) : 0
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            style.filled ? context.fillPath() : context.strokePath()
        case .ellipse(let rect):
            style.filled ? context.fillEllipse(in: rect) : context.strokeEllipse(in: rect)
        case .line(let from, let to):
            context.strokeLineSegments(between: [from, to])
        case .arrow(let from, let to):
            let outline = ArrowGeometry.outline(from: from, to: to, lineWidth: width)
            guard !outline.isEmpty else { return }
            context.addLines(between: outline)
            context.closePath()
            context.fillPath()
        case .pencil(let points):
            guard points.count > 1 else { return }
            context.addLines(between: points)
            switch style.pencilMode {
            case .color:
                context.strokePath()
            case .blur, .mosaic:
                // 涂抹式马赛克：把笔迹轮廓当裁剪区，贴上整张马赛克/模糊图
                context.replacePathWithStrokedPath()
                context.clip()
                if let image = mosaicImage(blur: style.pencilMode == .blur, block: style.mosaicBlock) {
                    context.draw(image, in: CGRect(origin: .zero, size: canvasSize))
                }
            }
        case .mosaic(let rect):
            guard let mosaic = mosaicImage(blur: style.mosaicBlur, block: style.mosaicBlock) else { return }
            context.clip(to: rect)
            context.draw(mosaic, in: CGRect(origin: .zero, size: canvasSize))
        case .text(let string, let origin):
            drawText(string, at: origin, style: style, in: context)
        case .step(let number, let center):
            drawStep(number, at: center, style: style, in: context)
        case .highlight:
            break  // 已在 drawHighlights 统一画
        }
    }

    /// 聚光灯：所有高亮区域以外压暗，压暗程度取最后一个高亮元素的不透明度
    private func drawHighlights(_ items: [Annotation], in context: CGContext) {
        let shapes = items.compactMap { item -> (CGRect, AnnotationStyle)? in
            if case .highlight(let rect) = item.shape { return (rect, item.style) }
            return nil
        }
        guard let dim = shapes.last?.1.opacity else { return }
        context.saveGState()
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: canvasSize))
        for (rect, style) in shapes {
            if style.highlightOval {
                path.addEllipse(in: rect)
            } else {
                // iShot 用圆角 5 的矩形
                path.addRoundedRect(in: rect, cornerWidth: min(5, rect.width / 2), cornerHeight: min(5, rect.height / 2))
            }
        }
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0, alpha: 0.5 * dim))
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    /// 文字和步骤标注用的字体
    static func font(for style: AnnotationStyle, size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        if let name = style.fontName, let font = NSFont(name: name, size: size) { return font }
        return .systemFont(ofSize: size, weight: weight)
    }

    private func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(for: style, size: style.fontSize),
            .foregroundColor: NSColor(cgColor: style.color.cgColor(alpha: style.opacity)) ?? .red,
        ]
        let text = string as NSString
        withGraphicsContext(context) {
            drawBackground(behind: CGRect(origin: origin, size: text.size(withAttributes: attributes)), style: style)
            text.draw(at: origin, withAttributes: attributes)
        }
    }

    /// 步骤标注：实心圆 + 白色序号
    private func drawStep(_ number: Int, at center: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let radius = style.stepRadius
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        withGraphicsContext(context) { drawBackground(behind: circle, style: style) }
        context.fillEllipse(in: circle)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(for: style, size: radius * 1.1, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(style.opacity),
        ]
        let text = "\(number)" as NSString
        let size = text.size(withAttributes: attributes)
        withGraphicsContext(context) {
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
        }
    }

    /// 文字背景：底色是填充圆角块，描边是圆角边框
    private func drawBackground(behind rect: CGRect, style: AnnotationStyle) {
        guard style.textBackground != .none,
              let color = NSColor(cgColor: style.textBackgroundColor.cgColor(alpha: style.opacity)) else { return }
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4)
        if style.textBackground == .fill {
            color.setFill()
            path.fill()
        } else {
            color.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    /// 文字要用 AppKit 画，临时把 CGContext 包成 NSGraphicsContext
    private func withGraphicsContext(_ context: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 整张选区图做像素化或毛玻璃；block 取整后缓存，避免拖滑块时反复生成
    private func mosaicImage(blur: Bool, block: CGFloat) -> CGImage? {
        let key = "\(blur)-\(Int(block))"
        if let cached = mosaicCache[key] { return cached }
        let pixelsPerPoint = CGFloat(baseImage.width) / canvasSize.width
        let input = CIImage(cgImage: baseImage)
        let filter = blur
            ? CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input.clampedToExtent(),
                                                            kCIInputRadiusKey: CGFloat(Int(block)) * pixelsPerPoint])
            : CIFilter(name: "CIPixellate", parameters: [kCIInputImageKey: input.clampedToExtent(),
                                                         kCIInputScaleKey: CGFloat(Int(block)) * pixelsPerPoint,
                                                         kCIInputCenterKey: CIVector(x: 0, y: 0)])
        guard let output = filter?.outputImage?.cropped(to: input.extent),
              let image = CIContext().createCGImage(output, from: input.extent) else { return nil }
        mosaicCache[key] = image
        return image
    }
}
