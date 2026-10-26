import CoreGraphics
import Foundation
import Testing
@testable import FeatureScreenshot

struct AnnotationDocumentTests {
    func item(_ shape: AnnotationShape) -> Annotation {
        Annotation(shape: shape)
    }

    @Test func 撤销重做() {
        let doc = AnnotationDocument()
        doc.add(item(.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))))
        doc.add(item(.line(from: .zero, to: CGPoint(x: 5, y: 5))))
        #expect(doc.items.count == 2)

        doc.undo()
        #expect(doc.items.count == 1)
        #expect(doc.canRedo)
        doc.redo()
        #expect(doc.items.count == 2)

        // 撤销后再新增，重做栈清空
        doc.undo()
        doc.add(item(.step(number: 1, center: .zero)))
        #expect(!doc.canRedo)
    }

    @Test func 拖动移动只记一次撤销点() {
        let doc = AnnotationDocument()
        let rect = item(.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        doc.add(rect)
        doc.checkpoint()
        doc.update(rect.moved(by: 5, 0))
        doc.update(rect.moved(by: 9, 0))
        #expect(doc.items[0].shape == .rectangle(CGRect(x: 9, y: 0, width: 10, height: 10)))
        doc.undo()
        #expect(doc.items[0].shape == .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    @Test func 步骤序号自动递增() {
        let doc = AnnotationDocument()
        #expect(doc.nextStepNumber == 1)
        doc.add(item(.step(number: 1, center: .zero)))
        doc.add(item(.step(number: 5, center: .zero)))
        #expect(doc.nextStepNumber == 6)
    }

    @Test func 平移画笔所有点() {
        let pencil = item(.pencil([CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 3)])).moved(by: 10, -1)
        #expect(pencil.shape == .pencil([CGPoint(x: 11, y: 0), CGPoint(x: 12, y: 2)]))
    }

    @Test func 数字键对应工具() {
        #expect(AnnotationTool(rawValue: 1) == .rectangle)
        #expect(AnnotationTool(rawValue: 6) == .mosaic)
        #expect(AnnotationTool(rawValue: 9) == .highlight)
        #expect(AnnotationTool(rawValue: 0) == nil)
    }
}

struct ArrowGeometryTests {
    @Test func 水平箭头外形上下对称且尖端在终点() {
        // 线宽 4 → 箭头大小 h = 18（大小滑块 20 时线宽正好是 4）
        let points = ArrowGeometry.outline(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(points.count == 7)
        #expect(points[3] == CGPoint(x: 100, y: 0))
        #expect(abs(points[2].y - 14.4) < 0.001 && abs(points[4].y + 14.4) < 0.001)  // 翼尖 ±0.8h
        #expect(abs(points[1].x - 82) < 0.001)                                      // 颈部在 length - h
    }

    @Test func 竖直箭头会旋转() {
        let points = ArrowGeometry.outline(from: .zero, to: CGPoint(x: 0, y: 50), lineWidth: 2)
        #expect(abs(points[3].x) < 0.001 && abs(points[3].y - 50) < 0.001)
        #expect(points[2].x < 0 && points[4].x > 0)  // 两翼分在左右
    }

    @Test func 很短的箭头头部不超过总长60() {
        #expect(ArrowGeometry.headSize(length: 10, lineWidth: 8) == 6)
        #expect(ArrowGeometry.outline(from: .zero, to: .zero, lineWidth: 4).isEmpty)
    }
}

struct AnnotationRendererTests {
    /// 2 倍屏下 50×40 点的选区：左半白、右半黑
    func makeBase() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 80))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 50, y: 0, width: 50, height: 80))
        return context.makeImage()!
    }

    @Test func 导出保持像素尺寸并画上标注() throws {
        let renderer = AnnotationRenderer(baseImage: makeBase(), canvasSize: CGSize(width: 50, height: 40))
        // 在左上角（白色区域）画一个红色步骤标注
        var style = AnnotationStyle()
        style.size = 50
        let step = Annotation(shape: .step(number: 1, center: CGPoint(x: 10, y: 30)), style: style)
        let image = try #require(renderer.render([step]))
        #expect(image.width == 100 && image.height == 80)
        // 点 (10,30) 对应像素 (20, 80-60=20)；圆心偏左一点避开白色数字
        let color = try #require(PixelColor.read(from: image, x: 12, y: 20))
        #expect(color.red > 200 && color.green < 120)
    }

    @Test func 聚光灯只压暗高亮区域以外() throws {
        let renderer = AnnotationRenderer(baseImage: makeBase(), canvasSize: CGSize(width: 50, height: 40))
        let highlight = Annotation(shape: .highlight(CGRect(x: 0, y: 0, width: 20, height: 40)))
        let image = try #require(renderer.render([highlight]))
        let inside = try #require(PixelColor.read(from: image, x: 20, y: 40))   // 高亮区内的白色
        let outside = try #require(PixelColor.read(from: image, x: 45, y: 40))  // 高亮区外的白色
        #expect(inside.red == 255)
        #expect(outside.red < 200)
    }

    @Test func 马赛克会把黑白交界处混合() throws {
        let renderer = AnnotationRenderer(baseImage: makeBase(), canvasSize: CGSize(width: 50, height: 40))
        // 大小 60 → 块大小 16 点 = 32 像素，覆盖黑白交界（x=50 像素）
        var style = AnnotationStyle()
        style.size = 60
        let mosaic = Annotation(shape: .mosaic(CGRect(x: 0, y: 0, width: 50, height: 40)), style: style)
        let image = try #require(renderer.render([mosaic]))
        // 交界两侧原本一白一黑，马赛克后同一块内颜色相同
        let left = try #require(PixelColor.read(from: image, x: 48, y: 10))
        let right = try #require(PixelColor.read(from: image, x: 52, y: 10))
        #expect(left == right)
    }

    @Test func 实心矩形会填满内部() throws {
        let renderer = AnnotationRenderer(baseImage: makeBase(), canvasSize: CGSize(width: 50, height: 40))
        var style = AnnotationStyle()
        style.filled = true
        let rect = Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 20, height: 20)), style: style)
        let image = try #require(renderer.render([rect]))
        // 矩形中心 (15,15) 点 → 像素 (30, 80-30=50)，原本是白色，现在是红色
        #expect(try #require(PixelColor.read(from: image, x: 30, y: 50)).hex == "#FF0000")
    }

    @Test func 画笔马赛克模式只处理笔迹经过的地方() throws {
        let renderer = AnnotationRenderer(baseImage: makeBase(), canvasSize: CGSize(width: 50, height: 40))
        var style = AnnotationStyle()
        style.size = 60
        style.pencilMode = .mosaic
        // 沿 y=20 横穿黑白交界画一笔
        let stroke = Annotation(shape: .pencil([CGPoint(x: 5, y: 20), CGPoint(x: 45, y: 20)]), style: style)
        let image = try #require(renderer.render([stroke]))
        // 笔迹外（y=5 点 → 像素 70）仍是原图：交界左白右黑
        #expect(try #require(PixelColor.read(from: image, x: 48, y: 70)).hex == "#FFFFFF")
        #expect(try #require(PixelColor.read(from: image, x: 52, y: 70)).hex == "#000000")
    }
}

struct AnnotationStyleTests {
    @Test func 大小滑块换算各工具尺寸() {
        var style = AnnotationStyle()
        style.size = 20
        #expect(style.lineWidth == 4)
        #expect(style.fontSize == 18)
        #expect(style.stepRadius == 12)
        #expect(style.mosaicBlock == 8)
    }

    @Test func 预设颜色来自iShot原版界面() {
        #expect(AnnotationColor.presets.count == 5)
        #expect(AnnotationColor.presets[0] == AnnotationColor(red: 1, green: 0, blue: 0))
    }
}
