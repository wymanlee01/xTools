import CoreGraphics
import Testing
@testable import FeatureScreenshot

struct ResizeHandleTests {
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func 点在角上能命中对应手柄() {
        #expect(SelectionGeometry.handle(at: CGPoint(x: 102, y: 198), in: rect) == .topLeft)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 200, y: 100), in: rect) == .bottom)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 200, y: 150), in: rect) == nil)
    }

    @Test func 拖右边只改宽度() {
        let result = SelectionGeometry.resize(rect, handle: .right, to: CGPoint(x: 350, y: 999))
        #expect(result == CGRect(x: 100, y: 100, width: 250, height: 100))
    }

    @Test func 拖左上角改左边和上边() {
        let result = SelectionGeometry.resize(rect, handle: .topLeft, to: CGPoint(x: 50, y: 250))
        #expect(result == CGRect(x: 50, y: 100, width: 250, height: 150))
    }

    @Test func 拖过对边会翻转() {
        // 右边拖到左边以外：原来的左边变成右边
        let result = SelectionGeometry.resize(rect, handle: .right, to: CGPoint(x: 40, y: 0))
        #expect(result == CGRect(x: 40, y: 100, width: 60, height: 100))
    }

    @Test func 移动选区不会超出屏幕() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        let moved = SelectionGeometry.clamp(CGRect(x: 450, y: -20, width: 200, height: 100), in: bounds)
        #expect(moved == CGRect(x: 300, y: 0, width: 200, height: 100))
    }
}

struct PixelColorTests {
    /// 造一张 2×2 的 sRGB 图：左下红、右下绿、左上蓝、右上白
    func makeImage() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let fills: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: 0, width: 1, height: 1), CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: 1, y: 0, width: 1, height: 1), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: 1, width: 1, height: 1), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: 1, y: 1, width: 1, height: 1), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)),
        ]
        for (rect, color) in fills {
            context.setFillColor(color)
            context.fill(rect)
        }
        return context.makeImage()!
    }

    @Test func 按左上原点读取像素颜色() {
        let image = makeImage()
        #expect(PixelColor.read(from: image, x: 0, y: 0)?.hex == "#0000FF")  // 左上
        #expect(PixelColor.read(from: image, x: 1, y: 0)?.hex == "#FFFFFF")  // 右上
        #expect(PixelColor.read(from: image, x: 0, y: 1)?.hex == "#FF0000")  // 左下
        #expect(PixelColor.read(from: image, x: 1, y: 1)?.rgb == "rgb(0, 255, 0)")
    }

    @Test func 越界返回nil() {
        #expect(PixelColor.read(from: makeImage(), x: 2, y: 0) == nil)
    }
}

struct MagnifierTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func 默认在光标右下方() {
        let frame = Magnifier.frame(near: CGPoint(x: 100, y: 500), in: bounds)
        #expect(frame.minX == 120)
        #expect(frame.maxY == 480)
    }

    @Test func 靠右下角时翻到左上方() {
        let frame = Magnifier.frame(near: CGPoint(x: 990, y: 10), in: bounds)
        #expect(frame.maxX == 970)
        #expect(frame.minY == 30)
    }

    @Test func 光标像素会限制在图片内() {
        let size = CGSize(width: 2000, height: 1600)
        let pixel = Magnifier.pixel(at: CGPoint(x: 1000, y: 0), viewHeight: 800, scale: 2, imageSize: size)
        #expect(pixel.x == 1999)
        #expect(pixel.y == 1599)
    }
}
