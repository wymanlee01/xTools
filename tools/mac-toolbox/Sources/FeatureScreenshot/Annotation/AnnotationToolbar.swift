import AppKit

/// 工具栏触发的动作
enum ToolbarAction {
    case selectTool(AnnotationTool)
    case styleChanged(AnnotationStyle)
    case undo, save, cancel, copy
}

/// 截图工具栏，尺寸、按钮顺序、样式栏布局都按 iShot 的界面1:1 复刻：
/// - 主工具栏 526×40：16 个 20×20 按钮，左边距 12、间距 12（图标资源也是 20×20 点）
/// - 样式栏 290×45：大小 / 不透明度滑块、5 个预设色 + 自定义色、各工具专属选项
/// - 悬浮提示框：工具名 + 可修改的快捷键，显示在工具栏上方，6 秒后自动隐藏
/// 图标用系统 SF Symbols，不使用 iShot 的图片资源
final class AnnotationToolbar: NSView {
    static let mainSize = CGSize(width: 526, height: 40)
    static let styleSize = CGSize(width: 290, height: 45)
    /// 样式栏上方指向当前工具的小三角高度
    static let arrowHeight: CGFloat = 7

    var onAction: ((ToolbarAction) -> Void)?
    private(set) var activeTool: AnnotationTool?
    private(set) var style = AnnotationStyle()

    private let shortcuts: ToolShortcuts
    private let mainBar = BarView()
    private let styleBar = StyleBar()
    private var toolButtons: [AnnotationTool: IconButton] = [:]
    private var undoButton: IconButton!

    /// 悬浮提示框：加在父视图上，才能显示在工具栏外面
    private var tipBox: TipBox?
    private var tipButton: IconButton?
    private var tipHideTimer: Timer?

    init(shortcuts: ToolShortcuts) {
        self.shortcuts = shortcuts
        super.init(frame: CGRect(origin: .zero, size: Self.mainSize))
        appearance = NSAppearance(named: .darkAqua)
        buildMainBar()
        styleBar.onChange = { [weak self] style in
            self?.style = style
            self?.onAction?(.styleChanged(style))
        }
        styleBar.isHidden = true
        addSubview(mainBar)
        addSubview(styleBar)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 点在工具栏空白处不往下传，避免被当成重新框选
    override func mouseDown(with event: NSEvent) {}

    /// 有工具时主工具栏下面多一行样式栏
    var preferredSize: CGSize {
        activeTool == nil ? Self.mainSize
            : CGSize(width: Self.mainSize.width, height: Self.mainSize.height + Self.arrowHeight + Self.styleSize.height)
    }

    override var isHidden: Bool {
        didSet { if isHidden { hideTip() } }
    }

    func select(tool: AnnotationTool) {
        activeTool = tool
        for (t, button) in toolButtons { button.isOn = t == tool }
        styleBar.configure(for: tool, style: style)
        styleBar.isHidden = false
        needsLayout = true
    }

    /// 选中已有元素时，样式栏显示它的样式
    func show(style: AnnotationStyle) {
        self.style = style
        if let tool = activeTool { styleBar.configure(for: tool, style: style) }
    }

    func setUndoState(canUndo: Bool) {
        undoButton.isEnabled = canUndo
    }

    override func layout() {
        super.layout()
        // 主工具栏在最上面（视图坐标原点在左下）
        mainBar.frame = CGRect(origin: CGPoint(x: 0, y: bounds.height - Self.mainSize.height), size: Self.mainSize)
        guard let tool = activeTool, let button = toolButtons[tool] else { return }
        // 样式栏放在主工具栏下方，小三角对准当前工具按钮
        let buttonCenter = mainBar.frame.minX + button.frame.midX
        let x = min(max(buttonCenter - 30, 0), Self.mainSize.width - Self.styleSize.width)
        styleBar.frame = CGRect(x: x, y: 0, width: Self.styleSize.width, height: Self.styleSize.height + Self.arrowHeight)
        styleBar.arrowX = buttonCenter - x
    }

    // MARK: - 主工具栏

    private func buildMainBar() {
        // 顺序、提示文字、提示框尺寸都和 iShot 一致；贴图、OCR、长截图功能还没做，按钮置灰占位
        typealias Item = (symbol: String, tip: TipSpec, tool: AnnotationTool?, action: ToolbarAction?, enabled: Bool)
        func shortcut(_ title: String, _ action: ShortcutAction, width: CGFloat = 120) -> TipSpec {
            TipSpec(title: title, size: CGSize(width: width, height: 70), body: .shortcut(action, note: nil))
        }
        let items: [Item] = [
            ("square", shortcut("矩形工具", .rectangle, width: 125), .rectangle, nil, true),
            ("circle", shortcut("椭圆工具", .ellipse), .ellipse, nil, true),
            ("line.diagonal", shortcut("直线工具", .line), .line, nil, true),
            ("arrow.up.right", shortcut("箭头工具", .arrow), .arrow, nil, true),
            ("pencil", shortcut("铅笔工具", .pencil), .pencil, nil, true),
            ("checkerboard.rectangle", shortcut("像素化工具", .mosaic), .mosaic, nil, true),
            ("character", shortcut("文本工具", .text, width: 130), .text, nil, true),
            ("1.circle", shortcut("步骤标注工具", .step, width: 130), .step, nil, true),
            ("highlighter", shortcut("高亮工具", .highlight), .highlight, nil, true),
            ("pin", shortcut("贴图", .pin), nil, nil, false),
            ("arrow.uturn.backward",
             TipSpec(title: "撤销工具", size: CGSize(width: 154, height: 90),
                     body: .lines(["上一步快捷键 : ⌘Z", "下一步快捷键 : ⇧⌘Z"])), nil, .undo, true),
            ("text.viewfinder", shortcut("OCR工具", .ocr), nil, nil, false),
            ("xmark",
             TipSpec(title: "取消截图", size: CGSize(width: 110, height: 90),
                     body: .lines(["快捷键 : ESC", "或者右键点击"])), nil, .cancel, true),
            ("arrow.up.and.down.text.horizontal", shortcut("长截图", .scroll), nil, nil, false),
            ("square.and.arrow.down",
             TipSpec(title: "保存截图", size: CGSize(width: 120, height: 95), body: .shortcut(.save, note: "ㄩ是空格键")),
             nil, .save, true),
            ("checkmark", shortcut("拷贝截图到剪切板", .copy, width: 130), nil, .copy, true),
        ]
        for (index, item) in items.enumerated() {
            let button = IconButton(symbol: item.symbol, label: item.tip.title)
            // 原版界面里按钮在内容区 (12 + 32i, 9)，内容区相对边框偏移 1
            button.frame = CGRect(x: 13 + CGFloat(index) * 32, y: 10, width: 20, height: 20)
            button.isEnabled = item.enabled
            if let tool = item.tool {
                toolButtons[tool] = button
                button.onClick = { [weak self] in self?.onAction?(.selectTool(tool)) }
            } else if let action = item.action {
                button.onClick = { [weak self] in self?.onAction?(action) }
            }
            if case .undo? = item.action { undoButton = button }
            let tip = item.tip
            button.onHover = { [weak self, weak button] inside in
                guard let self, let button else { return }
                inside ? self.showTip(tip, for: button) : self.scheduleHideTip()
            }
            mainBar.addSubview(button)
        }
        undoButton.isEnabled = false
    }

    // MARK: - 悬浮提示框

    /// 显示在工具栏上方、对准按钮；上方放不下就放下方
    private func showTip(_ spec: TipSpec, for button: IconButton) {
        guard let host = superview else { return }
        tipHideTimer?.invalidate()
        if tipButton === button, tipBox != nil { return }
        hideTip()

        let box = TipBox(spec: spec, shortcuts: shortcuts)
        box.onHover = { [weak self] inside in
            inside ? self?.tipHideTimer?.invalidate() : self?.scheduleHideTip()
        }
        let center = button.convert(CGPoint(x: button.bounds.midX, y: 0), to: host).x
        var origin = CGPoint(x: center - spec.size.width / 2, y: frame.maxY + 10)
        if origin.y + spec.size.height > host.bounds.maxY - 4 { origin.y = frame.minY - spec.size.height - 10 }
        origin.x = min(max(origin.x, 4), host.bounds.maxX - spec.size.width - 4)
        box.frame = CGRect(origin: origin, size: spec.size)
        host.addSubview(box)
        tipBox = box
        tipButton = button
        // 和 iShot 一样 6 秒后自动隐藏（鼠标停在提示框里时不隐藏）
        tipHideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideTipIfIdle() }
        }
    }

    /// 离开按钮后稍等一下再隐藏，方便把鼠标移进提示框改快捷键
    private func scheduleHideTip() {
        tipHideTimer?.invalidate()
        tipHideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideTipIfIdle() }
        }
    }

    private func hideTipIfIdle() {
        guard let box = tipBox, let window else { return }
        let mouse = box.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if box.bounds.contains(mouse) { return }
        hideTip()
    }

    private func hideTip() {
        tipHideTimer?.invalidate()
        tipBox?.removeFromSuperview()
        tipBox = nil
        tipButton = nil
    }
}

/// 悬浮提示框的内容，文字和尺寸取自 iShot 的界面
struct TipSpec {
    enum Body {
        /// 工具名 + “快捷键”下拉框；note 是额外说明（如“ㄩ是空格键”）
        case shortcut(ShortcutAction, note: String?)
        /// 工具名 + 若干行固定说明
        case lines([String])
    }

    let title: String
    let size: CGSize
    let body: Body
}

/// 悬浮提示框：跟随系统深浅色（深色 #242424 白字，浅色白底黑字），圆角 10、灰色细边框
final class TipBox: NSView {
    var onHover: ((Bool) -> Void)?
    private let isDark: Bool
    private var popupTarget: PopupTarget?

    init(spec: TipSpec, shortcuts: ToolShortcuts) {
        isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        super.init(frame: CGRect(origin: .zero, size: spec.size))
        appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let textColor = isDark ? NSColor.white.withAlphaComponent(0.85) : NSColor.black

        func label(_ text: String, _ frame: CGRect) {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 13)
            field.textColor = textColor
            field.frame = frame
            addSubview(field)
        }

        let width = spec.size.width - 20
        switch spec.body {
        case .shortcut(let action, let note):
            // 坐标取自原版界面：标题 (12,41)，“快捷键” (12,16)，下拉框 (60,12)；保存框高 95，整体上移一行
            let lift: CGFloat = note == nil ? 0 : 22
            label(spec.title, CGRect(x: 12, y: 41 + lift, width: width, height: 17))
            label("快捷键", CGRect(x: 12, y: 16 + lift, width: 44, height: 17))
            let popup = NSPopUpButton(frame: CGRect(x: 60, y: 12 + lift, width: 47, height: 22), pullsDown: false)
            popup.font = .systemFont(ofSize: 11)
            let allowsSpecial = action == .save || action == .copy
            popup.addItems(withTitles: ToolShortcuts.keys + (allowsSpecial ? ToolShortcuts.specialKeys : []))
            popup.selectItem(withTitle: shortcuts.key(for: action))
            let target = PopupTarget { key in shortcuts.set(key, for: action) }
            popup.target = target
            popup.action = #selector(PopupTarget.changed(_:))
            popupTarget = target  // NSPopUpButton 不持有 target，由提示框持有
            addSubview(popup)
            if let note { label(note, CGRect(x: 10, y: 13, width: width, height: 17)) }
        case .lines(let lines):
            label(spec.title, CGRect(x: 12, y: 64, width: width, height: 17))
            for (index, line) in lines.enumerated() {
                label(line, CGRect(x: 12, y: 39 - CGFloat(index) * 25, width: width, height: 17))
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        (isDark ? NSColor(srgbRed: 0.141, green: 0.141, blue: 0.141, alpha: 1) : NSColor.white).setFill()
        path.fill()
        NSColor.gray.setStroke()
        path.lineWidth = 0.3
        path.stroke()
    }
}

/// 下拉框的事件接收者（NSPopUpButton 需要一个 Objective-C 对象做 target）
private final class PopupTarget: NSObject {
    private let handler: (String) -> Void

    init(_ handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    @objc func changed(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem { handler(title) }
    }
}

// MARK: - 样式栏

/// 第二行：大小、不透明度、颜色、工具专属选项。坐标都取自 iShot 的界面
private final class StyleBar: NSView {
    var onChange: ((AnnotationStyle) -> Void)?
    /// 小三角的中心 x（相对样式栏）
    var arrowX: CGFloat = 40 { didSet { needsDisplay = true } }

    private var style = AnnotationStyle()
    private var tool: AnnotationTool = .rectangle

    private let sizeSlider = StyleBar.makeSlider(y: 22)
    private let opacitySlider = StyleBar.makeSlider(y: 2)
    private let sizeValue = StyleBar.makeLabel("", frame: CGRect(x: 76, y: 25, width: 24, height: 11), alignment: .right)
    private let opacityValue = StyleBar.makeLabel("", frame: CGRect(x: 76, y: 5, width: 24, height: 11), alignment: .right)

    /// 颜色区（106~176）：5 个预设色 + 自定义色；高亮、马赛克时换成单选项
    private let colorArea = NSView(frame: CGRect(x: 106, y: 2, width: 70, height: 40))
    private var swatches: [ColorSwatch] = []
    private var customColor = AnnotationColor(red: 1, green: 1, blue: 1)
    private let radioArea = NSView(frame: CGRect(x: 106, y: 2, width: 70, height: 40))
    private var radioA = NSButton(), radioB = NSButton()

    /// 选项区：矩形（实心、圆角）、椭圆（实心）、箭头（曲线箭头）
    private let checkArea = NSView(frame: CGRect(x: 182, y: 2, width: 70, height: 40))
    private let filledBox = StyleBar.makeCheckbox("实心", frame: CGRect(x: 4, y: 19, width: 52, height: 20))
    private let roundedBox = StyleBar.makeCheckbox("圆角", frame: CGRect(x: 4, y: -1, width: 52, height: 21))
    private let curvedBox = StyleBar.makeCheckbox("曲线箭头", frame: CGRect(x: 4, y: 19, width: 77, height: 20))

    /// 选项区：文字、步骤标注（背景、背景色、字体），画笔（模式）
    private let popupArea = NSView(frame: CGRect(x: 180, y: 2, width: 105, height: 40))
    private let backgroundPopup = StyleBar.makePopup(TextBackground.allCases.map(\.title), frame: CGRect(x: 2, y: 17, width: 58, height: 22))
    private let backgroundColorPopup = StyleBar.makePopup([], frame: CGRect(x: 55, y: 17, width: 48, height: 22))
    private let fontPopup = StyleBar.makePopup(StyleBar.fonts.map(\.title), frame: CGRect(x: 2, y: -3, width: 101, height: 22))
    private let pencilPopup = StyleBar.makePopup(PencilMode.allCases.map(\.title), frame: CGRect(x: 2, y: 17, width: 78, height: 22))

    /// 字体选项：iShot 默认“系统默认”，其余字体它在运行时填入；这里给几种常用中文字体
    static let fonts: [(title: String, name: String?)] = [
        ("系统默认", nil), ("苹方", "PingFangSC-Regular"), ("宋体", "STSongti-SC-Regular"),
        ("楷体", "STKaiti"), ("等宽", "Menlo-Regular"),
    ]

    init() {
        super.init(frame: CGRect(origin: .zero, size: AnnotationToolbar.styleSize))
        let content = NSView(frame: CGRect(x: 1, y: 1, width: 288, height: 43))
        addSubview(content)

        content.addSubview(Self.makeLabel("大小", frame: CGRect(x: 0, y: 26, width: 40, height: 10), alignment: .center))
        content.addSubview(Self.makeLabel("不透明度", frame: CGRect(x: 0, y: 5, width: 41, height: 11), alignment: .center))
        for view in [sizeSlider, opacitySlider, sizeValue, opacityValue] as [NSView] { content.addSubview(view) }
        sizeSlider.target = self
        sizeSlider.action = #selector(slidersChanged)
        opacitySlider.target = self
        opacitySlider.action = #selector(slidersChanged)

        buildColorArea()
        buildRadioArea()
        for box in [filledBox, roundedBox, curvedBox] {
            box.target = self
            box.action = #selector(optionsChanged)
            checkArea.addSubview(box)
        }
        curvedBox.isEnabled = false
        curvedBox.toolTip = "曲线箭头（开发中）"

        fillBackgroundColors()
        for popup in [backgroundPopup, backgroundColorPopup, fontPopup, pencilPopup] {
            popup.target = self
            popup.action = #selector(optionsChanged)
            popupArea.addSubview(popup)
        }
        for area in [colorArea, radioArea, checkArea, popupArea] { content.addSubview(area) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 按工具显示对应的控件，并回显样式
    func configure(for tool: AnnotationTool, style: AnnotationStyle) {
        self.tool = tool
        self.style = style

        // 颜色区：高亮、马赛克换成单选项（iShot 同样替换）
        let usesRadio = tool == .highlight || tool == .mosaic
        colorArea.isHidden = usesRadio
        radioArea.isHidden = !usesRadio
        if tool == .highlight {
            setRadio(a: "矩形", b: "椭圆", aFrame: CGRect(x: 4, y: 20, width: 52, height: 20),
                     bFrame: CGRect(x: 4, y: -1, width: 52, height: 20), bOn: style.highlightOval)
        } else if tool == .mosaic {
            setRadio(a: "马赛克", b: "毛玻璃", aFrame: CGRect(x: 6, y: 20, width: 67, height: 20),
                     bFrame: CGRect(x: 6, y: -1, width: 67, height: 20), bOn: style.mosaicBlur)
        }

        checkArea.isHidden = ![.rectangle, .ellipse, .arrow].contains(tool)
        filledBox.isHidden = !(tool == .rectangle || tool == .ellipse)
        roundedBox.isHidden = tool != .rectangle
        curvedBox.isHidden = tool != .arrow
        filledBox.state = style.filled ? .on : .off
        roundedBox.state = style.rounded ? .on : .off

        let textLike = tool == .text || tool == .step
        popupArea.isHidden = !(textLike || tool == .pencil)
        for popup in [backgroundPopup, backgroundColorPopup, fontPopup] { popup.isHidden = !textLike }
        pencilPopup.isHidden = tool != .pencil
        backgroundPopup.selectItem(at: style.textBackground.rawValue)
        backgroundColorPopup.selectItem(at: textBackgroundColors.firstIndex(of: style.textBackgroundColor) ?? 0)
        fontPopup.selectItem(at: Self.fonts.firstIndex { $0.name == style.fontName } ?? 0)
        pencilPopup.selectItem(at: style.pencilMode.rawValue)

        sizeSlider.doubleValue = Double(style.size)
        opacitySlider.doubleValue = Double(style.opacity * 100)
        refreshValues()
        refreshSwatches()
        needsDisplay = true
    }

    // MARK: - 事件

    @objc private func slidersChanged() {
        style.size = max(1, CGFloat(sizeSlider.doubleValue))
        style.opacity = max(0.1, CGFloat(opacitySlider.doubleValue) / 100)
        refreshValues()
        onChange?(style)
    }

    @objc private func optionsChanged() {
        style.filled = filledBox.state == .on
        style.rounded = roundedBox.state == .on
        if tool == .highlight { style.highlightOval = radioB.state == .on }
        if tool == .mosaic { style.mosaicBlur = radioB.state == .on }
        style.textBackground = TextBackground(rawValue: backgroundPopup.indexOfSelectedItem) ?? .none
        style.textBackgroundColor = textBackgroundColors[max(0, backgroundColorPopup.indexOfSelectedItem)]
        style.fontName = Self.fonts[max(0, fontPopup.indexOfSelectedItem)].name
        style.pencilMode = PencilMode(rawValue: pencilPopup.indexOfSelectedItem) ?? .color
        onChange?(style)
    }

    private func pick(_ color: AnnotationColor) {
        style.color = color
        refreshSwatches()
        onChange?(style)
    }

    /// 自定义颜色：打开系统取色面板
    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        // 面板要浮在截图遮罩上面
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue)
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        customColor = AnnotationColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        swatches.last?.color = customColor
        pick(customColor)
    }

    // MARK: - 构建与刷新

    private func buildColorArea() {
        // 原版界面里颜色块在 (111/133/155, 22) 和 (111/133/155, 4)，换算到颜色区内
        let origins = [(111, 22), (133, 22), (155, 22), (111, 4), (133, 4), (155, 4)]
        for (index, origin) in origins.enumerated() {
            let isCustom = index == origins.count - 1
            let swatch = ColorSwatch(color: isCustom ? customColor : AnnotationColor.presets[index])
            swatch.frame = CGRect(x: CGFloat(origin.0) - 106, y: CGFloat(origin.1) - 2, width: 16, height: 16)
            swatch.onClick = { [weak self, weak swatch] in
                guard let self, let swatch else { return }
                self.pick(swatch.color)
            }
            colorArea.addSubview(swatch)
            swatches.append(swatch)
        }
        // 自定义色右下角的小按钮（原版界面里 10×10，位于 (162, 2)）
        let set = IconButton(symbol: "eyedropper", label: "自定义颜色", fitSize: 9)
        set.frame = CGRect(x: 162 - 106, y: 0, width: 10, height: 10)
        set.onClick = { [weak self] in self?.openColorPanel() }
        colorArea.addSubview(set)
    }

    private func buildRadioArea() {
        radioA = NSButton(radioButtonWithTitle: "", target: self, action: #selector(optionsChanged))
        radioB = NSButton(radioButtonWithTitle: "", target: self, action: #selector(optionsChanged))
        for radio in [radioA, radioB] {
            radio.controlSize = .small
            radio.font = .systemFont(ofSize: 11)
            radioArea.addSubview(radio)
        }
    }

    private func setRadio(a: String, b: String, aFrame: CGRect, bFrame: CGRect, bOn: Bool) {
        radioA.title = a
        radioB.title = b
        radioA.frame = aFrame
        radioB.frame = bFrame
        radioA.state = bOn ? .off : .on
        radioB.state = bOn ? .on : .off
    }

    private func fillBackgroundColors() {
        backgroundColorPopup.removeAllItems()
        for color in textBackgroundColors {
            backgroundColorPopup.addItem(withTitle: "")
            backgroundColorPopup.lastItem?.image = ColorSwatch.image(color, size: CGSize(width: 22, height: 10))
        }
    }

    private func refreshValues() {
        sizeValue.stringValue = "\(Int(style.size))"
        opacityValue.stringValue = "\(Int((style.opacity * 100).rounded()))"
    }

    private func refreshSwatches() {
        for swatch in swatches { swatch.isSelected = swatch.color == style.color }
    }

    // MARK: - 绘制：深色底、边框、两条分隔线、指向工具的小三角

    override func draw(_ dirtyRect: NSRect) {
        let body = CGRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: AnnotationToolbar.styleSize.height - 1)
        let arrow = NSBezierPath()
        let tipY = bounds.height - 0.5
        arrow.move(to: CGPoint(x: arrowX - 7, y: body.maxY))
        arrow.line(to: CGPoint(x: arrowX, y: tipY))
        arrow.line(to: CGPoint(x: arrowX + 7, y: body.maxY))
        arrow.close()
        let path = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
        path.append(arrow)
        BarView.fill.setFill()
        path.fill()
        BarView.border.setStroke()
        NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6).stroke()

        // 分隔线：原版界面里是 (101, 3, 5, 34) 和 (176, 3, 5, 34) 的竖线
        NSColor.white.withAlphaComponent(0.15).setFill()
        for x in [104.0, 179.0] { CGRect(x: x, y: 4, width: 1, height: 34).fill() }
    }

    // MARK: - 控件工厂

    private static func makeSlider(y: CGFloat) -> NSSlider {
        let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
        slider.controlSize = .mini
        slider.frame = CGRect(x: 38, y: y, width: 46, height: 17)
        slider.isContinuous = true
        return slider
    }

    private static func makeLabel(_ text: String, frame: CGRect, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 8)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.frame = frame
        return label
    }

    private static func makeCheckbox(_ title: String, frame: CGRect) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.controlSize = .small
        box.font = .systemFont(ofSize: 11)
        box.frame = frame
        return box
    }

    private static func makePopup(_ titles: [String], frame: CGRect) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame, pullsDown: false)
        popup.controlSize = .mini
        popup.font = .systemFont(ofSize: 9)
        popup.addItems(withTitles: titles)
        return popup
    }
}

// MARK: - 小部件

/// 深色圆角底板（颜色取自原版界面：填充 #2E2E2E，边框 #666666，圆角 6）
private final class BarView: NSView {
    static let fill = NSColor(srgbRed: 0.180, green: 0.180, blue: 0.180, alpha: 1)
    static let border = NSColor(srgbRed: 0.401, green: 0.402, blue: 0.402, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        Self.fill.setFill()
        path.fill()
        Self.border.setStroke()
        path.stroke()
    }
}

/// 只有图标的按钮：常态浅灰，选中蓝色，不可用时半透明
/// 图标等比放大到 19×19，撑满 20×20 的按钮（iShot 的图标资源就是画满 20×20 的）
private final class IconButton: NSView {
    var onClick: (() -> Void)?
    /// 鼠标进入 / 离开，用来显示悬浮提示框
    var onHover: ((Bool) -> Void)?
    var isOn = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    private let image: NSImage?
    private let fitSize: CGFloat
    private var hovering = false { didSet { needsDisplay = true } }
    private var hoverArea: NSTrackingArea?

    init(symbol: String, label: String, fitSize: CGFloat = 19) {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(config)
        self.fitSize = fitSize
        super.init(frame: .zero)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(false) }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let tint: NSColor = !isEnabled ? .white.withAlphaComponent(0.25)
            : isOn ? .systemBlue : hovering ? .white : NSColor(white: 0.84, alpha: 1)
        // 等比缩放到 fitSize 见方以内并居中
        let scale = fitSize / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        let tinted = NSImage(size: image.size, flipped: false) { drawRect in
            image.draw(in: drawRect)
            tint.set()
            drawRect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect)
    }
}

/// 颜色块：16×16，选中时加白框
private final class ColorSwatch: NSView {
    var color: AnnotationColor { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    init(color: AnnotationColor) {
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(cgColor: color.cgColor())?.setFill()
        let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 2, yRadius: 2)
        inner.fill()
        (isSelected ? NSColor.white : NSColor.white.withAlphaComponent(0.2)).setStroke()
        inner.lineWidth = isSelected ? 1.5 : 0.5
        inner.stroke()
    }

    static func image(_ color: AnnotationColor, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor(cgColor: color.cgColor())?.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            return true
        }
    }
}
