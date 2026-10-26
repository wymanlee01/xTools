import AppKit
import FeatureClipboard
import FeatureOCR
import FeaturePin
import FeatureRecord
import FeatureScreenshot
import ToolboxCore

/// 组装底座和各功能模块，生成菜单栏菜单和偏好设置窗口
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var context: ToolContext?
    private var settingsWindow: SettingsWindowController?

    /// 新增功能模块只需加到这里
    private let modules: [ToolModule] = [
        ScreenshotModule(),
        PinModule(),
        RecordModule(),
        OCRModule(),
        ClipboardModule(),
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for module in modules {
            module.menuItems().forEach { menu.addItem($0) }
            menu.addItem(.separator())
        }
        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let permissionItem = NSMenuItem(title: "检查权限…", action: #selector(checkPermissions), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(NSMenuItem(title: "退出 xTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// 偏好设置：各模块的页面 + 通用页
    @objc private func openSettings() {
        guard let context else { return }
        if settingsWindow == nil {
            let general = GeneralSettingsPage.make(
                settings: context.settings,
                onMenuBarIconChange: { [weak self] hidden in self?.statusItem?.isVisible = !hidden },
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
