import Carbon.HIToolbox
import ToolboxCore

/// 粘贴板设置，键名都在 “clipboard.” 下
struct ClipboardSettings {
    let store: SettingsStore

    /// 默认 F6 打开面板（和截图 F1、贴图 F3、OCR F4、录屏 F5 一致用功能键）
    static let defaultHotkey = Hotkey(keyCode: kVK_F6, modifiers: [])
    static let limits = [100, 300, 500, 1000, 5000]
    /// 保存天数，0 表示永久
    static let keepDaysOptions = [1, 7, 30, 90, 0]
    /// 默认忽略的应用：钥匙串和常见密码管理器
    static let defaultIgnoredApps = [
        "com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "com.lastpass.LastPass",
    ]

    var hotkey: Hotkey? { store.hotkey("hotkey", default: Self.defaultHotkey) }
    var limit: Int { store.int("limit", default: 300) }
    var keepDays: Int { store.int("keepDays", default: 30) }
    /// 选中后自动粘贴到当前应用（需要辅助功能权限）
    var autoPaste: Bool { store.bool("autoPaste", default: true) }
    /// 默认粘贴为纯文本
    var plainTextByDefault: Bool { store.bool("plainText", default: false) }
    var recordImages: Bool { store.bool("recordImages", default: true) }
    var recordFiles: Bool { store.bool("recordFiles", default: true) }
    var ignoredApps: [String] {
        let raw = store.string("ignoredApps", default: Self.defaultIgnoredApps.joined(separator: ","))
        return raw.split(separator: ",").map(String.init)
    }

    func set(ignoredApps: [String]) {
        store.set(ignoredApps.joined(separator: ","), for: "ignoredApps")
    }
}
