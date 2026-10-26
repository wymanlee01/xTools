import AppKit
import ToolboxCore

/// “贴图”设置页，坐标取自 iShot 的界面
/// 快捷键：贴剪贴板、打开贴图库（开发中）、隐藏/显示全部；默认设置：控件、双击关闭、单桌面、圆角、透明度
@MainActor
enum PinSettingsPage {
    static func make(settings: PinSettings, onHotkeyChange: @escaping () -> Void) -> SettingsPageInfo {
        SettingsPageInfo(title: "贴图", symbol: "pin") { build(settings: settings, onHotkeyChange: onHotkeyChange) }
    }

    private static func build(settings: PinSettings, onHotkeyChange: @escaping () -> Void) -> NSView {
        let page = SettingsPageView()
        let store = settings.store

        // 快捷键
        page.addTitle("快捷键", at: CGRect(x: 70, y: 643, width: 390, height: 19))
        let keys = page.addGroup(at: CGRect(x: 40, y: 438, width: 620, height: 195))
        func row(y: CGFloat, hotkey: Hotkey?, title: String, key: String?) {
            page.addLabel("点按", at: CGRect(x: 47, y: y + 2, width: 38, height: 16), in: keys)
            let recorder = page.addHotkeyRecorder(at: CGRect(x: 87, y: y, width: 130, height: 20), hotkey: hotkey, in: keys) { newValue in
                guard let key else { return }
                store.set(newValue, for: key)
                onHotkeyChange()
            }
            recorder.alphaValue = key == nil ? 0.4 : 1
            page.addLabel(title, at: CGRect(x: 225, y: y + 2, width: 380, height: 16), in: keys)
        }
        row(y: 140, hotkey: settings.pasteHotkey, title: "把剪切板里的图片、富文本贴图到屏幕上", key: "hotkey.paste")
        page.addNote("*点按菜单栏里按钮把剪切板里的图片、纯文本贴图到屏幕上", at: CGRect(x: 47, y: 120, width: 438, height: 14), in: keys)
        row(y: 82, hotkey: nil, title: "打开贴图库（开发中）", key: nil)
        row(y: 25, hotkey: settings.toggleHotkey, title: "隐藏/显示全部贴图窗口", key: "hotkey.toggle")

        // 默认设置
        page.addTitle("默认设置", at: CGRect(x: 73, y: 319, width: 390, height: 19))
        let defaults = page.addGroup(at: CGRect(x: 40, y: 40, width: 620, height: 267))
        page.addCheckbox("显示/隐藏贴图窗口按钮", at: CGRect(x: 47, y: 218, width: 300, height: 18),
                         isOn: settings.showsControls, in: defaults) { store.set($0, for: "showsControls") }
        page.addCheckbox("双击鼠标左键关闭贴图", at: CGRect(x: 47, y: 175, width: 295, height: 18),
                         isOn: settings.doubleClickClose, in: defaults) { store.set($0, for: "doubleClickClose") }
        page.addCheckbox("固定在单个桌面上（创建时有效）", at: CGRect(x: 47, y: 133, width: 295, height: 18),
                         isOn: settings.pinnedToOneSpace, in: defaults) { store.set($0, for: "pinnedToOneSpace") }
        page.addLabel("保存到贴图库并", at: CGRect(x: 57, y: 95, width: 134, height: 16), alignment: .right, in: defaults)
        let library = page.addPopup(["无动作", "保存至本地", "保存至剪切板", "保存至本地和剪切板"],
                                    at: CGRect(x: 195, y: 89, width: 191, height: 25), selected: 0, in: defaults) { _ in }
        library.isEnabled = false
        library.toolTip = "贴图库开发中"

        page.addLabel("默认圆角大小:", at: CGRect(x: 58, y: 60, width: 134, height: 17), alignment: .right, in: defaults)
        let cornerValue = page.addLabel("", at: CGRect(x: 390, y: 61, width: 30, height: 17), alignment: .right, in: defaults)
        page.addSlider(at: CGRect(x: 196, y: 55, width: 191, height: 20), range: 0...30, value: Double(settings.cornerRadius),
                       valueLabel: cornerValue, in: defaults) { store.set($0.rounded(), for: "cornerRadius") }
        page.addLabel("pt", at: CGRect(x: 422, y: 62, width: 15, height: 16), in: defaults)

        page.addLabel("默认透明度:", at: CGRect(x: 47, y: 19, width: 144, height: 16), alignment: .right, in: defaults)
        let opacityValue = page.addLabel("", at: CGRect(x: 390, y: 19, width: 30, height: 16), alignment: .right, in: defaults)
        page.addSlider(at: CGRect(x: 196, y: 14, width: 191, height: 24), range: 10...100,
                       value: Double(settings.defaultOpacity * 100), valueLabel: opacityValue, in: defaults) {
            store.set($0.rounded(), for: "defaultOpacity")
        }
        page.addLabel("%", at: CGRect(x: 422, y: 19, width: 16, height: 16), in: defaults)

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
