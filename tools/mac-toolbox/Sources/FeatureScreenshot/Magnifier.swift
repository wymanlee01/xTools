import AppKit

/// 放大镜 + 取色信息，跟随光标显示
/// 尺寸参照 iShot：取光标周围 15×15 像素，每像素放大成 8 点，共 120×120
enum Magnifier {
    static let pixelCount = 15
    static let zoom: CGFloat = 8
    static let size = CGFloat(pixelCount) * zoom
    static let infoHeight: CGFloat = 66
    /// 离光标的距离，避免挡住光标
    static let offset: CGFloat = 20

    /// 光标所在的像素（图片坐标，原点左上），会限制在图片范围内
    static func pixel(at point: CGPoint, viewHeight: CGFloat, scale: CGFloat, imageSize: CGSize) -> (x: Int, y: Int) {
        let x = Int(point.x * scale)
        let y = Int((viewHeight - point.y) * scale)
        return (min(max(x, 0), Int(imageSize.width) - 1), min(max(y, 0), Int(imageSize.height) - 1))
    }

    /// 放大镜整体（含下方信息栏）的位置：默认在光标右下方，靠边时翻到另一侧
    static func frame(near point: CGPoint, in bounds: CGRect) -> CGRect {
        let total = CGSize(width: size, height: size + infoHeight)
        var x = point.x + offset
        var y = point.y - offset - total.height
        if x + total.width > bounds.maxX { x = point.x - offset - total.width }
        if y < bounds.minY { y = point.y + offset }
        return CGRect(origin: CGPoint(x: x, y: y), size: total)
    }

    /// 在当前图形上下文中画出放大镜
    static func draw(image: CGImage, cursor: CGPoint, viewBounds: CGRect, scale: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let imageSize = CGSize(width: image.width, height: image.height)
        let center = pixel(at: cursor, viewHeight: viewBounds.height, scale: scale, imageSize: imageSize)
        let whole = frame(near: cursor, in: viewBounds)
        let zoomBox = CGRect(x: whole.minX, y: whole.maxY - size, width: size, height: size)

        // 1. 放大的像素：超出图片的部分留黑
        NSColor.black.setFill()
        zoomBox.fill()
        let half = pixelCount / 2
        let sample = CGRect(x: center.x - half, y: center.y - half, width: pixelCount, height: pixelCount)
        let crop = sample.intersection(CGRect(origin: .zero, size: imageSize))
        if !crop.isEmpty, let part = image.cropping(to: crop) {
            // 像素坐标原点在左上，放大镜原点在左下，要翻转 Y
            let dest = CGRect(x: zoomBox.minX + (crop.minX - sample.minX) * zoom,
                              y: zoomBox.maxY - (crop.maxY - sample.minY) * zoom,
                              width: crop.width * zoom, height: crop.height * zoom)
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(part, in: dest)
            context.restoreGState()
        }

        // 2. 十字准线和中心像素框
        let centerBox = CGRect(x: zoomBox.minX + CGFloat(half) * zoom, y: zoomBox.minY + CGFloat(half) * zoom,
                               width: zoom, height: zoom)
        NSColor.systemBlue.withAlphaComponent(0.35).setFill()
        CGRect(x: zoomBox.minX, y: centerBox.minY, width: size, height: zoom).fill()
        CGRect(x: centerBox.minX, y: zoomBox.minY, width: zoom, height: size).fill()
        NSColor.white.setStroke()
        NSBezierPath(rect: centerBox).stroke()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        NSBezierPath(rect: zoomBox.insetBy(dx: 0.5, dy: 0.5)).stroke()

        // 3. 信息栏：坐标、颜色、操作提示
        let infoBox = CGRect(x: whole.minX, y: whole.minY, width: size, height: infoHeight)
        NSColor.black.withAlphaComponent(0.8).setFill()
        infoBox.fill()
        guard let color = PixelColor.read(from: image, x: center.x, y: center.y) else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let white: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let gray: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.lightGray]
        let left = infoBox.minX + 6
        ("(\(center.x), \(center.y))" as NSString).draw(at: CGPoint(x: left, y: infoBox.minY + 48), withAttributes: white)

        let swatch = CGRect(x: left, y: infoBox.minY + 32, width: 12, height: 12)
        context.setFillColor(color.cgColor)
        context.fill(swatch)
        NSColor.white.setStroke()
        NSBezierPath(rect: swatch).stroke()
        (color.hex as NSString).draw(at: CGPoint(x: left + 18, y: infoBox.minY + 31), withAttributes: white)
        (color.rgb as NSString).draw(at: CGPoint(x: left, y: infoBox.minY + 17), withAttributes: white)
        ("C 复制 HEX  ⇧C 复制 RGB" as NSString).draw(at: CGPoint(x: left, y: infoBox.minY + 3), withAttributes: gray)
    }
}
