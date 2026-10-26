import AppKit
import Carbon.HIToolbox
import ToolboxCore

/// 贴图模块：注册 PinService 供截图模块使用；快捷键把剪贴板贴到屏幕、隐藏/显示全部贴图
@MainActor
public final class PinModule: ToolModule {
    public let id = "pin"
    public let title = "贴图"
    public let requiredPermissions: [Permission] = []

    /// 默认快捷键：F3 贴剪贴板，⇧F3 隐藏/显示全部（iShot 用 ⌥S、⌥H，这里避开）
    static let pasteHotkey = Hotkey(keyCode: kVK_F3, modifiers: [])
    static let toggleHotkey = Hotkey(keyCode: kVK_F3, modifiers: [.shift])

    private var context: ToolContext?
    private var manager: PinManager?

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        [
            makeItem("贴剪贴板到屏幕  F3", #selector(pinPasteboard)),
            makeItem("隐藏/显示全部贴图  ⇧F3", #selector(toggleAll)),
            makeItem("关闭全部贴图", #selector(closeAll)),
        ]
    }

    public func start(context: ToolContext) {
        self.context = context
        let manager = PinManager(pasteboard: context.pasteboard)
        self.manager = manager
        context.services.register(PinService.self, manager)
        do {
            try context.hotkeys.register(Self.pasteHotkey, owner: id) { [weak self] in self?.pinPasteboard() }
            try context.hotkeys.register(Self.toggleHotkey, owner: id) { [weak self] in self?.toggleAll() }
        } catch {
            NSLog("[pin] 快捷键注册失败：\(error)")
        }
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
        manager?.closeAll()
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pinPasteboard() {
        guard manager?.pinFromPasteboard() == false else { return }
        // 和 iShot 的提示一致
        let alert = NSAlert()
        alert.messageText = "⚠️ 剪切板中无图片可用于贴图。"
        alert.informativeText = "可以贴图片、图片文件、PDF 或文字。"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleAll() { manager?.toggleAll() }
    @objc private func closeAll() { manager?.closeAll() }
}
