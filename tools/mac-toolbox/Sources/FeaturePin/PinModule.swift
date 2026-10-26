import AppKit
import ToolboxCore

/// 贴图模块：注册 PinService 供截图模块使用；快捷键把剪贴板贴到屏幕、隐藏/显示全部贴图
@MainActor
public final class PinModule: ToolModule {
    public let id = "pin"
    public let title = "贴图"
    public let requiredPermissions: [Permission] = []

    private var context: ToolContext?
    private var manager: PinManager?
    private var settings: PinSettings?

    public init() {}

    public func menuItems() -> [NSMenuItem] {
        // 菜单只留常用的一项；隐藏/显示全部贴图用快捷键，关闭全部在贴图右键菜单里
        let item = makeItem("贴图", #selector(pinPasteboard))
        item.setHotkey(settings?.pasteHotkey)
        return [item]
    }

    public func start(context: ToolContext) {
        self.context = context
        let settings = PinSettings(store: context.settings.scoped(id))
        self.settings = settings
        let manager = PinManager(pasteboard: context.pasteboard, settings: settings)
        self.manager = manager
        context.services.register(PinService.self, manager)
        registerHotkeys()
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
        manager?.closeAll()
    }

    public func reloadSettings() {
        registerHotkeys()
    }

    public func settingsPages() -> [SettingsPageInfo] {
        guard let settings else { return [] }
        return [PinSettingsPage.make(settings: settings) { [weak self] in self?.registerHotkeys() }]
    }

    /// 按设置注册快捷键；设置为“无”的不注册
    private func registerHotkeys() {
        guard let context, let settings else { return }
        context.hotkeys.unregisterAll(owner: id)
        let pairs: [(Hotkey?, () -> Void)] = [
            (settings.pasteHotkey, { [weak self] in self?.pinPasteboard() }),
            (settings.toggleHotkey, { [weak self] in self?.toggleAll() }),
        ]
        for (hotkey, action) in pairs {
            guard let hotkey else { continue }
            do {
                try context.hotkeys.register(hotkey, owner: id, action: action)
            } catch {
                NSLog("[pin] 快捷键 \(hotkey.displayName) 注册失败：\(error)")
            }
        }
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

    private func toggleAll() { manager?.toggleAll() }
}
