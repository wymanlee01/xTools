import AppKit
import ToolboxCore

/// “标注”设置页：工具快捷键表（图标 | 名称 | 快捷键）+ 工具栏弹窗响应时间
/// 表格位置取自 iShot 的界面，快捷键与悬浮提示框里的同一份设置
@MainActor
enum AnnotationSettingsPage {
    /// 表格行：工具和其他可设单键快捷键的操作
    private static let rows: [(symbol: String, title: String, action: ShortcutAction)] = [
        ("square", "矩形工具", .rectangle), ("circle", "椭圆工具", .ellipse), ("line.diagonal", "直线工具", .line),
        ("arrow.up.right", "箭头工具", .arrow), ("pencil", "铅笔工具", .pencil),
        ("checkerboard.rectangle", "像素化工具", .mosaic), ("character", "文本工具", .text),
        ("1.circle", "步骤标注工具", .step), ("highlighter", "高亮工具", .highlight), ("pin", "贴图", .pin),
        ("square.and.arrow.down", "保存截图", .save), ("checkmark", "拷贝截图到剪切板", .copy),
    ]

    static func make(store: SettingsStore) -> SettingsPageInfo {
        SettingsPageInfo(title: "标注", symbol: "pencil.tip.crop.circle") { build(store: store) }
    }

    private static func build(store: SettingsStore) -> NSView {
        let page = SettingsPageView()
        let shortcuts = ToolShortcuts(settings: store)
        page.addTitle("快捷键", at: CGRect(x: 44, y: 640, width: 200, height: 22))
        page.addNote("*截图时有选区后按单键触发；ㄩ 是空格键，↩ 是回车键", at: CGRect(x: 44, y: 620, width: 500, height: 16))

        let box = NSBox(frame: CGRect(x: 40, y: 80, width: 605, height: 530))
        box.boxType = .custom
        box.cornerRadius = 6
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        page.addSubview(box)

        // 表头：图标 | 名称 | 快捷键
        let top: CGFloat = 500
        page.addLabel("图标", at: CGRect(x: 16, y: top + 6, width: 60, height: 16), font: .boldSystemFont(ofSize: 12), in: box)
        page.addLabel("名称", at: CGRect(x: 90, y: top + 6, width: 200, height: 16), font: .boldSystemFont(ofSize: 12), in: box)
        page.addLabel("快捷键", at: CGRect(x: 330, y: top + 6, width: 100, height: 16), font: .boldSystemFont(ofSize: 12), in: box)
        page.addSeparator(at: CGRect(x: 0, y: top, width: 605, height: 1), in: box)

        var popups: [ShortcutAction: NSPopUpButton] = [:]
        for (index, row) in rows.enumerated() {
            let y = top - 40 - CGFloat(index) * 40
            let icon = NSImageView(image: NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.title) ?? NSImage())
            icon.frame = CGRect(x: 20, y: y + 8, width: 20, height: 20)
            box.addSubview(icon)
            page.addLabel(row.title, at: CGRect(x: 90, y: y + 10, width: 200, height: 17), in: box)
            let keys = ToolShortcuts.keys + (row.action == .save || row.action == .copy ? ToolShortcuts.specialKeys : [])
            let popup = page.addPopup(keys, at: CGRect(x: 330, y: y + 6, width: 70, height: 25),
                                      selected: keys.firstIndex(of: shortcuts.key(for: row.action)) ?? 0, in: box) { selected in
                shortcuts.set(keys[selected], for: row.action)
                // 冲突时另一项会被换成原来的键，刷新所有下拉框
                for (action, other) in popups { other.selectItem(withTitle: shortcuts.key(for: action)) }
            }
            popups[row.action] = popup
        }

        // 工具栏弹窗响应时间（iShot 默认 0.5 秒）
        page.addLabel("工具栏弹窗响应时间:", at: CGRect(x: 40, y: 32, width: 160, height: 16), alignment: .right)
        let value = page.addLabel("", at: CGRect(x: 310, y: 32, width: 30, height: 16), alignment: .right)
        page.addSlider(at: CGRect(x: 205, y: 30, width: 100, height: 18), range: 0...2,
                       value: ScreenshotSettings(store: store).tipDelay, valueLabel: value) {
            store.set(($0 * 10).rounded() / 10, for: "tipDelay")
        }
        page.addLabel("s", at: CGRect(x: 342, y: 32, width: 11, height: 16))

        page.addButton("重置", at: CGRect(x: 591, y: 25, width: 69, height: 32)) {
            for action in ShortcutAction.allCases { store.remove("shortcut.\(action.rawValue)") }
            store.remove("tipDelay")
            guard let container = page.superview else { return }
            page.removeFromSuperview()
            container.addSubview(build(store: store))
        }
        return page
    }
}
