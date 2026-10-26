import AppKit
import ToolboxCore

/// “截图”设置页：顶部切换“偏好设置 / 保存 & 动作”，坐标取自 iShot 的界面
@MainActor
enum ScreenshotSettingsPage {
    static func make(store: SettingsStore, onHotkeyChange: @escaping () -> Void) -> SettingsPageInfo {
        let info = SettingsPageInfo(title: "截图", symbol: "camera.viewfinder") {
            build(store: store, onHotkeyChange: onHotkeyChange)
        }
        currentInfo = info
        return info
    }

    private static func build(store: SettingsStore, onHotkeyChange: @escaping () -> Void) -> NSView {
        let page = SettingsPageView()
        // 子分页内容区：iShot 的分页视图在 (-8, 27) 大小 716×641，这里用 700×610 的容器放内容
        let tabs = [preferences(store: store, page: page, onHotkeyChange: onHotkeyChange), saveAndActions(store: store, page: page)]
        for (index, tab) in tabs.enumerated() {
            tab.frame = CGRect(x: 0, y: 27, width: 700, height: 610)
            tab.isHidden = index != 0
            page.addSubview(tab)
        }
        let segmented = NSSegmentedControl(labels: ["偏好设置", "保存 & 动作"], trackingMode: .selectOne, target: nil, action: nil)
        segmented.selectedSegment = 0
        segmented.frame = CGRect(x: 250, y: 645, width: 200, height: 24)
        page.bind(segmented) { control in
            let selected = (control as? NSSegmentedControl)?.selectedSegment ?? 0
            for (index, tab) in tabs.enumerated() { tab.isHidden = index != selected }
        }
        page.addSubview(segmented)
        return page
    }

    // MARK: - 偏好设置：快捷键 + 效果

    private static func preferences(store: SettingsStore, page: SettingsPageView,
                                    onHotkeyChange: @escaping () -> Void) -> NSView {
        let tab = NSView()
        var settings: ScreenshotSettings { ScreenshotSettings(store: store) }

        page.addTitle("快捷键", at: CGRect(x: 44, y: 564, width: 122, height: 22), in: tab)
        // 快捷键表：截图模式 | 快捷键 | 偏好设置（目前只有区域截图一种模式）
        let box = NSBox(frame: CGRect(x: 40, y: 290, width: 605, height: 261))
        box.boxType = .custom
        box.cornerRadius = 6
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        tab.addSubview(box)
        let header = NSView(frame: CGRect(x: 0, y: 236, width: 605, height: 24))
        box.addSubview(header)
        page.addLabel("截图模式", at: CGRect(x: 16, y: 4, width: 200, height: 16), font: .boldSystemFont(ofSize: 12), in: header)
        page.addLabel("快捷键", at: CGRect(x: 240, y: 4, width: 130, height: 16), font: .boldSystemFont(ofSize: 12), in: header)
        page.addLabel("偏好设置", at: CGRect(x: 420, y: 4, width: 150, height: 16), font: .boldSystemFont(ofSize: 12), in: header)
        page.addSeparator(at: CGRect(x: 0, y: 232, width: 605, height: 1), in: box)
        page.addLabel("区域截图", at: CGRect(x: 16, y: 206, width: 200, height: 17), in: box)
        page.addHotkeyRecorder(at: CGRect(x: 240, y: 204, width: 130, height: 20), hotkey: settings.captureHotkey, in: box) { hotkey in
            store.set(hotkey, for: "hotkey.capture")
            onHotkeyChange()
        }
        page.addNote("默认 F1（或 fn+F1）", at: CGRect(x: 420, y: 206, width: 180, height: 16), in: box)

        // 效果
        page.addLabel("效果", at: CGRect(x: 44, y: 234, width: 75, height: 17), font: .boldSystemFont(ofSize: 13), in: tab)
        page.addSeparator(at: CGRect(x: 45, y: 223, width: 605, height: 5), in: tab)
        page.addCheckbox("截图时截取光标", at: CGRect(x: 43, y: 185, width: 300, height: 18), isOn: settings.captureCursor, in: tab) {
            store.set($0, for: "captureCursor")
        }
        page.addCheckbox("显示截图光标辅助十字线", at: CGRect(x: 44, y: 154, width: 363, height: 18), isOn: settings.crosshair, in: tab) {
            store.set($0, for: "crosshair")
        }
        page.addCheckbox("添加阴影", at: CGRect(x: 43, y: 92, width: 101, height: 18), isOn: settings.addShadow, in: tab) {
            store.set($0, for: "addShadow")
        }
        page.addLabel("阴影大小:", at: CGRect(x: 170, y: 91, width: 95, height: 17), alignment: .right, in: tab)
        let shadowValue = page.addLabel("", at: CGRect(x: 410, y: 91, width: 25, height: 17), alignment: .right, in: tab)
        page.addSlider(at: CGRect(x: 270, y: 90, width: 138, height: 20), range: 0...50, value: settings.shadowSize,
                       valueLabel: shadowValue, in: tab) { store.set($0.rounded(), for: "shadowSize") }
        page.addLabel("pt", at: CGRect(x: 436, y: 90, width: 15, height: 16), in: tab)
        page.addLabel("颜色:", at: CGRect(x: 449, y: 91, width: 52, height: 17), alignment: .right, in: tab)
        page.addColorWell(at: CGRect(x: 507, y: 90, width: 40, height: 20), color: settings.shadowColor, in: tab) {
            settings.set(shadowColor: $0)
        }
        page.addCheckbox("增加圆角", at: CGRect(x: 43, y: 61, width: 110, height: 18), isOn: settings.addCorner, in: tab) {
            store.set($0, for: "addCorner")
        }
        page.addLabel("默认圆角大小:", at: CGRect(x: 161, y: 61, width: 104, height: 17), alignment: .right, in: tab)
        let cornerValue = page.addLabel("", at: CGRect(x: 405, y: 61, width: 30, height: 17), alignment: .right, in: tab)
        page.addSlider(at: CGRect(x: 270, y: 58, width: 138, height: 20), range: 0...50, value: settings.cornerSize,
                       valueLabel: cornerValue, in: tab) { store.set($0.rounded(), for: "cornerSize") }
        page.addLabel("pt", at: CGRect(x: 436, y: 60, width: 15, height: 16), in: tab)
        page.addNote("*阴影和圆角加在复制、保存的截图上（贴图有自己的圆角和光晕）", at: CGRect(x: 44, y: 38, width: 475, height: 16), in: tab)
        page.addCheckbox("右键点击退出截图", at: CGRect(x: 409, y: 10, width: 208, height: 18), isOn: settings.rightClickExit, in: tab) {
            store.set($0, for: "rightClickExit")
        }
        page.addButton("重置", at: CGRect(x: 581, y: 237, width: 69, height: 32), in: tab) {
            for key in ["captureCursor", "crosshair", "addShadow", "shadowSize", "shadowColor", "addCorner", "cornerSize",
                        "rightClickExit", "hotkey.capture"] {
                store.remove(key)
            }
            onHotkeyChange()
            reload(page)
        }
        return tab
    }

    // MARK: - 保存 & 动作

    private static func saveAndActions(store: SettingsStore, page: SettingsPageView) -> NSView {
        let tab = NSView()
        var settings: ScreenshotSettings { ScreenshotSettings(store: store) }
        func rightLabel(_ text: String, _ frame: CGRect) {
            page.addLabel(text, at: frame, alignment: .right, in: tab)
        }

        page.addTitle("保存", at: CGRect(x: 44, y: 532, width: 85, height: 16), in: tab)
        rightLabel("图片保存格式:", CGRect(x: 91, y: 488, width: 152, height: 16))
        let formats = ImageFormat.allCases
        page.addPopup(formats.map(\.rawValue), at: CGRect(x: 254, y: 482, width: 150, height: 24),
                      selected: formats.firstIndex(of: settings.format) ?? 1,
                      disabled: Set(formats.indices.filter { !formats[$0].isSupported }), in: tab) {
            store.set(formats[$0].rawValue, for: "format")
        }

        rightLabel("图片保存路径:", CGRect(x: 68, y: 444, width: 175, height: 18))
        let pathPopup = page.addPopup([], at: CGRect(x: 254, y: 440, width: 150, height: 24), selected: 0, in: tab) { index in
            switch index {
            case 1: store.set(true, for: "askPath")
            case 2:  // 其他...：选择文件夹
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
            reload(page)
        }
        // 第一项显示当前文件夹名（iShot 同样把所选路径放在第一项）
        pathPopup.addItems(withTitles: [FileManager.default.displayName(atPath: settings.saveDirectory), "保存时选择路径", "其他..."])
        pathPopup.selectItem(at: settings.askPath ? 1 : 0)

        rightLabel("图片质量:", CGRect(x: 68, y: 402, width: 175, height: 19))
        page.addPopup(["高清", "普通"], at: CGRect(x: 254, y: 398, width: 150, height: 24),
                      selected: settings.normalQuality ? 1 : 0, in: tab) { store.set($0 == 1, for: "normalQuality") }

        page.addCheckbox("截图时播放声效", at: CGRect(x: 254, y: 359, width: 247, height: 18), isOn: settings.playSound, in: tab) {
            store.set($0, for: "playSound")
        }
        page.addCheckbox("保存至文件时同时保存至剪切板", at: CGRect(x: 254, y: 321, width: 300, height: 20), isOn: settings.alsoCopy, in: tab) {
            store.set($0, for: "alsoCopy")
        }
        page.addCheckbox("输出普通RGB颜色描述文件", at: CGRect(x: 254, y: 288, width: 229, height: 18), isOn: settings.genericRGB, in: tab) {
            store.set($0, for: "genericRGB")
        }
        page.addSeparator(at: CGRect(x: 40, y: 259, width: 605, height: 5), in: tab)

        page.addTitle("连贯动作", at: CGRect(x: 50, y: 216, width: 121, height: 16), in: tab)
        rightLabel("双击鼠标左键触发", CGRect(x: 109, y: 160, width: 134, height: 16))
        page.addPopup(DoubleClickAction.allCases.map(\.title), at: CGRect(x: 254, y: 154, width: 213, height: 25),
                      selected: settings.doubleClickAction.rawValue, disabled: [DoubleClickAction.ocr.rawValue], in: tab) {
            store.set($0, for: "doubleClickAction")
        }

        rightLabel("双击修饰键", CGRect(x: 129, y: 108, width: 114, height: 16))
        page.addPopup(ScreenshotSettings.modifierKeys, at: CGRect(x: 254, y: 101, width: 100, height: 26),
                      selected: settings.doubleTapModifier, in: tab) { store.set($0, for: "doubleTapModifier") }
        page.addLabel("保存截图，并使用", at: CGRect(x: 358, y: 108, width: 115, height: 16), in: tab)
        // App 图标按钮：点击选择用哪个 App 打开
        let appButton = NSButton(image: NSWorkspace.shared.icon(forFile: settings.openAppPath), target: nil, action: nil)
        appButton.isBordered = false
        appButton.imageScaling = .scaleProportionallyUpOrDown
        appButton.frame = CGRect(x: 475, y: 103, width: 25, height: 25)
        appButton.toolTip = FileManager.default.displayName(atPath: settings.openAppPath)
        page.bind(appButton) { control in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            store.set(url.path, for: "openAppPath")
            (control as? NSButton)?.image = NSWorkspace.shared.icon(forFile: url.path)
            control.toolTip = FileManager.default.displayName(atPath: url.path)
        }
        tab.addSubview(appButton)
        page.addLabel("打开。", at: CGRect(x: 506, y: 107, width: 50, height: 16), in: tab)
        page.addNote("*点击图标来选择合适的app", at: CGRect(x: 328, y: 83, width: 243, height: 16), in: tab)
        return tab
    }

    /// 重新生成整页，让控件显示最新的设置值
    private static func reload(_ page: SettingsPageView) {
        guard let container = page.superview, let info = currentInfo else { return }
        page.removeFromSuperview()
        container.addSubview(info.makeView())
    }

    /// make 生成的页面信息（重置后用它重建页面）
    private static var currentInfo: SettingsPageInfo?
}
