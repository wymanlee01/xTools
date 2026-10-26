import AppKit
import ToolboxCore

/// 贴图设置（默认值同 iShot：圆角 8、不透明、显示控件）
struct PinSettings {
    var cornerRadius: CGFloat = 8
    var defaultOpacity: CGFloat = 1
    var showsControls = true
}

/// 管理所有贴图，对外提供 PinService
@MainActor
final class PinManager: PinService {
    let pasteboard: PasteboardService
    let settings = PinSettings()
    private var pins: [PinController] = []
    private var hidden = false

    init(pasteboard: PasteboardService) {
        self.pasteboard = pasteboard
    }

    var count: Int { pins.count }

    // MARK: - PinService

    func pin(image: CGImage, frame: CGRect?, scale: CGFloat) {
        let controller = PinController(image: image, frame: frame, pixelScale: scale, manager: self)
        pins.append(controller)
        if hidden { showAll() }
        controller.show()
    }

    // MARK: - 剪贴板贴图

    /// 把剪贴板里的图片、图片文件、PDF 或文字贴到屏幕上；没有可贴内容时返回 false
    @discardableResult
    func pinFromPasteboard(_ board: NSPasteboard = .general) -> Bool {
        guard let (image, scale) = Self.image(from: board) else { return false }
        pin(image: image, frame: nil, scale: scale)
        return true
    }

    /// 从剪贴板取图：先图片、再文件（图片或 PDF）、最后文字（按屏幕倍率渲染）
    static func image(from board: NSPasteboard) -> (CGImage, CGFloat)? {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let image = NSImage(contentsOf: url), let result = cgImage(of: image) {
            return result
        }
        if let image = NSImage(pasteboard: board), let result = cgImage(of: image) {
            return result
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        if let rich = board.readObjects(forClasses: [NSAttributedString.self])?.first as? NSAttributedString,
           let image = PinImageOps.image(from: rich, scale: scale) {
            return (image, scale)
        }
        if let text = board.string(forType: .string), !text.isEmpty {
            let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14),
                                                                           .foregroundColor: NSColor.black])
            if let image = PinImageOps.image(from: attributed, scale: scale) { return (image, scale) }
        }
        return nil
    }

    /// NSImage 转 CGImage，同时算出像素倍率
    private static func cgImage(of image: NSImage) -> (CGImage, CGFloat)? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard image.size.width > 0, let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cg, CGFloat(cg.width) / image.size.width)
    }

    // MARK: - 全部贴图

    func remove(_ controller: PinController) {
        pins.removeAll { $0 === controller }
    }

    func closeAll() {
        for pin in pins { pin.window.orderOut(nil) }
        pins.removeAll()
        hidden = false
    }

    /// 隐藏/显示全部贴图
    func toggleAll() {
        hidden ? showAll() : hideAll()
    }

    private func hideAll() {
        for pin in pins { pin.window.orderOut(nil) }
        hidden = true
    }

    private func showAll() {
        for pin in pins { pin.window.orderFront(nil) }
        hidden = false
    }
}
