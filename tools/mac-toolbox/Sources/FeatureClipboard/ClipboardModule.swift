import AppKit
import ApplicationServices
import ToolboxCore

/// 粘贴板模块：记录剪贴板历史；快捷键打开面板，选中后粘贴到当前应用
@MainActor
public final class ClipboardModule: ToolModule {
    public let id = "clipboard"
    public let title = "粘贴板"
    /// 自动粘贴要模拟 ⌘V，需要辅助功能权限（不授权也能用，只是要手动按 ⌘V）
    public let requiredPermissions: [Permission] = [.accessibility]

    private var context: ToolContext?
    private var settings: ClipboardSettings?
    private var store: ClipStore?
    private var panel: ClipboardPanel?

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "粘贴板", action: #selector(togglePanel), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: nil)
        item.setHotkey(settings?.hotkey)
        return [item]
    }

    public func start(context: ToolContext) {
        self.context = context
        settings = ClipboardSettings(store: context.settings.scoped(id))
        store = ClipStore(directory: ClipStore.defaultDirectory)
        context.pasteboard.onChange { [weak self] board in self?.record(board) }
        registerHotkey()
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
        panel?.hide()
    }

    public func reloadSettings() {
        registerHotkey()
    }

    public func settingsPages() -> [SettingsPageInfo] {
        guard let settings else { return [] }
        return [ClipboardSettingsPage.make(settings: settings, onHotkeyChange: { [weak self] in self?.registerHotkey() },
                                           onClear: { [weak self] in self?.confirmClear() })]
    }

    private func registerHotkey() {
        guard let context else { return }
        context.hotkeys.unregisterAll(owner: id)
        guard let hotkey = settings?.hotkey else { return }
        do {
            try context.hotkeys.register(hotkey, owner: id) { [weak self] in self?.togglePanel() }
        } catch {
            NSLog("[clipboard] 快捷键注册失败：\(error)")
        }
    }

    // MARK: - 记录

    private func record(_ board: NSPasteboard) {
        guard let settings, let store else { return }
        // 从历史里粘贴时我们自己写的剪贴板，不重复记录
        if board.string(forType: PasteboardService.sourceType) == id { return }
        let source = NSWorkspace.shared.frontmostApplication
        if let bundleID = source?.bundleIdentifier, settings.ignoredApps.contains(bundleID) { return }
        let options = ClipCapture.Options(recordImages: settings.recordImages, recordFiles: settings.recordFiles)
        guard let item = ClipCapture.read(board, store: store, options: options, source: source) else { return }
        store.add(item, limit: settings.limit, keepDays: settings.keepDays == 0 ? nil : settings.keepDays)
        if panel?.isVisible == true { panel?.reload() }
    }

    // MARK: - 面板

    @objc private func togglePanel() {
        guard let store else { return }
        if panel == nil {
            let panel = ClipboardPanel(store: store)
            panel.onPaste = { [weak self] item, plain in self?.paste(item, plainText: plain) }
            panel.onCopy = { [weak self] item in self?.copy(item, plainText: false); self?.panel?.hide(); HUD.show("已拷贝") }
            panel.onTogglePin = { [weak self] item in self?.store?.togglePin(id: item.id); self?.panel?.reload() }
            panel.onDelete = { [weak self] item in self?.store?.delete(id: item.id); self?.panel?.reload() }
            panel.onPinToScreen = { [weak self] item in self?.pinToScreen(item) }
            panel.onClearAll = { [weak self] in self?.confirmClear() }
            panel.onOpenSettings = { NotificationCenter.default.post(name: .xToolsOpenSettings, object: nil) }
            // 调整后的大小存在设置里，下次按这个大小弹出
            panel.savedSize = { [weak self] in
                let value = self?.settings?.store.string("panelSize", default: "") ?? ""
                return value.isEmpty ? nil : value
            }
            panel.saveSize = { [weak self] value in self?.settings?.store.set(value, for: "panelSize") }
            self.panel = panel
        }
        guard let panel else { return }
        panel.isVisible ? panel.hide() : panel.show()
    }

    /// 写回剪贴板（打上本模块的来源标记，避免被重复记录），并移到历史最前面
    private func copy(_ item: ClipItem, plainText: Bool) {
        guard let store else { return }
        context?.pasteboard.write(ClipCapture.pasteboardItems(for: item, store: store, plainText: plainText), source: id)
        store.moveToTop(id: item.id)
    }

    /// 粘贴到当前应用：面板不抢焦点，收起后直接模拟 ⌘V
    private func paste(_ item: ClipItem, plainText: Bool) {
        guard let settings else { return }
        copy(item, plainText: plainText || settings.plainTextByDefault)
        panel?.hide()
        guard settings.autoPaste else { HUD.show("已拷贝，按 ⌘V 粘贴"); return }
        guard AXIsProcessTrusted() else {
            HUD.show("已拷贝。开启“辅助功能”权限后可自动粘贴")
            context?.permissions.request(.accessibility)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.sendCommandV() }
    }

    /// 模拟按下 ⌘V
    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// 图片贴到屏幕（通过底座的 PinService，不 import 贴图模块）
    private func pinToScreen(_ item: ClipItem) {
        guard let url = store?.imageURL(for: item), let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        panel?.hide()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        context?.services.resolve(PinService.self)?.pin(image: cg, frame: nil, scale: scale)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "清空粘贴板历史？"
        alert.informativeText = "收藏的记录会保留。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store?.clearUnpinned()
        panel?.reload()
    }
}

