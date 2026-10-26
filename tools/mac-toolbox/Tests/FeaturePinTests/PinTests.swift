import AppKit
import Testing
import ToolboxCore
@testable import FeaturePin

struct PinRulesTests {
    @Test func 滚轮缩放按速度分档() {
        #expect(PinRules.zoomStep(forDelta: 3) == 1)
        #expect(PinRules.zoomStep(forDelta: -8) == 5)
        #expect(PinRules.zoomStep(forDelta: 15) == 10)
        #expect(PinRules.zoomStep(forDelta: 40) == 20)
        #expect(PinRules.zoomStep(forDelta: 100) == 30)
    }

    @Test func 透明度按速度分档() {
        #expect(PinRules.opacityStep(forDelta: 2) == 1)
        #expect(PinRules.opacityStep(forDelta: 9) == 2)
        #expect(PinRules.opacityStep(forDelta: 25) == 5)
        #expect(PinRules.opacityStep(forDelta: 60) == 10)
        #expect(PinRules.opacityStep(forDelta: 90) == 30)
        #expect(PinRules.clampOpacity(0.02) == 0.1)
        #expect(PinRules.clampOpacity(1.5) == 1)
    }

    @Test func 缩放不小于60乘30也不超过800() {
        let size = CGSize(width: 300, height: 100)
        #expect(PinRules.clampScale(5, baseSize: size) == 30)    // 高度 30 点 → 30%
        #expect(PinRules.clampScale(2000, baseSize: size) == 800)
        #expect(PinRules.clampScale(150, baseSize: size) == 150)
    }

    @Test func 超大图片初始缩小到屏幕90以内() {
        #expect(PinRules.initialScale(imageSize: CGSize(width: 400, height: 300), screenSize: CGSize(width: 1440, height: 900)) == 100)
        #expect(PinRules.initialScale(imageSize: CGSize(width: 2880, height: 900), screenSize: CGSize(width: 1440, height: 900)) == 45)
    }

    @Test func 以鼠标位置为中心缩放() {
        // 窗口 (100,100) 大小 200×100，鼠标在窗口内 (50,50)，放大到 200%
        let frame = PinImageOps.zoomedFrame(CGRect(x: 100, y: 100, width: 200, height: 100), from: 100, to: 200,
                                            anchor: CGPoint(x: 50, y: 50))
        #expect(frame == CGRect(x: 50, y: 50, width: 400, height: 200))
        // 鼠标下的点（屏幕坐标 150,150）缩放前后不动：新窗口里对应 (100,100)，即 50+100
    }
}

struct PinImageOpsTests {
    /// 2×1 的图：左红右蓝
    func makeImage() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }

    /// 读像素颜色（原点左上），返回 "R" / "B"
    func color(_ image: CGImage, _ x: Int, _ y: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes[0] > 200 ? "R" : (bytes[2] > 200 ? "B" : "?")
    }

    @Test func 向左旋转后红色在下() throws {
        let image = try #require(PinImageOps.apply(.rotateLeft, to: makeImage()))
        #expect(image.width == 1 && image.height == 2)
        // 左红右蓝逆时针转 90°：右边（蓝）转到上面，左边（红）转到下面
        #expect(color(image, 0, 0) == "B")
        #expect(color(image, 0, 1) == "R")
    }

    @Test func 向右旋转后红色在上() throws {
        let image = try #require(PinImageOps.apply(.rotateRight, to: makeImage()))
        #expect(color(image, 0, 0) == "R")
        #expect(color(image, 0, 1) == "B")
    }

    @Test func 水平翻转左右互换() throws {
        let image = try #require(PinImageOps.apply(.flipHorizontal, to: makeImage()))
        #expect(color(image, 0, 0) == "B")
        #expect(color(image, 1, 0) == "R")
    }

    @Test func 文字转成图片带边距和倍率() throws {
        let text = NSAttributedString(string: "贴图", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let image = try #require(PinImageOps.image(from: text, scale: 2))
        // 四周各 10 点边距，2 倍像素
        #expect(image.width > 40 * 2 && image.height > 20 * 2)
        #expect(image.width % 2 == 0)
        #expect(PinImageOps.image(from: NSAttributedString(string: ""), scale: 2) == nil)
    }
}

struct PinGlowTests {
    /// 20×20 像素的白图
    func makeWhite() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        return context.makeImage()!
    }

    /// 读一个像素的 RGBA（原点左上）
    func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    @Test func 四周各留6点() throws {
        // 1 倍图：留边 6 像素
        let image = try #require(PinImageOps.decorated(makeWhite(), pixelScale: 1, cornerRadius: 0, glow: nil))
        #expect(image.width == 32 && image.height == 32)
        #expect(rgba(image, 16, 16) == [255, 255, 255, 255])  // 中间是原图
        #expect(rgba(image, 2, 16)[3] == 0)                   // 不画光晕时留边透明
    }

    @Test func 选中时留边里是蓝色光晕() throws {
        let image = try #require(PinImageOps.decorated(makeWhite(), pixelScale: 1, cornerRadius: 0,
                                                       glow: PinRules.activeGlow))
        let edge = rgba(image, 4, 16)  // 紧贴图片左边的留边
        #expect(edge[3] > 0)            // 有光晕
        #expect(edge[2] > edge[0])      // 偏蓝
    }

    @Test func 圆角会切掉四角() throws {
        let image = try #require(PinImageOps.decorated(makeWhite(), pixelScale: 1, cornerRadius: 8, glow: nil))
        #expect(rgba(image, 6, 6)[3] == 0)        // 原图左上角已被切掉
        #expect(rgba(image, 16, 6)[3] == 255)     // 上边中间还在
    }

    @Test func 贴回原位时窗口比选区四周大6点() {
        #expect(PinRules.windowFrame(forContent: CGRect(x: 100, y: 100, width: 50, height: 40))
                == CGRect(x: 94, y: 94, width: 62, height: 52))
    }
}

@MainActor
struct PinPasteboardTests {
    @Test func 剪贴板文字能转成贴图() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("xtools.tests.\(UUID().uuidString)"))
        board.clearContents()
        board.setString("hello", forType: .string)
        let (image, scale) = try #require(PinManager.image(from: board))
        #expect(image.width > 0 && scale > 0)
        board.releaseGlobally()
    }

    @Test func 空剪贴板没有可贴内容() {
        let board = NSPasteboard(name: NSPasteboard.Name("xtools.tests.\(UUID().uuidString)"))
        board.clearContents()
        #expect(PinManager.image(from: board) == nil)
        board.releaseGlobally()
    }
}

struct PinSettingsTests {
    @Test func 默认值和iShot一致() {
        let defaults = UserDefaults(suiteName: "xtools.tests.\(UUID().uuidString)")!
        let settings = PinSettings(store: SettingsStore(defaults: defaults).scoped("pin"))
        #expect(settings.showsControls && settings.doubleClickClose && !settings.pinnedToOneSpace)
        #expect(settings.cornerRadius == 8)
        #expect(settings.defaultOpacity == 1)
        #expect(settings.pasteHotkey?.displayName == "F3")
        #expect(settings.toggleHotkey?.displayName == "⇧F3")
    }
}
