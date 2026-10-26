import AppKit
import FeatureClipboard
import FeatureOCR
import FeaturePin
import FeatureRecord
import FeatureScreenshot
import FeatureWindow
import ToolboxCore

/// 组装底座和各功能模块，生成菜单栏菜单和偏好设置窗口
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var context: ToolContext?
    private var settingsWindow: SettingsWindowController?
    private var updater: UpdateController?

    /// 新增功能模块只需加到这里
    private let modules: [ToolModule] = [
        ScreenshotModule(),
        PinModule(),
        RecordModule(),
        OCRModule(),
        ClipboardModule(),
        WindowModule(),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = ToolContext(settings: SettingsStore(), hotkeys: HotkeyCenter(),
                                  permissions: PermissionCenter(), pasteboard: PasteboardService(),
                                  services: ServiceRegistry())
        self.context = context
        modules.forEach { $0.start(context: context) }
        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .xToolsOpenSettings, object: nil)
        statusItem?.isVisible = !context.settings.bool(GeneralSettingsPage.hideMenuBarIconKey, default: false)
        let updater = UpdateController(settings: context.settings)
        self.updater = updater
        updater.checkOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        modules.forEach { $0.stop() }
    }

    /// 菜单栏图标隐藏时，再次打开 xTools.app 就打开偏好设置（同 iShot）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "xTools")
        let menu = NSMenu()
        // 每次打开菜单时重建，快捷键改了也能显示最新的
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// 菜单打开期间按快捷键也能直接执行（见 HotkeyCenter.watchKeys）
    func menuWillOpen(_ menu: NSMenu) {
        context?.hotkeys.watchKeys(whileOpen: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        context?.hotkeys.stopWatchingKeys()
    }

    /// 菜单打开时按到已注册的快捷键（F1 等）：不让系统按菜单项的 keyEquivalent 处理（会先收起菜单，截图截不到菜单），
    /// 交给 HotkeyCenter.watchKeys 执行；其他按键（⌘,、⌘Q）照常找对应的菜单项
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        NSLog("[DBG] menuHasKeyEquivalent code=\(event.keyCode)")
        guard context?.hotkeys.isRegistered(event) != true else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let item = menu.items.first(where: {
            !$0.keyEquivalent.isEmpty && $0.keyEquivalent == event.charactersIgnoringModifiers?.lowercased()
                && $0.keyEquivalentModifierMask == modifiers
        }) else { return false }
        target.pointee = item.target
        action.pointee = item.action
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // 分三组：功能 / 设置 / 退出；每项都带图标，文字才能左对齐
        modules.flatMap { $0.menuItems() }.forEach { menu.addItem($0) }
        menu.addItem(.separator())
        menu.addItem(makeItem("偏好设置…", "gearshape", #selector(openSettings), key: ","))
        menu.addItem(makeItem("检查权限…", "lock.shield", #selector(checkPermissions)))
        menu.addItem(.separator())
        let quitItem = makeItem("退出 xTools", "power", #selector(NSApplication.terminate(_:)), key: "q")
        quitItem.target = nil
        menu.addItem(quitItem)
    }

    private func makeItem(_ title: String, _ symbol: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    /// 偏好设置：各模块的页面 + 通用页
    @objc private func openSettings() {
        guard let context else { return }
        if settingsWindow == nil {
            let general = GeneralSettingsPage.make(
                settings: context.settings,
                currentVersion: updater?.currentVersion.description ?? "",
                onMenuBarIconChange: { [weak self] hidden in self?.statusItem?.isVisible = !hidden },
                onCheckUpdates: { [weak self] in self?.updater?.checkNow() },
                onCheckPermissions: { [weak self] in self?.checkPermissions() },
                onResetAll: { [weak self] in self?.resetAllSettings() })
            settingsWindow = SettingsWindowController(pages: modules.flatMap { $0.settingsPages() } + [general])
        }
        settingsWindow?.show()
    }

    /// 初始化：清掉全部设置，各模块重新读取，并重开设置窗口显示默认值
    private func resetAllSettings() {
        guard let context else { return }
        context.settings.reset()
        modules.forEach { $0.reloadSettings() }
        statusItem?.isVisible = true
        settingsWindow?.close()
        settingsWindow = nil
        openSettings()
    }

    /// 汇总各模块需要的权限，缺哪个就引导哪个
    @objc private func checkPermissions() {
        guard let permissions = context?.permissions else { return }
        let needed = Set(modules.flatMap { $0.requiredPermissions })
        let missing = needed.filter { !permissions.isGranted($0) }

        let alert = NSAlert()
        if missing.isEmpty {
            alert.messageText = "所需权限都已开启"
        } else {
            alert.messageText = "缺少权限：" + missing.map(\.displayName).joined(separator: "、")
            alert.informativeText = "授权后需要重启 xTools 才生效。"
            missing.forEach { permissions.request($0) }
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
