import AppKit
import ToolboxCore

/// “录屏”设置页：上半部分坐标取自 iShot 的界面；
/// iShot 把格式、帧率、声音等放在录制工具条上，这里放在下半部分“录制选项”
@MainActor
enum RecordSettingsPage {
    static func make(settings: RecordSettings, onHotkeyChange: @escaping () -> Void) -> SettingsPageInfo {
        SettingsPageInfo(title: "录屏", symbol: "record.circle") { build(settings: settings, onHotkeyChange: onHotkeyChange) }
    }

    private static func build(settings: RecordSettings, onHotkeyChange: @escaping () -> Void) -> NSView {
        let page = SettingsPageView()
        let store = settings.store
        func rightLabel(_ text: String, _ frame: CGRect, in parent: NSView) {
            page.addLabel(text, at: frame, alignment: .right, in: parent)
        }

        page.addTitle("快捷键", at: CGRect(x: 70, y: 643, width: 106, height: 19))
        let keys = page.addGroup(at: CGRect(x: 40, y: 404, width: 620, height: 229))
        rightLabel("开始/停止录屏:", CGRect(x: 120, y: 188, width: 174, height: 16), in: keys)
        page.addHotkeyRecorder(at: CGRect(x: 298, y: 185, width: 149, height: 20), hotkey: settings.toggleHotkey, in: keys) {
            store.set($0, for: "hotkey.toggle")
            onHotkeyChange()
        }
        rightLabel("暂停/恢复录屏:", CGRect(x: 120, y: 152, width: 174, height: 16), in: keys)
        page.addHotkeyRecorder(at: CGRect(x: 299, y: 149, width: 149, height: 20), hotkey: settings.pauseHotkey, in: keys) {
            store.set($0, for: "hotkey.pause")
            onHotkeyChange()
        }
        rightLabel("开始/停止标注:", CGRect(x: 82, y: 115, width: 212, height: 16), in: keys)
        let annotate = page.addHotkeyRecorder(at: CGRect(x: 298, y: 114, width: 149, height: 20), hotkey: nil, in: keys) { _ in }
        annotate.alphaValue = 0.4
        page.addNote("（开发中）", at: CGRect(x: 455, y: 116, width: 100, height: 16), in: keys)

        rightLabel("保存路径:", CGRect(x: 149, y: 83, width: 145, height: 16), in: keys)
        let path = page.addPopup([], at: CGRect(x: 298, y: 76, width: 149, height: 24), selected: 0, in: keys) { index in
            switch index {
            case 1: store.set(true, for: "askPath")
            case 2:
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.directoryURL = URL(fileURLWithPath: settings.saveDirectory)
                if panel.runModal() == .OK, let url = panel.url {
                    store.set(url.path, for: "saveDirectory")
                    store.set(false, for: "askPath")
                }
            default: store.set(false, for: "askPath")
            }
            reload(page, settings: settings, onHotkeyChange: onHotkeyChange)
        }
        path.addItems(withTitles: [FileManager.default.displayName(atPath: settings.saveDirectory), "保存时选择路径", "其他..."])
        path.selectItem(at: settings.askPath ? 1 : 0)

        rightLabel("保存方式:", CGRect(x: 190, y: 49, width: 104, height: 16), in: keys)
        page.addPopup(["本地文件", "剪切板", "同时保存到剪切板和本地"], at: CGRect(x: 298, y: 42, width: 149, height: 25),
                      selected: settings.saveMethod, in: keys) { store.set($0, for: "saveMethod") }
        rightLabel("完成时动作:", CGRect(x: 108, y: 16, width: 186, height: 16), in: keys)
        page.addPopup(["无", "自动播放", "打开路径"], at: CGRect(x: 298, y: 9, width: 149, height: 25),
                      selected: settings.finishAction, in: keys) { store.set($0, for: "finishAction") }

        // 录制选项
        page.addTitle("录制选项", at: CGRect(x: 70, y: 328, width: 311, height: 19))
        let options = page.addGroup(at: CGRect(x: 40, y: 60, width: 620, height: 256))
        rightLabel("格式:", CGRect(x: 120, y: 214, width: 174, height: 16), in: options)
        page.addPopup(RecordSettings.formats, at: CGRect(x: 298, y: 208, width: 149, height: 25),
                      selected: RecordSettings.formats.firstIndex(of: settings.format) ?? 0, in: options) {
            store.set(RecordSettings.formats[$0], for: "format")
        }
        rightLabel("帧率:", CGRect(x: 120, y: 180, width: 174, height: 16), in: options)
        page.addPopup(RecordSettings.frameRates.map { "\($0) fps" }, at: CGRect(x: 298, y: 174, width: 149, height: 25),
                      selected: RecordSettings.frameRates.firstIndex(of: settings.frameRate) ?? 1, in: options) {
            store.set(RecordSettings.frameRates[$0], for: "frameRate")
        }
        rightLabel("开始前倒计时:", CGRect(x: 120, y: 146, width: 174, height: 16), in: options)
        page.addPopup(RecordSettings.countdowns.map { $0 == 0 ? "不倒计时" : "\($0) 秒" }, at: CGRect(x: 298, y: 140, width: 149, height: 25),
                      selected: RecordSettings.countdowns.firstIndex(of: settings.countdown) ?? 1, in: options) {
            store.set(RecordSettings.countdowns[$0], for: "countdown")
        }
        page.addCheckbox("显示光标", at: CGRect(x: 298, y: 106, width: 250, height: 18), isOn: settings.showsCursor, in: options) {
            store.set($0, for: "showsCursor")
        }
        page.addCheckbox("显示鼠标点击", at: CGRect(x: 298, y: 80, width: 250, height: 18), isOn: settings.showsClicks, in: options) {
            store.set($0, for: "showsClicks")
        }
        page.addCheckbox("录制系统声音", at: CGRect(x: 298, y: 54, width: 250, height: 18), isOn: settings.systemAudio, in: options) {
            store.set($0, for: "systemAudio")
        }
        page.addCheckbox("录制麦克风", at: CGRect(x: 298, y: 28, width: 250, height: 18), isOn: settings.microphone, in: options) {
            store.set($0, for: "microphone")
        }
        page.addNote("*录制时不会录进 xTools 自己的窗口；菜单栏显示计时，点开可暂停或停止",
                     at: CGRect(x: 40, y: 36, width: 620, height: 16))

        page.addButton("重置", at: CGRect(x: 591, y: 5, width: 69, height: 32)) {
            store.reset()
            onHotkeyChange()
            reload(page, settings: settings, onHotkeyChange: onHotkeyChange)
        }
        return page
    }

    private static func reload(_ page: SettingsPageView, settings: RecordSettings, onHotkeyChange: @escaping () -> Void) {
        guard let container = page.superview else { return }
        page.removeFromSuperview()
        container.addSubview(build(settings: settings, onHotkeyChange: onHotkeyChange))
    }
}
