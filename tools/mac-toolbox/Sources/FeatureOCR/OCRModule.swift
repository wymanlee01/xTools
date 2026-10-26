import AppKit
import ToolboxCore

/// OCR 模块：全局快捷键框选识别、截图工具栏的 OCR 按钮（实现 OCRService）
@MainActor
public final class OCRModule: ToolModule, OCRService {
    public let id = "ocr"
    public let title = "OCR"
    public let requiredPermissions: [Permission] = [.screenRecording]

    private var context: ToolContext?
    private var settings: OCRSettings?
    private var window: OCRWindowController?
    /// 上一次识别的区域（固定区域模式下直接再截这里）
    private var lastFrame: CGRect?

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "OCR 识别文字  \(settings?.hotkey?.displayName ?? "")", action: #selector(startOCR),
                              keyEquivalent: "")
        item.target = self
        return [item]
    }

    public func start(context: ToolContext) {
        self.context = context
        settings = OCRSettings(store: context.settings.scoped(id))
        context.services.register(OCRService.self, self)
        registerHotkey()
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
    }

    public func reloadSettings() {
        registerHotkey()
    }

    public func settingsPages() -> [SettingsPageInfo] {
        guard let settings else { return [] }
        return [OCRSettingsPage.make(settings: settings) { [weak self] in self?.registerHotkey() }]
    }

    private func registerHotkey() {
        guard let context else { return }
        context.hotkeys.unregisterAll(owner: id)
        guard let hotkey = settings?.hotkey else { return }
        do {
            try context.hotkeys.register(hotkey, owner: id) { [weak self] in self?.startOCR() }
        } catch {
            NSLog("[ocr] 快捷键注册失败：\(error)")
        }
    }

    /// 全局快捷键：框选后识别；固定区域模式下直接识别上次的区域
    @objc private func startOCR() {
        guard let capture = context?.services.resolve(CaptureService.self) else { return }
        if settings?.fixedRegion == true, let lastFrame {
            capture.captureRegion(lastFrame) { [weak self] result in
                guard let result else { return }
                self?.recognize(image: result.image, frame: result.frame)
            }
            return
        }
        capture.selectRegion(purpose: .ocr) { [weak self] result in
            guard let result else { return }
            self?.recognize(image: result.image, frame: result.frame)
        }
    }

    // MARK: - OCRService

    public func recognize(image: CGImage, frame: CGRect?) {
        guard let settings, let pasteboard = context?.pasteboard else { return }
        if let frame { lastFrame = frame }
        let showWindow = !settings.copyWithoutWindow
        if showWindow {
            if window == nil { window = OCRWindowController(settings: settings, pasteboard: pasteboard) }
            window?.showLoading()
        }
        // Vision 识别比较耗时，放到后台线程
        Task.detached(priority: .userInitiated) {
            let text = TextRecognizer.recognize(image).text
            await MainActor.run { [weak self] in self?.deliver(text, showWindow: showWindow) }
        }
    }

    private func deliver(_ text: String, showWindow: Bool) {
        guard let settings else { return }
        let output = settings.joinLines ? TextRecognizer.joinLines(text) : text
        if settings.alwaysCopy || !showWindow { context?.pasteboard.write(string: output, source: id) }
        if showWindow {
            window?.show(text)
        } else {
            HUD.show(text.isEmpty ? "没有识别到文字" : "识别结果已复制到剪切板")
        }
    }
}

/// 屏幕中央短暂显示的提示
@MainActor
enum HUD {
    static func show(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 40, height: 44)
        let screen = NSScreen.main?.frame ?? .zero
        let panel = NSPanel(contentRect: CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        label.frame.origin = CGPoint(x: 20, y: (size.height - label.frame.height) / 2)
        background.addSubview(label)
        panel.contentView = background
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { panel.orderOut(nil) }
    }
}
