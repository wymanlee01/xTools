import AppKit
import ToolboxCore

/// “分屏”设置页：每个动作一个快捷键（两列）；窗口间距；忽略的应用；辅助功能权限状态
@MainActor
enum WindowSettingsPage {
    static func make(settings: WindowSettings, permissions: PermissionCenter,
                     onHotkeyChange: @escaping () -> Void) -> SettingsPageInfo {
        SettingsPageInfo(title: "分屏", symbol: "rectangle.split.2x1") {
            build(settings: settings, permissions: permissions, onHotkeyChange: onHotkeyChange)
        }
    }

    private static func build(settings: WindowSettings, permissions: PermissionCenter,
                              onHotkeyChange: @escaping () -> Void) -> NSView {
        let page = SettingsPageView()
        let store = settings.store

        // 快捷键：两列，每列 9 个动作；点录入框后按新组合键，可清空
        page.addTitle("快捷键", at: CGRect(x: 70, y: 643, width: 390, height: 19))
        let keys = page.addGroup(at: CGRect(x: 40, y: 262, width: 620, height: 371))
        let actions = WindowAction.allCases
        let perColumn = (actions.count + 1) / 2
        for (index, action) in actions.enumerated() {
            let column = CGFloat(index / perColumn), row = CGFloat(index % perColumn)
            let x = 16 + column * 300, y = 330 - row * 38
            page.addLabel(action.title, at: CGRect(x: x, y: y + 2, width: 118, height: 16), alignment: .right, in: keys)
            page.addHotkeyRecorder(at: CGRect(x: x + 126, y: y, width: 140, height: 20),
                                   hotkey: settings.hotkey(for: action), in: keys) { newValue in
                store.set(newValue, for: WindowSettings.hotkeyKey(action))
                onHotkeyChange()
            }
        }

        // 选项
        page.addTitle("选项", at: CGRect(x: 73, y: 222, width: 390, height: 19))
        let options = page.addGroup(at: CGRect(x: 40, y: 50, width: 620, height: 160))
        page.addLabel("窗口间距:", at: CGRect(x: 20, y: 122, width: 110, height: 17), alignment: .right, in: options)
        let gapValue = page.addLabel("", at: CGRect(x: 342, y: 123, width: 30, height: 17), alignment: .right, in: options)
        page.addSlider(at: CGRect(x: 138, y: 117, width: 200, height: 24), range: 0...20, value: Double(settings.gap),
                       valueLabel: gapValue, in: options) { store.set($0.rounded(), for: "gap") }
        page.addLabel("pt", at: CGRect(x: 376, y: 124, width: 20, height: 16), in: options)
        page.addNote("*窗口和窗口之间、窗口和屏幕边缘留出的距离", at: CGRect(x: 138, y: 100, width: 400, height: 14), in: options)

        // 忽略的应用：在菜单栏“窗口分屏”里对当前应用选“忽略”添加或取消
        let names = settings.ignoredApps.map(appName)
        page.addLabel("忽略的应用:", at: CGRect(x: 20, y: 68, width: 110, height: 17), alignment: .right, in: options)
        page.addLabel(names.isEmpty ? "无" : names.joined(separator: "、"), at: CGRect(x: 138, y: 68, width: 460, height: 17),
                      color: names.isEmpty ? .secondaryLabelColor : .labelColor, in: options)
        page.addNote("*在菜单栏「窗口分屏」里对当前应用选「忽略」添加或取消", at: CGRect(x: 138, y: 50, width: 400, height: 14), in: options)

        let granted = permissions.isGranted(.accessibility)
        page.addLabel("辅助功能权限:", at: CGRect(x: 20, y: 18, width: 110, height: 17), alignment: .right, in: options)
        page.addLabel(granted ? "已授权" : "未授权（移动其他应用的窗口需要这个权限）",
                      at: CGRect(x: 138, y: 18, width: 300, height: 17),
                      color: granted ? .secondaryLabelColor : .systemRed, in: options)
        if !granted {
            page.addButton("去授权", at: CGRect(x: 470, y: 11, width: 100, height: 30), in: options) {
                permissions.request(.accessibility)
            }
        }

        page.addButton("重置", at: CGRect(x: 591, y: 5, width: 69, height: 32)) {
            store.reset()
            onHotkeyChange()
            guard let container = page.superview else { return }
            page.removeFromSuperview()
            container.addSubview(build(settings: settings, permissions: permissions, onHotkeyChange: onHotkeyChange))
        }
        return page
    }

    /// bundle id → 应用显示名；找不到应用时直接显示 bundle id
    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
