import AppKit
import Carbon.HIToolbox
import ToolboxCore

/// 截图模块：快捷键 → 冻结屏幕 → 框选 → 复制或保存
@MainActor
public final class ScreenshotModule: ToolModule {
    public let id = "screenshot"
    public let title = "截图"
    public let requiredPermissions: [Permission] = [.screenRecording]

    /// 默认快捷键 F1（不带修饰键；系统没开“标准功能键”时需按 fn+F1）
    static let defaultHotkey = Hotkey(keyCode: kVK_F1, modifiers: [])

    private var context: ToolContext?
    private var settings: SettingsStore?
    private var session: CaptureSession?

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "区域截图  F1", action: #selector(menuCapture), keyEquivalent: "")
        item.target = self
        return [item]
    }

    public func start(context: ToolContext) {
        self.context = context
        settings = context.settings.scoped(id)
        do {
            try context.hotkeys.register(Self.defaultHotkey, owner: id) { [weak self] in self?.beginCapture() }
        } catch {
            NSLog("[screenshot] 快捷键注册失败：\(error)")
        }
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
        session?.finish(.cancel)
    }

    @objc private func menuCapture() {
        beginCapture()
    }

    /// 开始一次截图
    func beginCapture() {
        guard session == nil, let context else { return }
        guard context.permissions.isGranted(.screenRecording) else {
            context.permissions.request(.screenRecording)
            return
        }
        // 先取窗口列表再截图，保证两者是同一时刻的状态
        let windows = ScreenCapturer.visibleWindows()
        Task { @MainActor [weak self] in
            do {
                let screens = try await ScreenCapturer.captureAllScreens()
                guard let settings = self?.settings else { return }
                let shortcuts = ToolShortcuts(settings: settings)
                let session = CaptureSession(screens: screens, windows: windows, shortcuts: shortcuts) { result, image in
                    self?.handle(result, image: image)
                }
                self?.session = session
                session.show()
            } catch {
                NSLog("[screenshot] 截屏失败：\(error)")
            }
        }
    }

    private func handle(_ result: CaptureSession.Result, image: CGImage?) {
        session = nil
        switch result {
        case .copy:
            if let image { context?.pasteboard.write(image: image, source: id) }
        case .save:
            if let image { save(image) }
        case .copyColor(let text):
            context?.pasteboard.write(string: text, source: id)
        case .cancel:
            break
        }
    }

    /// 保存为 PNG，目录可在设置里改，默认桌面
    private func save(_ image: CGImage) {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.path
        let directory = settings?.string("saveDirectory", default: desktop) ?? desktop
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let url = URL(fileURLWithPath: directory).appendingPathComponent("xTools_\(formatter.string(from: Date())).png")

        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url)
        } catch {
            NSLog("[screenshot] 保存失败：\(error)")
        }
    }
}
