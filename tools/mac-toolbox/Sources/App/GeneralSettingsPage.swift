import AppKit
import ServiceManagement
import ToolboxCore

/// “通用”设置页，坐标取自 iShot 的界面
/// 启动 & 显示：隐藏菜单栏图标、开机自启动；权限；初始化
@MainActor
enum GeneralSettingsPage {
    static let hideMenuBarIconKey = "general.hideMenuBarIcon"

    static func make(settings: SettingsStore, onMenuBarIconChange: @escaping (Bool) -> Void,
                     onCheckPermissions: @escaping () -> Void, onResetAll: @escaping () -> Void) -> SettingsPageInfo {
        SettingsPageInfo(title: "通用", symbol: "gearshape") {
            let page = SettingsPageView()

            page.addTitle("启动 & 显示", at: CGRect(x: 70, y: 644, width: 200, height: 19))
            let launch = page.addGroup(at: CGRect(x: 40, y: 416, width: 620, height: 217))
            page.addCheckbox("隐藏菜单栏图标", at: CGRect(x: 30, y: 160, width: 300, height: 18),
                             isOn: settings.bool(hideMenuBarIconKey, default: false), in: launch) { hidden in
                settings.set(hidden, for: hideMenuBarIconKey)
                onMenuBarIconChange(hidden)
            }
            page.addNote("*隐藏后，再次打开 xTools.app 即可打开偏好设置", at: CGRect(x: 36, y: 138, width: 400, height: 16), in: launch)
            page.addCheckbox("开机自启动", at: CGRect(x: 30, y: 113, width: 300, height: 18),
                             isOn: SMAppService.mainApp.status == .enabled, in: launch) { enabled in
                setLaunchAtLogin(enabled)
            }

            page.addTitle("权限", at: CGRect(x: 72, y: 271, width: 200, height: 19))
            let permission = page.addGroup(at: CGRect(x: 40, y: 40, width: 620, height: 217))
            page.addLabel("根据不同的功能，xTools 可能需要屏幕录制、辅助功能等权限", at: CGRect(x: 31, y: 103, width: 473, height: 38),
                          in: permission)
            page.addButton("查看权限设置 >>", at: CGRect(x: 33, y: 65, width: 254, height: 22), in: permission) {
                onCheckPermissions()
            }

            page.addButton("初始化", at: CGRect(x: 555, y: 363, width: 105, height: 32)) {
                let alert = NSAlert()
                alert.messageText = "恢复全部默认设置？"
                alert.informativeText = "所有快捷键和偏好设置都会恢复成默认值。"
                alert.addButton(withTitle: "初始化")
                alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn { onResetAll() }
            }
            return page
        }
    }

    /// 开机自启动：注册为登录项；失败时提示（例如应用不在“应用程序”文件夹）
    private static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机自启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
