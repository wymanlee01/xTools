import AppKit

/// 粘贴板面板，样式参考 PasteNow 官网截图：贴屏幕右侧、全高、毛玻璃圆角；
/// 顶栏（固定按钮、搜索框、设置齿轮）+ 胶囊分类标签 + 卡片列表 + 底栏条数
/// 不抢焦点（粘贴时目标应用仍在前台）
/// 操作：输入即搜索；↑↓ 选择；回车粘贴，⇧回车粘贴为纯文本；⌘1~9 直接粘贴第几条；
///      空格（搜索框为空时）预览；⌘P 收藏；⌘⌫ 删除；Esc 关闭；右键更多操作
@MainActor
final class ClipboardPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    static let width: CGFloat = 320
    /// 离屏幕边缘的距离
    static let margin: CGFloat = 8

    // 事件交给模块处理
    var onPaste: ((ClipItem, _ plainText: Bool) -> Void)?
    var onCopy: ((ClipItem) -> Void)?
    var onTogglePin: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?
    var onPinToScreen: ((ClipItem) -> Void)?
    var onClearAll: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// 记住用户拖动、缩放后的位置（存在设置里，字符串格式同 NSStringFromRect）
    var savedFrame: (() -> String?)?
    var saveFrame: ((String?) -> Void)?

    private let store: ClipStore
    private var rows: [ClipItem] = []
    private var filter = ClipFilter.all
    private let search = NSSearchField()
    private let tabs = PillTabs(titles: ClipFilter.allCases.map(\.title))
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "还没有记录")
    private let countLabel = NSTextField(labelWithString: "")
    private var pinButton: NSButton!
    /// 固定面板：点到别处也不收起
    private var keepOpen = false
    /// 程序自己移动窗口（打开时滑入）时不记位置
    private var movingProgrammatically = false
    private var keyMonitor: Any?
    private lazy var preview = ClipPreviewPanel()

    init(store: ClipStore) {
        self.store = store
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        // 按住顶栏或空白处可拖动，边缘可调大小
        isMovableByWindowBackground = true
        minSize = CGSize(width: 280, height: 360)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
        buildLayout()
    }

    override var canBecomeKey: Bool { true }

    // MARK: - 显示 / 隐藏

    /// 打开面板：总是出现在鼠标所在的屏幕上
    /// - 拖动 / 缩放过：按记住的位置，挪到鼠标所在屏幕的同一相对位置
    /// - 否则贴边、全高：鼠标在屏幕左半边贴左边，右半边贴右边，从那一侧滑入
    func show() {
        search.stringValue = ""
        reload()
        let mouse = NSEvent.mouseLocation
        let visible = Self.screen(containing: mouse)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = savedFrame?().map(NSRectFromString), saved.width > 0, saved.height > 0 {
            let from = Self.screen(mostlyCovering: saved)?.visibleFrame
            movingProgrammatically = true
            setFrame(Self.place(saved, from: from, to: visible), display: false)
            movingProgrammatically = false
            alphaValue = 1
            present()
            return
        }
        let target = Self.dockedFrame(in: visible, mouseX: mouse.x)
        movingProgrammatically = true
        if !isVisible {
            // 从贴边的那一侧滑进来
            let slide = target.midX < visible.midX ? -Self.width / 3 : Self.width / 3
            setFrame(target.offsetBy(dx: slide, dy: 0), display: false)
            alphaValue = 0
        }
        present()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.movingProgrammatically = false }
        }
    }

    private func present() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
        startKeyMonitor()
    }

    /// 鼠标所在的屏幕
    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// 窗口大部分所在的屏幕（拔掉外接屏后可能一块都不在，返回 nil）
    private static func screen(mostlyCovering frame: CGRect) -> NSScreen? {
        func overlap(_ screen: NSScreen) -> CGFloat {
            let rect = screen.visibleFrame.intersection(frame)
            return rect.isNull ? 0 : rect.width * rect.height
        }
        let best = NSScreen.screens.max { overlap($0) < overlap($1) }
        return best.flatMap { overlap($0) > 0 ? $0 : nil }
    }

    /// 贴边、和可用区域一样高：鼠标在左半边贴左边，否则贴右边
    static func dockedFrame(in visible: CGRect, mouseX: CGFloat) -> CGRect {
        let x = mouseX < visible.midX ? visible.minX + margin : visible.maxX - width - margin
        return CGRect(x: x, y: visible.minY + margin, width: width, height: visible.height - margin * 2)
    }

    /// 把记住的位置从原来的屏幕挪到目标屏幕：
    /// 离上边的距离不变；在原屏幕右半边就保持离右边的距离，否则保持离左边的距离；
    /// 最后缩到能放下并整个放进目标屏幕
    static func place(_ frame: CGRect, from old: CGRect?, to visible: CGRect) -> CGRect {
        var f = frame
        if let old {
            f.origin.x = frame.midX > old.midX ? visible.maxX - (old.maxX - frame.minX) : visible.minX + (frame.minX - old.minX)
            f.origin.y = visible.maxY - (old.maxY - frame.minY)
        }
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }

    // 用户拖动、缩放后记住位置
    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }

    private func rememberFrame() {
        guard !movingProgrammatically, isVisible else { return }
        saveFrame?(NSStringFromRect(frame))
    }

    /// 恢复贴边（忘掉记住的位置，按鼠标在哪半边贴哪边）
    @objc private func dockToEdge() {
        saveFrame?(nil)
        let mouse = NSEvent.mouseLocation
        let visible = Self.screen(containing: mouse)?.visibleFrame ?? frame
        movingProgrammatically = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().setFrame(Self.dockedFrame(in: visible, mouseX: mouse.x), display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.movingProgrammatically = false }
        }
    }

    func hide() {
        preview.orderOut(nil)
        stopKeyMonitor()
        orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // 点到别处就收起（固定面板、预览窗口除外）
        if keepOpen { return }
        if !preview.isVisible || !preview.isKeyWindow { hide() }
    }

    /// 历史变化后刷新列表，尽量保持选中项
    func reload() {
        let selectedID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        rows = store.filtered(filter, query: search.stringValue)
        table.reloadData()
        let index = selectedID.flatMap { id in rows.firstIndex { $0.id == id } } ?? 0
        if !rows.isEmpty { select(index) }
        emptyLabel.isHidden = !rows.isEmpty
        emptyLabel.stringValue = store.items.isEmpty ? "还没有记录，复制点东西试试" : "没有匹配的记录"
        countLabel.stringValue = "\(rows.count) 条"
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        table.selectRowIndexes([index], byExtendingSelection: false)
        table.scrollRowToVisible(index)
        if preview.isVisible { preview.show(rows[index], store: store, beside: self) }
    }

    private var selectedItem: ClipItem? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil
    }

    // MARK: - 布局

    private func buildLayout() {
        let w = Self.width, h: CGFloat = 600
        let root = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        // 毛玻璃由系统直接绘制，不认图层圆角，要用遮罩图才能裁出圆角
        root.maskImage = Self.roundedMask(radius: 14)
        root.autoresizingMask = [.width, .height]
        contentView = root

        // 顶栏：固定按钮 | 恢复贴右侧 | 搜索框 | 设置齿轮
        pinButton = iconButton("pin", tip: "固定面板（点别处不收起）", action: #selector(togglePinPanel))
        pinButton.frame = CGRect(x: 10, y: h - 40, width: 26, height: 26)
        pinButton.autoresizingMask = [.minYMargin]
        root.addSubview(pinButton)
        let dock = iconButton("rectangle.righthalf.inset.filled", tip: "恢复贴边（鼠标在哪半边贴哪边）", action: #selector(dockToEdge))
        dock.frame = CGRect(x: 36, y: h - 40, width: 26, height: 26)
        dock.autoresizingMask = [.minYMargin]
        root.addSubview(dock)
        let gear = iconButton("gearshape", tip: "偏好设置", action: #selector(openSettings))
        gear.frame = CGRect(x: w - 36, y: h - 40, width: 26, height: 26)
        gear.autoresizingMask = [.minXMargin, .minYMargin]
        root.addSubview(gear)
        search.frame = CGRect(x: 68, y: h - 39, width: w - 110, height: 24)
        search.placeholderString = "输入以搜索…"
        search.delegate = self
        search.focusRingType = .none
        search.autoresizingMask = [.width, .minYMargin]
        root.addSubview(search)

        // 胶囊分类标签
        tabs.frame.origin = CGPoint(x: 12, y: h - 72)
        tabs.autoresizingMask = [.minYMargin]
        tabs.onSelect = { [weak self] index in
            self?.filter = ClipFilter(rawValue: index) ?? .all
            self?.reload()
        }
        root.addSubview(tabs)

        // 卡片列表
        let scroll = OverlayScrollView(frame: CGRect(x: 0, y: 34, width: w, height: h - 34 - 80))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        // 列表上下留点空，滚动条不贴着顶栏和底栏；卡片右侧留出的空位正好放滚动条
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scroll.autoresizingMask = [.width, .height]
        let column = NSTableColumn(identifier: .init("item"))
        column.resizingMask = .autoresizingMask
        column.width = w
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.menu = NSMenu()
        table.menu?.delegate = self
        scroll.documentView = table
        root.addSubview(scroll)

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = CGRect(x: 0, y: h / 2 - 10, width: w, height: 20)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        root.addSubview(emptyLabel)

        // 底栏：分隔线 + 条数 + 快捷键提示
        let line = NSBox(frame: CGRect(x: 0, y: 33, width: w, height: 1))
        line.boxType = .separator
        line.autoresizingMask = [.width]
        root.addSubview(line)
        let listIcon = NSImageView(image: NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil) ?? NSImage())
        listIcon.contentTintColor = .secondaryLabelColor
        listIcon.frame = CGRect(x: 12, y: 8, width: 18, height: 18)
        listIcon.toolTip = "↩ 粘贴  ⇧↩ 纯文本  ⌘1~9 快速粘贴  空格 预览  ⌘P 收藏  ⌘⌫ 删除"
        root.addSubview(listIcon)
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .center
        countLabel.frame = CGRect(x: 40, y: 10, width: w - 80, height: 14)
        countLabel.autoresizingMask = [.width]
        root.addSubview(countLabel)
    }

    /// 可拉伸的圆角遮罩：四个角固定，中间随面板大小拉伸
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let size = radius * 2 + 1
        let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func iconButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        return button
    }

    @objc private func togglePinPanel() {
        keepOpen.toggle()
        pinButton.image = NSImage(systemSymbolName: keepOpen ? "pin.fill" : "pin", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        pinButton.contentTintColor = keepOpen ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func openSettings() {
        hide()
        onOpenSettings?()
    }

    @objc private func doubleClicked() {
        if let item = selectedItem { onPaste?(item, false) }
    }

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    // MARK: - 键盘

    /// 搜索框里的方向键、回车、Esc
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): select(max(0, table.selectedRow - 1))
        case #selector(NSResponder.moveDown(_:)): select(min(rows.count - 1, table.selectedRow + 1))
        case #selector(NSResponder.insertNewline(_:)):
            if let item = selectedItem { onPaste?(item, NSEvent.modifierFlags.contains(.shift)) }
        case #selector(NSResponder.cancelOperation(_:)): hide()
        default: return false
        }
        return true
    }

    /// ⌘ 组合键和空格预览：面板显示期间用本地监听处理
    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isKeyWindow || self.preview.isKeyWindow else { return event }
            return self.handleShortcut(event) ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let char = event.charactersIgnoringModifiers ?? ""
        if flags == .command, let digit = Int(char), (1...9).contains(digit) {
            if rows.indices.contains(digit - 1) { onPaste?(rows[digit - 1], false) }
            return true
        }
        guard let item = selectedItem else { return false }
        switch (flags, char.lowercased(), event.keyCode) {
        case ([.command], "p", _): onTogglePin?(item); return true
        case ([.command], _, 51): onDelete?(item); return true
        case ([.command], "c", _) where search.currentEditor()?.selectedRange.length ?? 0 == 0:
            onCopy?(item); return true
        case ([], " ", _) where search.stringValue.isEmpty:
            preview.isVisible ? preview.orderOut(nil) : preview.show(item, store: store, beside: self)
            return true
        case ([], _, 53) where preview.isVisible:
            preview.orderOut(nil); return true
        default: return false
        }
    }

    // MARK: - 列表

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        ClipCardView.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        ClipCardView(item: rows[row], index: row, store: store, width: tableColumn?.width ?? Self.width)
    }

    /// 不画系统选中底色，选中由卡片描边表示
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshSelectionBorders()
        if preview.isVisible, let item = selectedItem { preview.show(item, store: store, beside: self) }
    }

    /// 新出现的行也要按选中状态描边
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        (rowView.view(atColumn: 0) as? ClipCardView)?.isSelected = rowView.isSelected
    }

    /// 选中的卡片强调色描边，其余去掉
    private func refreshSelectionBorders() {
        table.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? ClipCardView)?.isSelected = rowView.isSelected
        }
    }
}

// MARK: - 右键菜单

extension ClipboardPanel: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard rows.indices.contains(row) else { return }
        let item = rows[row]
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let menuItem = ClipMenuItem(title: title, handler: action)
            menuItem.isEnabled = enabled
            menu.addItem(menuItem)
        }
        add("粘贴") { [weak self] in self?.onPaste?(item, false) }
        add("粘贴为纯文本", enabled: item.kind == .text) { [weak self] in self?.onPaste?(item, true) }
        add("拷贝") { [weak self] in self?.onCopy?(item) }
        add(item.pinned ? "取消收藏" : "收藏") { [weak self] in self?.onTogglePin?(item) }
        add("贴到屏幕", enabled: item.kind == .image) { [weak self] in self?.onPinToScreen?(item) }
        if item.kind == .files {
            add("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) }) }
        }
        menu.addItem(.separator())
        add("删除") { [weak self] in self?.onDelete?(item) }
        add("清空历史（保留收藏）…") { [weak self] in self?.onClearAll?() }
    }
}

/// 菜单项事件转闭包
final class ClipMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

// MARK: - 预览

/// 空格预览：在面板旁边显示完整文字或大图
@MainActor
final class ClipPreviewPanel: NSPanel {
    private let textView = NSTextView()
    private let imageView = NSImageView()
    private let scroll = NSScrollView()

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 460, height: 560),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .floating
        let root = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 460, height: 560))
        root.material = .popover
        root.autoresizingMask = [.width, .height]
        contentView = root
        scroll.frame = root.bounds.insetBy(dx: 12, dy: 12)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        textView.isEditable = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.frame = CGRect(origin: .zero, size: scroll.contentSize)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        root.addSubview(scroll)
        imageView.frame = root.bounds.insetBy(dx: 12, dy: 12)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(imageView)
    }

    func show(_ item: ClipItem, store: ClipStore, beside panel: NSWindow) {
        let isImage = item.kind == .image
        scroll.isHidden = isImage
        imageView.isHidden = !isImage
        if isImage {
            imageView.image = store.imageURL(for: item).flatMap { NSImage(contentsOf: $0) }
        } else if let url = store.rtfURL(for: item), let rich = NSAttributedString(rtf: (try? Data(contentsOf: url)) ?? Data(),
                                                                                   documentAttributes: nil) {
            textView.textStorage?.setAttributedString(rich)
        } else {
            textView.string = item.kind == .files ? item.filePaths.joined(separator: "\n") : item.text
        }
        // 放在面板右侧，放不下就放左侧
        let screen = panel.screen?.visibleFrame ?? .zero
        var x = panel.frame.maxX + 8
        if x + frame.width > screen.maxX { x = panel.frame.minX - frame.width - 8 }
        setFrame(CGRect(x: x, y: panel.frame.maxY - frame.height, width: frame.width, height: frame.height), display: true)
        orderFront(nil)
    }
}

/// 始终用浮动滚动条的列表：系统设成“始终显示滚动条”或接了鼠标时，
/// 普通滚动条会占掉右边一条，卡片右边距就比左边宽；浮动滚动条叠在卡片右侧空位上，不占宽度
final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}
