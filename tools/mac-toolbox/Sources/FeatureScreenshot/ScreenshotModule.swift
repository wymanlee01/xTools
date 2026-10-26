import AppKit
import ToolboxCore
import UniformTypeIdentifiers

/// 截图模块：快捷键 → 冻结屏幕 → 框选 → 标注 → 复制 / 保存 / 贴图 / OCR
/// 同时实现 CaptureService，给 OCR、录屏模块提供“只框选”和“截固定区域”
@MainActor
public final class ScreenshotModule: ToolModule, CaptureService {
    public let id = "screenshot"
    public let title = "截图"
    public let requiredPermissions: [Permission] = [.screenRecording]

    private var context: ToolContext?
    private var store: SettingsStore?
    private var session: CaptureSession?
    /// 只框选模式的回调（OCR、录屏）
    private var regionCompletion: ((CaptureResult?) -> Void)?

    private var settings: ScreenshotSettings? { store.map(ScreenshotSettings.init) }

    /// 正在截屏、遮罩还没显示出来
    private var isStartingCapture = false

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "截图", action: #selector(menuCapture), keyEquivalent: "")
        item.target = self
        item.setHotkey(settings?.captureHotkey)
        return [item]
    }

    public func start(context: ToolContext) {
        self.context = context
        store = context.settings.scoped(id)
        context.services.register(CaptureService.self, self)
        registerHotkey()
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
        session?.finish(.cancel)
    }

    public func reloadSettings() {
        registerHotkey()
    }

    public func settingsPages() -> [SettingsPageInfo] {
        guard let store else { return [] }
        return [
            ScreenshotSettingsPage.make(store: store) { [weak self] in self?.registerHotkey() },
            AnnotationSettingsPage.make(store: store),
        ]
    }

    /// 按设置注册截图快捷键（默认 F1；系统没开“标准功能键”时需按 fn+F1）
    private func registerHotkey() {
        guard let context, let hotkey = settings?.captureHotkey else {
            context?.hotkeys.unregisterAll(owner: id)
            return
        }
        context.hotkeys.unregisterAll(owner: id)
        do {
            try context.hotkeys.register(hotkey, owner: id) { [weak self] in self?.beginCapture() }
        } catch {
            NSLog("[screenshot] 快捷键注册失败：\(error)")
        }
    }

    @objc private func menuCapture() {
        beginCapture()
    }

    // MARK: - CaptureService

    public func selectRegion(purpose: CapturePurpose, completion: @escaping (CaptureResult?) -> Void) {
        guard session == nil else { completion(nil); return }
        regionCompletion = completion
        beginCapture(purpose: purpose)
    }

    /// 截取固定区域：截下所在屏幕再裁出这块
    public func captureRegion(_ frame: CGRect, completion: @escaping (CaptureResult?) -> Void) {
        guard context?.permissions.isGranted(.screenRecording) == true else { completion(nil); return }
        Task { @MainActor in
            guard let screens = try? await ScreenCapturer.captureAllScreens(),
                  let frozen = screens.first(where: { $0.screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
            else { completion(nil); return }
            let local = frame.offsetBy(dx: -frozen.screen.frame.minX, dy: -frozen.screen.frame.minY)
            let pixels = SelectionGeometry.pixelRect(for: local, viewHeight: frozen.screen.frame.height, scale: frozen.scale,
                                                     imageSize: CGSize(width: frozen.image.width, height: frozen.image.height))
            guard let image = frozen.image.cropping(to: pixels) else { completion(nil); return }
            completion(CaptureResult(image: image, frame: frame, scale: frozen.scale, displayID: frozen.screen.displayID))
        }
    }

    // MARK: - 截图

    /// 开始一次截图；purpose 不为空时是只框选模式
    func beginCapture(purpose: CapturePurpose? = nil) {
        // 截屏要零点几秒，期间 session 还没设上；用这个标记保证同一时间只开一个截图，
        // 否则后开的会顶掉先开的，先开的遮罩没人管，Esc、右键都退不出
        guard session == nil, !isStartingCapture, let context, let settings else { return }
        guard context.permissions.isGranted(.screenRecording) else {
            context.permissions.request(.screenRecording)
            return
        }
        // 先取窗口列表再截图，保证两者是同一时刻的状态
        let windows = ScreenCapturer.visibleWindows()
        isStartingCapture = true
        Task { @MainActor [weak self] in
            defer { self?.isStartingCapture = false }
            do {
                let screens = try await ScreenCapturer.captureAllScreens(showsCursor: settings.captureCursor)
                let shortcuts = ToolShortcuts(settings: settings.store)
                let session = CaptureSession(screens: screens, windows: windows, shortcuts: shortcuts,
                                             settings: settings, purpose: purpose) { result, output in
                    self?.handle(result, output: output)
                }
                self?.session = session
                // 从托盘菜单打开时按的快捷键：屏幕已冻结（截到了菜单），这时再收起菜单
                context.hotkeys.dismissOpenMenu()
                session.show()
            } catch {
                NSLog("[screenshot] 截屏失败：\(error)")
            }
        }
    }

    private func handle(_ result: CaptureSession.Result, output: CaptureOutput?) {
        session = nil
        // 只框选模式：把选区交回调用方（取消时回调 nil）
        if let completion = regionCompletion {
            regionCompletion = nil
            if case .confirm = result, let output, let frame = output.frame {
                completion(CaptureResult(image: output.image, frame: frame, scale: output.scale, displayID: output.displayID))
            } else {
                completion(nil)
            }
            return
        }
        guard let settings else { return }
        if case .copyColor(let text) = result {
            context?.pasteboard.write(string: text, source: id)
            return
        }
        guard let output else { return }
        if settings.playSound, result != .ocr { ScreenshotOutput.playSound() }

        // 贴图、OCR 用原图（贴图有自己的圆角和光晕）；复制、保存按设置加圆角和阴影
        switch result {
        case .pin:
            context?.services.resolve(PinService.self)?.pin(image: output.image, frame: output.frame, scale: output.scale)
            return
        case .ocr:
            context?.services.resolve(OCRService.self)?.recognize(image: output.image, frame: output.frame)
            return
        default:
            break
        }
        let image = ScreenshotOutput.applyEffects(to: output.image, pixelScale: output.scale, settings: settings)
        switch result {
        case .copy:
            copy(image)
        case .save:
            // 保存至文件时同时保存至剪切板
            if save(image, scale: output.scale, settings: settings) != nil, settings.alsoCopy { copy(image) }
        case .saveAndCopy:
            _ = save(image, scale: output.scale, settings: settings)
            copy(image)
        case .saveAndOpen:
            if let url = save(image, scale: output.scale, settings: settings) {
                let app = URL(fileURLWithPath: settings.openAppPath)
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
        case .pin, .ocr, .confirm, .copyColor, .cancel:
            break
        }
    }

    private func copy(_ image: CGImage) {
        context?.pasteboard.write(image: image, source: id)
    }

    /// 按设置的格式、路径、质量保存；返回保存的文件
    private func save(_ image: CGImage, scale: CGFloat, settings: ScreenshotSettings) -> URL? {
        let format = settings.format.isSupported ? settings.format : .png
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let name = "xTools_\(formatter.string(from: Date())).\(format.rawValue)"

        var url = URL(fileURLWithPath: settings.saveDirectory).appendingPathComponent(name)
        if settings.askPath {
            // 保存时选择路径
            let panel = NSSavePanel()
            panel.allowedContentTypes = [format.type]
            panel.nameFieldStringValue = name
            panel.directoryURL = URL(fileURLWithPath: settings.saveDirectory)
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
            url = chosen
        }
        guard let data = ScreenshotOutput.encode(image, pixelScale: scale, settings: settings) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("[screenshot] 保存失败：\(error)")
            return nil
        }
    }
}
