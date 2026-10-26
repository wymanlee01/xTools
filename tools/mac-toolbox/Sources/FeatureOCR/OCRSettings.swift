import Carbon.HIToolbox
import ToolboxCore

/// OCR 设置，键名都在 “ocr.” 下；默认值同 iShot（三个开关默认都关）
struct OCRSettings {
    let store: SettingsStore

    /// 默认 F4（iShot 用 ⌥O，这里避开）
    static let defaultHotkey = Hotkey(keyCode: kVK_F4, modifiers: [])

    var hotkey: Hotkey? { store.hotkey("hotkey", default: Self.defaultHotkey) }
    /// 取消换行
    var joinLines: Bool { store.bool("joinLines", default: false) }
    /// 始终保存到剪切板
    var alwaysCopy: Bool { store.bool("alwaysCopy", default: false) }
    /// 不打开窗口直接保存到剪切板
    var copyWithoutWindow: Bool { store.bool("copyWithoutWindow", default: false) }

    // 结果窗口里的开关，记住上次的选择
    var continuous: Bool { store.bool("window.continuous", default: false) }
    var fixedRegion: Bool { store.bool("window.fixedRegion", default: false) }
    var keepOnTop: Bool { store.bool("window.keepOnTop", default: false) }
    var englishSymbols: Bool { store.bool("window.englishSymbols", default: false) }
}
