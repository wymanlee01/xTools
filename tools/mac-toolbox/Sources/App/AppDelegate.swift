import AppKit
import FeatureScreenshot
import ToolboxCore

/// 组装底座和各功能模块，生成菜单栏菜单
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var context: ToolContext?

    /// 新增功能模块只需加到这里
    private let modules: [ToolModule] = [
        ScreenshotModule(),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = ToolContext(settings: SettingsStore(), hotkeys: HotkeyCenter(),
                                  permissions: PermissionCenter(), pasteboard: PasteboardService(),
                                  services: ServiceRegistry())
        self.context = context
        modules.forEach { $0.start(context: context) }
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        modules.forEach { $0.stop() }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "xTools")

        let menu = NSMenu()
        for module in modules {
            module.menuItems().forEach { menu.addItem($0) }
            menu.addItem(.separator())
        }
        let permissionItem = NSMenuItem(title: "检查权限…", action: #selector(checkPermissions), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(NSMenuItem(title: "退出 xTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
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
