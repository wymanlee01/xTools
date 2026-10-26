import AppKit
import ToolboxCore

/// “粘贴板”设置页：快捷键、记录、粘贴、隐私
@MainActor
enum ClipboardSettingsPage {
    static func make(settings: ClipboardSettings, onHotkeyChange: @escaping () -> Void,
                     onClear: @escaping () -> Void) -> SettingsPageInfo {
        SettingsPageInfo(title: "粘贴板", symbol: "doc.on.clipboard") {
            build(settings: settings, onHotkeyChange: onHotkeyChange, onClear: onClear)
        }
    }

    private static func build(settings: ClipboardSettings, onHotkeyChange: @escaping () -> Void,
                              onClear: @escaping () -> Void) -> NSView {
        let page = SettingsPageView()
        let store = settings.store
        func rightLabel(_ text: String, _ frame: CGRect, in parent: NSView) {
            page.addLabel(text, at: frame, alignment: .right, in: parent)
        }

        // 快捷键与记录
        page.addTitle("记录", at: CGRect(x: 70, y: 643, width: 300, height: 19))
        let record = page.addGroup(at: CGRect(x: 40, y: 430, width: 620, height: 203))
        rightLabel("打开粘贴板面板:", CGRect(x: 40, y: 166, width: 180, height: 16), in: record)
        page.addHotkeyRecorder(at: CGRect(x: 228, y: 163, width: 149, height: 20), hotkey: settings.hotkey, in: record) {
            store.set($0, for: "hotkey")
            onHotkeyChange()
        }
        rightLabel("最多保存:", CGRect(x: 40, y: 130, width: 180, height: 16), in: record)
        let limits = ClipboardSettings.limits
        page.addPopup(limits.map { "\($0) 条" }, at: CGRect(x: 228, y: 124, width: 149, height: 25),
                      selected: limits.firstIndex(of: settings.limit) ?? 1, in: record) { store.set(limits[$0], for: "limit") }
        rightLabel("保存时间:", CGRect(x: 40, y: 96, width: 180, height: 16), in: record)
        let days = ClipboardSettings.keepDaysOptions
        page.addPopup(days.map { $0 == 0 ? "永久" : "\($0) 天" }, at: CGRect(x: 228, y: 90, width: 149, height: 25),
                      selected: days.firstIndex(of: settings.keepDays) ?? 2, in: record) { store.set(days[$0], for: "keepDays") }
        page.addCheckbox("记录图片", at: CGRect(x: 228, y: 58, width: 200, height: 18), isOn: settings.recordImages, in: record) {
            store.set($0, for: "recordImages")
        }
        page.addCheckbox("记录文件", at: CGRect(x: 228, y: 32, width: 200, height: 18), isOn: settings.recordFiles, in: record) {
            store.set($0, for: "recordFiles")
        }
        page.addNote("*收藏的记录不受数量和时间限制", at: CGRect(x: 228, y: 10, width: 360, height: 16), in: record)

        // 粘贴
        page.addTitle("粘贴", at: CGRect(x: 70, y: 395, width: 300, height: 19))
        let paste = page.addGroup(at: CGRect(x: 40, y: 290, width: 620, height: 95))
        page.addCheckbox("选中后自动粘贴到当前应用", at: CGRect(x: 228, y: 58, width: 300, height: 18),
                         isOn: settings.autoPaste, in: paste) { store.set($0, for: "autoPaste") }
        page.addNote("*需要在“系统设置 > 隐私与安全性 > 辅助功能”里允许 xTools", at: CGRect(x: 246, y: 38, width: 360, height: 16),
                     in: paste)
        page.addCheckbox("默认粘贴为纯文本", at: CGRect(x: 228, y: 12, width: 300, height: 18),
                         isOn: settings.plainTextByDefault, in: paste) { store.set($0, for: "plainText") }

        // 隐私
        page.addTitle("隐私", at: CGRect(x: 70, y: 255, width: 300, height: 19))
        let privacy = page.addGroup(at: CGRect(x: 40, y: 60, width: 620, height: 185))
        page.addNote("密码管理器标记为“隐藏 / 临时”的内容始终不记录。以下应用复制的内容也不记录（每行一个 Bundle ID）：",
                     at: CGRect(x: 20, y: 156, width: 580, height: 16), in: privacy)
        let scroll = NSScrollView(frame: CGRect(x: 20, y: 46, width: 580, height: 104))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        let ignored = NSTextView(frame: CGRect(origin: .zero, size: scroll.contentSize))
        ignored.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        ignored.isRichText = false
        ignored.autoresizingMask = [.width]
        ignored.string = settings.ignoredApps.joined(separator: "\n")
        scroll.documentView = ignored
        privacy.addSubview(scroll)
        page.addButton("保存忽略列表", at: CGRect(x: 14, y: 8, width: 130, height: 32), in: privacy) {
            let ids = ignored.string.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            settings.set(ignoredApps: ids)
            HUD.show("已保存")
        }
        page.addButton("添加正在运行的应用…", at: CGRect(x: 150, y: 8, width: 180, height: 32), in: privacy) {
            // 列出正在运行的普通应用，选一个加进去
            let menu = NSMenu()
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                guard let id = app.bundleIdentifier, let name = app.localizedName else { continue }
                let item = ClipMenuItem(title: "\(name)（\(id)）") {
                    if !ignored.string.contains(id) { ignored.string += (ignored.string.isEmpty ? "" : "\n") + id }
                }
                item.image = app.icon
                item.image?.size = CGSize(width: 16, height: 16)
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }

        page.addButton("清空历史…", at: CGRect(x: 40, y: 15, width: 110, height: 32)) { onClear() }
        page.addButton("重置", at: CGRect(x: 591, y: 15, width: 69, height: 32)) {
            store.reset()
            onHotkeyChange()
            guard let container = page.superview else { return }
            page.removeFromSuperview()
            container.addSubview(build(settings: settings, onHotkeyChange: onHotkeyChange, onClear: onClear))
        }
        return page
    }
}
