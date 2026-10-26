import AppKit
import ToolboxCore

/// 偏好设置窗口，布局按 iShot 的界面复刻：
/// 900×700 固定大小、标题栏透明；左侧 200 宽菜单，右侧 700×700 页面
@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let pages: [SettingsPageInfo]
    private let table = NSTableView()
    private let content = NSView(frame: CGRect(x: 200, y: 0, width: 700, height: 700))

    init(pages: [SettingsPageInfo]) {
        self.pages = pages
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "xTools 偏好设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildLayout()
        select(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildLayout() {
        guard let root = window?.contentView else { return }
        // 左侧菜单：侧边栏材质背景 + 表格
        let sidebar = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 200, height: 700))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        root.addSubview(sidebar)

        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 652))
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: .init("page"))
        column.width = 184
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 36
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        sidebar.addSubview(scroll)
        root.addSubview(content)
    }

    private func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        table.selectRowIndexes([index], byExtendingSelection: false)
        content.subviews.forEach { $0.removeFromSuperview() }
        content.addSubview(pages[index].makeView())
    }

    // MARK: - 左侧菜单

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: pages[row].symbol, accessibilityDescription: nil) ?? NSImage())
        icon.frame = CGRect(x: 12, y: 8, width: 20, height: 20)
        icon.contentTintColor = .controlAccentColor
        let label = NSTextField(labelWithString: pages[row].title)
        label.font = .systemFont(ofSize: 14)
        label.frame = CGRect(x: 42, y: 9, width: 130, height: 18)
        cell.addSubview(icon)
        cell.addSubview(label)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0 else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        content.addSubview(pages[row].makeView())
    }
}
