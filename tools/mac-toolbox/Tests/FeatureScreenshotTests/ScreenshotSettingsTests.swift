import CoreGraphics
import Foundation
import ImageIO
import Testing
import ToolboxCore
@testable import FeatureScreenshot

struct ScreenshotSettingsTests {
    func makeSettings() -> ScreenshotSettings {
        let defaults = UserDefaults(suiteName: "xtools.tests.\(UUID().uuidString)")!
        return ScreenshotSettings(store: SettingsStore(defaults: defaults).scoped("screenshot"))
    }

    @Test func 默认值和iShot一致() {
        let settings = makeSettings()
        #expect(settings.captureHotkey == ScreenshotSettings.defaultHotkey)
        #expect(!settings.captureCursor)
        #expect(settings.crosshair)
        #expect(settings.rightClickExit)
        #expect(settings.addShadow && settings.shadowSize == 18)
        #expect(settings.addCorner && settings.cornerSize == 18)
        #expect(settings.format == .png)
        #expect(settings.playSound && !settings.alsoCopy && settings.genericRGB)
        #expect(settings.doubleClickAction == .copy)  // iShot doubleLeftButtonAction = 4
        #expect(settings.tipDelay == 0.5)
    }

    /// 40×20 像素的白图
    func makeWhite() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return context.makeImage()!
    }

    @Test func 阴影四周留出阴影大小的边() {
        let settings = makeSettings()
        // 默认阴影 18 点，2 倍图每边多 36 像素
        let image = ScreenshotOutput.applyEffects(to: makeWhite(), pixelScale: 2, settings: settings)
        #expect(image.width == 40 + 72 && image.height == 20 + 72)
    }

    @Test func 关掉阴影和圆角时原样输出() {
        let settings = makeSettings()
        settings.store.set(false, for: "addShadow")
        settings.store.set(false, for: "addCorner")
        let image = ScreenshotOutput.applyEffects(to: makeWhite(), pixelScale: 2, settings: settings)
        #expect(image.width == 40 && image.height == 20)
    }

    @Test func 按格式编码() throws {
        let settings = makeSettings()
        let png = try #require(ScreenshotOutput.encode(makeWhite(), pixelScale: 1, settings: settings))
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        settings.store.set("jpg", for: "format")
        let jpg = try #require(ScreenshotOutput.encode(makeWhite(), pixelScale: 1, settings: settings))
        #expect(jpg.prefix(2) == Data([0xFF, 0xD8]))
        settings.store.set("pdf", for: "format")
        let pdf = try #require(ScreenshotOutput.encode(makeWhite(), pixelScale: 1, settings: settings))
        #expect(pdf.prefix(4) == Data("%PDF".utf8))
    }

    @Test func 普通质量缩成1倍() throws {
        let settings = makeSettings()
        settings.store.set(true, for: "normalQuality")
        let data = try #require(ScreenshotOutput.encode(makeWhite(), pixelScale: 2, settings: settings))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 20 && image.height == 10)
    }
}
