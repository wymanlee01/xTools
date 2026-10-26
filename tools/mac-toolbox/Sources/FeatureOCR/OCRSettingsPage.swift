import AppKit
import ToolboxCore

/// “OCR”设置页，坐标取自 iShot 的界面
@MainActor
enum OCRSettingsPage {
    static func make(settings: OCRSettings, onHotkeyChange: @escaping () -> Void) -> SettingsPageInfo {
        SettingsPageInfo(title: "OCR", symbol: "text.viewfinder") { build(settings: settings, onHotkeyChange: onHotkeyChange) }
    }

    private static func build(settings: OCRSettings, onHotkeyChange: @escaping () -> Void) -> NSView {
        let page = SettingsPageView()
        let store = settings.store
        page.addTitle("OCR（文字、二维码识别）", at: CGRect(x: 70, y: 643, width: 306, height: 19))
        let group = page.addGroup(at: CGRect(x: 40, y: 431, width: 620, height: 202))
        page.addLabel("截图 > 选择需要的区域 > OCR（或按 O 键）", at: CGRect(x: 42, y: 164, width: 500, height: 16), in: group)
        page.addLabel("⚠️ 优先识别二维码，有二维码时返回二维码内容。", at: CGRect(x: 42, y: 133, width: 500, height: 16), in: group)
        page.addLabel("全局快捷键:", at: CGRect(x: 42, y: 101, width: 129, height: 16), in: group)
        page.addHotkeyRecorder(at: CGRect(x: 177, y: 97, width: 130, height: 20), hotkey: settings.hotkey, in: group) {
            store.set($0, for: "hotkey")
            onHotkeyChange()
        }
        page.addCheckbox("取消换行", at: CGRect(x: 42, y: 68, width: 300, height: 18), isOn: settings.joinLines, in: group) {
            store.set($0, for: "joinLines")
        }
        page.addCheckbox("始终保存到剪切板", at: CGRect(x: 42, y: 39, width: 300, height: 18), isOn: settings.alwaysCopy, in: group) {
            store.set($0, for: "alwaysCopy")
        }
        page.addCheckbox("不打开窗口直接保存到剪切板", at: CGRect(x: 42, y: 11, width: 329, height: 18),
                         isOn: settings.copyWithoutWindow, in: group) { store.set($0, for: "copyWithoutWindow") }

        page.addButton("重置", at: CGRect(x: 591, y: 5, width: 69, height: 32)) {
            store.reset()
            onHotkeyChange()
            guard let container = page.superview else { return }
            page.removeFromSuperview()
            container.addSubview(build(settings: settings, onHotkeyChange: onHotkeyChange))
        }
        return page
    }
}
