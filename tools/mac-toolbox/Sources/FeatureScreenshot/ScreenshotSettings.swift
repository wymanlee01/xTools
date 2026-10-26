import AppKit
import Carbon.HIToolbox
import ToolboxCore
import UniformTypeIdentifiers

/// 图片保存格式（选项同 iShot；webp 系统不支持写入，置灰）
enum ImageFormat: String, CaseIterable {
    case jpg, png, tiff, webp, heic, pdf

    var isSupported: Bool { self != .webp }
    var type: UTType {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .webp: return .webP
        case .heic: return .heic
        case .pdf: return .pdf
        }
    }
}

/// 双击鼠标左键触发的动作（选项同 iShot；OCR 还没做，置灰）
enum DoubleClickAction: Int, CaseIterable {
    case none, pin, ocr, save, copy, saveAndCopy

    var title: String { ["无动作", "贴图", "OCR", "保存至本地", "保存至剪切板", "保存至本地和剪切板"][rawValue] }
}

/// 截图模块的设置，键名都在 “screenshot.” 下，默认值取自 iShot 的默认设置
struct ScreenshotSettings {
    let store: SettingsStore

    static let defaultHotkey = Hotkey(keyCode: kVK_F1, modifiers: [])
    static let modifierKeys = ["Option", "Command", "Control"]

    // 快捷键与效果
    var captureHotkey: Hotkey? { store.hotkey("hotkey.capture", default: Self.defaultHotkey) }
    var captureCursor: Bool { store.bool("captureCursor", default: false) }
    var crosshair: Bool { store.bool("crosshair", default: true) }
    var rightClickExit: Bool { store.bool("rightClickExit", default: true) }
    var addShadow: Bool { store.bool("addShadow", default: true) }
    var shadowSize: Double { store.double("shadowSize", default: 18) }
    var shadowColor: NSColor {
        let parts = store.string("shadowColor", default: "0,0,0,0.3").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return NSColor.black.withAlphaComponent(0.3) }
        return NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: parts[3])
    }
    var addCorner: Bool { store.bool("addCorner", default: true) }
    var cornerSize: Double { store.double("cornerSize", default: 18) }

    // 保存
    var format: ImageFormat { ImageFormat(rawValue: store.string("format", default: "png")) ?? .png }
    var askPath: Bool { store.bool("askPath", default: false) }
    var saveDirectory: String {
        store.string("saveDirectory", default: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].path)
    }
    /// 普通质量：按 1 倍像素输出（默认高清，同 iShot nomalQualityImage = false）
    var normalQuality: Bool { store.bool("normalQuality", default: false) }
    var playSound: Bool { store.bool("playSound", default: true) }
    var alsoCopy: Bool { store.bool("alsoCopy", default: false) }
    var genericRGB: Bool { store.bool("genericRGB", default: true) }

    // 连贯动作
    var doubleClickAction: DoubleClickAction {
        DoubleClickAction(rawValue: store.int("doubleClickAction", default: DoubleClickAction.copy.rawValue)) ?? .copy
    }
    var doubleTapModifier: Int { store.int("doubleTapModifier", default: 0) }
    var openAppPath: String { store.string("openAppPath", default: "/System/Applications/Preview.app") }

    // 标注
    /// 工具栏弹窗响应时间（秒）
    var tipDelay: Double { store.double("tipDelay", default: 0.5) }

    func set(shadowColor color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        store.set("\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent),\(rgb.alphaComponent)", for: "shadowColor")
    }
}

/// 截图输出效果和导出
enum ScreenshotOutput {
    /// 加圆角和阴影（同 iShot：先切圆角，再四周留出阴影大小的边、模糊 = 大小 × 1.1、不偏移）
    static func applyEffects(to image: CGImage, pixelScale: CGFloat, settings: ScreenshotSettings) -> CGImage {
        var result = image
        if settings.addCorner, let rounded = roundCorners(result, radius: CGFloat(settings.cornerSize) * pixelScale) {
            result = rounded
        }
        if settings.addShadow, settings.shadowSize > 0,
           let shadowed = addShadow(result, size: CGFloat(settings.shadowSize) * pixelScale, color: settings.shadowColor.cgColor) {
            result = shadowed
        }
        return result
    }

    static func roundCorners(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let r = min(radius, CGFloat(min(w, h)) / 2)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        context.clip()
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    static func addShadow(_ image: CGImage, size: CGFloat, color: CGColor) -> CGImage? {
        let pad = Int(size)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width + pad * 2, height: image.height + pad * 2,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setShadow(offset: .zero, blur: size * 1.1, color: color)
        context.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// 按设置导出文件数据：普通质量缩到 1 倍；转换到 sRGB 颜色描述；按格式编码
    static func encode(_ image: CGImage, pixelScale: CGFloat, settings: ScreenshotSettings) -> Data? {
        var output = image
        if settings.normalQuality, pixelScale > 1, let scaled = resize(image, by: 1 / pixelScale) { output = scaled }
        if settings.genericRGB, let converted = resize(output, by: 1) { output = converted }

        let format = settings.format.isSupported ? settings.format : .png
        if format == .pdf { return pdfData(output, pointScale: settings.normalQuality ? 1 : pixelScale) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: settings.normalQuality ? 0.8 : 1.0] as CFDictionary
        CGImageDestinationAddImage(destination, output, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 缩放并画进 sRGB 画布（factor 为 1 时只做色彩转换）
    static func resize(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let w = max(1, Int(CGFloat(image.width) * factor)), h = max(1, Int(CGFloat(image.height) * factor))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    private static func pdfData(_ image: CGImage, pointScale: CGFloat) -> Data? {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: CGFloat(image.width) / pointScale, height: CGFloat(image.height) / pointScale)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// 截图声效（系统自带的“Screen Capture”）
    static func playSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
