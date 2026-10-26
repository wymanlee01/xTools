import AppKit
import AVFoundation
import ToolboxCore

/// 录屏模块：快捷键 → 框选区域（CaptureService）→ 倒计时 → 录制（可暂停）→ 停止 → 按设置保存
@MainActor
public final class RecordModule: ToolModule {
    public let id = "record"
    public let title = "录屏"
    public let requiredPermissions: [Permission] = [.screenRecording]

    private var context: ToolContext?
    private var settings: RecordSettings?

    // 录制中的状态
    private var recorder: ScreenRecorder?
    private var border: RecordingBorderWindow?
    private var statusItem: RecordingStatusItem?
    private var isPaused = false
    private var tempURL: URL?

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        let recording = recorder != nil
        let title = recording ? "停止录屏" : "开始录屏"
        let item = NSMenuItem(title: "\(title)  \(settings?.toggleHotkey?.displayName ?? "")", action: #selector(toggle),
                              keyEquivalent: "")
        item.target = self
        return [item]
    }

    public func start(context: ToolContext) {
        self.context = context
        settings = RecordSettings(store: context.settings.scoped(id))
        registerHotkeys()
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
        if recorder != nil { stopRecording() }
    }

    public func reloadSettings() {
        registerHotkeys()
    }

    public func settingsPages() -> [SettingsPageInfo] {
        guard let settings else { return [] }
        return [RecordSettingsPage.make(settings: settings) { [weak self] in self?.registerHotkeys() }]
    }

    private func registerHotkeys() {
        guard let context, let settings else { return }
        context.hotkeys.unregisterAll(owner: id)
        let pairs: [(Hotkey?, () -> Void)] = [
            (settings.toggleHotkey, { [weak self] in self?.toggle() }),
            (settings.pauseHotkey, { [weak self] in self?.togglePause() }),
        ]
        for (hotkey, action) in pairs {
            guard let hotkey else { continue }
            do {
                try context.hotkeys.register(hotkey, owner: id, action: action)
            } catch {
                NSLog("[record] 快捷键 \(hotkey.displayName) 注册失败：\(error)")
            }
        }
    }

    // MARK: - 开始 / 停止

    /// 开始/停止录屏
    @objc private func toggle() {
        if recorder != nil {
            stopRecording()
            return
        }
        guard let capture = context?.services.resolve(CaptureService.self) else { return }
        capture.selectRegion(purpose: .record) { [weak self] result in
            guard let self, let result else { return }
            self.countdownThenRecord(result)
        }
    }

    private func countdownThenRecord(_ region: CaptureResult) {
        guard let settings else { return }
        let countdown = CountdownWindow(center: CGPoint(x: region.frame.midX, y: region.frame.midY))
        countdown.run(seconds: settings.countdown) { [weak self] in
            self?.startRecording(region)
        }
    }

    private func startRecording(_ region: CaptureResult) {
        guard let settings,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID
              }) else { return }
        // ScreenCaptureKit 的区域：显示器内坐标、原点在左上
        let local = region.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let sourceRect = CGRect(x: local.minX, y: screen.frame.height - local.maxY, width: local.width, height: local.height)
        let fileType: AVFileType = settings.format == "mov" ? .mov : .mp4
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xTools-\(UUID().uuidString).\(settings.format)")
        let options = ScreenRecorder.Options(
            displayID: region.displayID, sourceRect: sourceRect, pixelScale: region.scale,
            frameRate: settings.frameRate, showsCursor: settings.showsCursor, showsClicks: settings.showsClicks,
            systemAudio: settings.systemAudio, microphone: settings.microphone, fileType: fileType, outputURL: url)

        let recorder = ScreenRecorder()
        self.recorder = recorder
        tempURL = url
        isPaused = false
        border = RecordingBorderWindow(frame: region.frame)
        border?.orderFrontRegardless()
        statusItem = RecordingStatusItem(pauseTitle: pauseMenuTitle(), stopTitle: "停止录制  \(settings.toggleHotkey?.displayName ?? "")",
                                         onPause: { [weak self] in self?.togglePause() },
                                         onStop: { [weak self] in self?.stopRecording() })
        Task { @MainActor in
            do {
                try await recorder.start(options)
            } catch {
                self.cleanUp()
                self.showError("开始录屏失败", error.localizedDescription)
            }
        }
    }

    /// 暂停/恢复录屏
    @objc private func togglePause() {
        guard let recorder else { return }
        isPaused.toggle()
        recorder.setPaused(isPaused)
        border?.isPaused = isPaused
        statusItem?.setPaused(isPaused, pauseTitle: pauseMenuTitle())
    }

    private func pauseMenuTitle() -> String {
        "\(isPaused ? "继续录制" : "暂停录制")  \(settings?.pauseHotkey?.displayName ?? "")"
    }

    private func stopRecording() {
        guard let recorder else { return }
        cleanUp()
        Task { @MainActor in
            guard let url = await recorder.stop() else {
                self.showError("录屏失败", "没有录到画面。")
                return
            }
            self.deliver(url)
        }
    }

    private func cleanUp() {
        recorder = nil
        border?.orderOut(nil)
        border = nil
        statusItem?.remove()
        statusItem = nil
    }

    // MARK: - 保存

    /// 按“保存方式”“保存路径”“完成时动作”处理录好的文件
    private func deliver(_ temp: URL) {
        guard let settings else { return }
        var target = temp
        // 0 本地文件、2 同时保存到剪切板和本地：移到保存路径
        if settings.saveMethod != 1 {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
            let name = "xTools录屏_\(formatter.string(from: Date())).\(temp.pathExtension)"
            var url = URL(fileURLWithPath: settings.saveDirectory).appendingPathComponent(name)
            if settings.askPath {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.directoryURL = URL(fileURLWithPath: settings.saveDirectory)
                NSApp.activate(ignoringOtherApps: true)
                guard panel.runModal() == .OK, let chosen = panel.url else { return }
                url = chosen
            }
            do {
                try FileManager.default.moveItem(at: temp, to: url)
                target = url
            } catch {
                showError("保存录屏失败", error.localizedDescription)
                return
            }
        }
        // 1 剪切板、2 同时：把文件放到剪切板，可直接粘贴到聊天软件或 Finder
        if settings.saveMethod != 0 {
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects([target as NSURL])
        }
        switch settings.finishAction {
        case 1: NSWorkspace.shared.open(target)
        case 2: NSWorkspace.shared.activateFileViewerSelecting([target])
        default: break
        }
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
