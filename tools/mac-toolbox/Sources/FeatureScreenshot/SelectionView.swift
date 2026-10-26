import AppKit
import ToolboxCore

/// 截图遮罩上的交互视图：压暗、框选、窗口识别、调整手柄、放大镜取色
/// 冻结画面由父视图的图层显示，这里只画遮罩和标记，鼠标移动时不用重画整张截图
/// 操作：拖拽框选；单击选中光标下的窗口；拖动选区内部可移动；拖动手柄调整大小
///      方向键移动选区 1 点（⇧ 加速到 10 点）；C 复制颜色 HEX，⇧C 复制 RGB
///      回车/双击 = 复制，⌘S = 保存，Esc/右键 = 取消
final class SelectionView: NSView {
    private let frozen: FrozenScreen
    /// 本屏内可识别的窗口（已转成本视图坐标，从前到后）
    private let windowRects: [CGRect]
    private weak var session: CaptureSession?

    private(set) var selection: CGRect?
    private var hoverWindow: CGRect?
    /// 当前光标位置，放大镜跟着它画
    private var cursor: CGPoint?

    // 拖拽状态：新建选区 / 移动选区 / 拖动手柄，同时只有一种
    private var dragStart: CGPoint?
    private var moveOffset: CGPoint?
    private var activeHandle: ResizeHandle?
    private var rectBeforeResize: CGRect = .zero

    /// 截图界面的单键快捷键（可在工具栏悬浮提示框里修改）
    private let shortcuts: ToolShortcuts
    /// 截图设置（十字线、右键退出、双击动作等）
    private let settings: ScreenshotSettings
    /// 上一次按下“双击修饰键”的时间，用来判断双击
    private var lastModifierTap: Date?
    /// 只框选模式（OCR、录屏）：不显示标注工具栏，改用确认条
    private let purpose: CapturePurpose?
    private lazy var confirmBar: SelectionConfirmBar = {
        let bar = SelectionConfirmBar(purpose: purpose ?? .ocr)
        bar.onConfirm = { [weak self] in self?.session?.finish(.confirm) }
        bar.onCancel = { [weak self] in self?.session?.finish(.cancel) }
        addSubview(bar)
        return bar
    }()

    /// 所在显示器
    var displayID: CGDirectDisplayID { frozen.screen.displayID }
    /// 选区定下后显示的工具栏
    private let toolbar: AnnotationToolbar
    /// 选了标注工具后才创建；创建后选区锁定，不能再移动和调整
    private var canvas: AnnotationCanvas?

    /// 还没定下选区、或正在拖拽时才显示放大镜
    private var showsMagnifier: Bool {
        cursor != nil && canvas == nil && (selection == nil || dragStart != nil || activeHandle != nil)
    }

    private var isDragging: Bool { dragStart != nil || moveOffset != nil || activeHandle != nil }

    init(frozen: FrozenScreen, windowRects: [CGRect], shortcuts: ToolShortcuts, settings: ScreenshotSettings,
         purpose: CapturePurpose?, session: CaptureSession) {
        self.frozen = frozen
        self.purpose = purpose
        self.shortcuts = shortcuts
        self.settings = settings
        toolbar = AnnotationToolbar(shortcuts: shortcuts, tipDelay: settings.tipDelay)
        self.windowRects = windowRects
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        toolbar.isHidden = true
        toolbar.onAction = { [weak self] action in self?.handleToolbar(action) }
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// 清空本屏选区（其他屏开始框选时调用）
    func clearSelection() {
        selection = nil
        hoverWindow = nil
        cursor = nil
        toolbar.isHidden = true
        needsDisplay = true
    }

    /// 选区在全局屏幕坐标里的位置（贴图要放在原位）
    var selectionOnScreen: CGRect? {
        guard let selection, let window else { return nil }
        return window.convertToScreen(convert(selection, to: nil))
    }

    /// 截图像素 / 点
    var pixelScale: CGFloat { frozen.scale }

    /// 选区对应的图片；有标注时返回合成后的图片
    func croppedImage() -> CGImage? {
        if let canvas { return canvas.renderedImage() }
        return baseImage()
    }

    /// 选区内的原始截图
    private func baseImage() -> CGImage? {
        guard let selection else { return nil }
        let rect = SelectionGeometry.pixelRect(for: selection, viewHeight: bounds.height, scale: frozen.scale,
                                               imageSize: CGSize(width: frozen.image.width, height: frozen.image.height))
        return rect.isEmpty ? nil : frozen.image.cropping(to: rect)
    }

    // MARK: - 鼠标

    override func mouseMoved(with event: NSEvent) {
        // 鼠标移到这块屏幕时，键盘焦点跟过来（Esc、回车才有效）
        if window?.isKeyWindow == false {
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
        }
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        if selection == nil {
            hoverWindow = windowRects.first { $0.contains(point) }
        }
        updateCursor(at: point)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // 标注中选区已锁定，选区外的点击不处理
        guard canvas == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, selection?.contains(point) == true {
            purpose == nil ? performDoubleClick() : session?.finish(.confirm)
            return
        }
        session?.willBeginSelection(in: self)
        if let selection, let handle = SelectionGeometry.handle(at: point, in: selection) {
            // 按在手柄上：准备调整大小
            activeHandle = handle
            rectBeforeResize = selection
        } else if let selection, selection.contains(point) {
            // 在已有选区内按下：准备移动
            moveOffset = CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
        } else {
            dragStart = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), in: bounds)
        cursor = point
        if let handle = activeHandle {
            selection = SelectionGeometry.resize(rectBeforeResize, handle: handle, to: point)
        } else if let offset = moveOffset, let rect = selection {
            let moved = CGRect(origin: CGPoint(x: point.x - offset.x, y: point.y - offset.y), size: rect.size)
            selection = SelectionGeometry.clamp(moved, in: bounds)
        } else if let start = dragStart {
            selection = SelectionGeometry.rect(from: start, to: point)
            hoverWindow = nil
        }
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasCreating = dragStart != nil
        defer {
            dragStart = nil
            moveOffset = nil
            activeHandle = nil
            updateCursor(at: convert(event.locationInWindow, from: nil))
            layoutToolbar()
            needsDisplay = true
        }
        guard wasCreating else { return }
        // 拖动距离很小视为单击：选中光标下的窗口，没有窗口就选整屏
        if let rect = selection, rect.width > 3, rect.height > 3 { return }
        selection = hoverWindow ?? bounds
    }

    // MARK: - 工具栏和标注

    /// 工具栏放在选区下方右对齐；下方放不下放上方，再放不下放选区内底部
    private func layoutToolbar() {
        guard let selection, !isDragging else {
            toolbar.isHidden = true
            if purpose != nil { confirmBar.isHidden = true }
            return
        }
        // 只框选模式：选区下方放确认条
        if purpose != nil {
            let size = SelectionConfirmBar.size
            var origin = CGPoint(x: selection.maxX - size.width, y: selection.minY - size.height - 6)
            if origin.y < bounds.minY + 4 { origin.y = selection.maxY + 6 }
            if origin.y + size.height > bounds.maxY - 4 { origin.y = selection.minY + 6 }
            origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
            confirmBar.frame = CGRect(origin: origin, size: size)
            confirmBar.isHidden = false
            return
        }
        let size = toolbar.preferredSize
        var origin = CGPoint(x: selection.maxX - size.width, y: selection.minY - size.height - 6)
        if origin.y < bounds.minY + 4 { origin.y = selection.maxY + 6 }
        if origin.y + size.height > bounds.maxY - 4 { origin.y = selection.minY + 6 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        toolbar.frame = CGRect(origin: origin, size: size)
        toolbar.isHidden = false
    }

    private func handleToolbar(_ action: ToolbarAction) {
        switch action {
        case .selectTool(let tool): select(tool)
        case .styleChanged(let style): canvas?.style = style
        case .undo: canvas?.undo()
        case .save: session?.finish(.save)
        case .pin: session?.finish(.pin)
        case .ocr: session?.finish(.ocr)
        case .cancel: session?.finish(.cancel)
        case .copy: session?.finish(.copy)
        }
        // 点完按钮把键盘焦点拿回来，快捷键才继续有效
        if window?.firstResponder is NSButton { window?.makeFirstResponder(self) }
    }

    /// 选工具：第一次选时创建画布并锁定选区
    private func select(_ tool: AnnotationTool) {
        guard let selection else { return }
        if canvas == nil {
            guard let base = baseImage() else { return }
            let canvas = AnnotationCanvas(frame: selection, baseImage: base)
            canvas.style = toolbar.style
            canvas.onChange = { [weak self] in self?.refreshUndoState() }
            // 选中已有元素：工具栏回显它的样式，之后改样式就作用到它
            canvas.onSelectionChange = { [weak self, weak canvas] style in
                guard let style else { return }
                self?.toolbar.show(style: style)
                canvas?.style = style
            }
            addSubview(canvas, positioned: .below, relativeTo: toolbar)
            self.canvas = canvas
            refreshUndoState()
        }
        canvas?.tool = tool
        toolbar.select(tool: tool)
        layoutToolbar()
        needsDisplay = true
    }

    private func refreshUndoState() {
        toolbar.setUndoState(canUndo: canvas?.document.canUndo ?? false)
    }

    /// 右键：默认退出截图；关掉“右键点击退出截图”后只取消当前选区
    override func rightMouseDown(with event: NSEvent) {
        if settings.rightClickExit {
            session?.finish(.cancel)
        } else if canvas == nil, selection != nil {
            clearSelection()
        }
    }

    /// 双击选区：按设置里的“双击鼠标左键触发”执行
    private func performDoubleClick() {
        switch settings.doubleClickAction {
        case .none: break
        case .ocr: session?.finish(.ocr)
        case .pin: session?.finish(.pin)
        case .save: session?.finish(.save)
        case .copy: session?.finish(.copy)
        case .saveAndCopy: session?.finish(.saveAndCopy)
        }
    }

    /// 连按两次设置里的修饰键（默认 Option）：保存截图并用指定 App 打开
    override func flagsChanged(with event: NSEvent) {
        let keys: [NSEvent.ModifierFlags] = [.option, .command, .control]
        let target = keys[min(settings.doubleTapModifier, keys.count - 1)]
        let pressed = event.modifierFlags.intersection([.option, .command, .control, .shift])
        guard pressed == target, selection != nil else { return }
        if let last = lastModifierTap, Date().timeIntervalSince(last) < 0.4 {
            lastModifierTap = nil
            session?.finish(.saveAndOpen)
        } else {
            lastModifierTap = Date()
        }
    }

    /// 按位置切换光标样式：手柄上显示调整箭头，选区内显示手形
    private func updateCursor(at point: CGPoint) {
        if let canvas {
            (canvas.tool == .text && canvas.frame.contains(point) ? NSCursor.iBeam : NSCursor.crosshair).set()
            return
        }
        guard let selection, dragStart == nil else { NSCursor.crosshair.set(); return }
        switch SelectionGeometry.handle(at: point, in: selection) {
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .some: NSCursor.crosshair.set()
        case .none: (selection.contains(point) ? NSCursor.openHand : NSCursor.crosshair).set()
        }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        let command = flags.contains(.command)
        // 只框选模式：回车确认、Esc 取消、方向键移动，其他键不处理
        if purpose != nil {
            switch event.keyCode {
            case 36, 76: if selection != nil { session?.finish(.confirm) }
            case 53: session?.finish(.cancel)
            case 123...126: nudge(keyCode: event.keyCode, step: flags.contains(.shift) ? 10 : 1)
            default: break
            }
            return
        }
        // 有选区时先查自定义单键快捷键（默认同 iShot：1~9 工具、空格保存、回车复制）
        if !command, selection != nil,
           let key = ToolShortcuts.key(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode),
           let action = shortcuts.action(forKey: key) {
            perform(action)
            return
        }
        switch (event.keyCode, command) {
        case (53, _): session?.finish(.cancel)                // Esc
        case (36, _), (76, _): session?.finish(.copy)         // 回车（还没有选区时也能用）
        case (8, true): session?.finish(.copy)                // ⌘C
        case (8, false) where selection == nil:
            copyColor(asRGB: flags.contains(.shift))          // 框选前 C / ⇧C 复制颜色
        case (1, true): session?.finish(.save)                // ⌘S
        case (6, true): flags.contains(.shift) ? canvas?.redo() : canvas?.undo()  // ⌘Z / ⇧⌘Z
        case (51, false), (117, false): canvas?.deleteSelection()                  // Delete
        case (123...126, false) where canvas == nil:
            nudge(keyCode: event.keyCode, step: flags.contains(.shift) ? 10 : 1)
        default: super.keyDown(with: event)
        }
    }

    /// 执行快捷键对应的操作；长截图还没做
    private func perform(_ action: ShortcutAction) {
        if let tool = action.tool { select(tool); return }
        switch action {
        case .save: session?.finish(.save)
        case .copy: session?.finish(.copy)
        case .pin: session?.finish(.pin)
        case .ocr: session?.finish(.ocr)
        default: break
        }
    }

    /// 方向键移动选区
    private func nudge(keyCode: UInt16, step: CGFloat) {
        guard var rect = selection else { return }
        switch keyCode {
        case 123: rect.origin.x -= step  // ←
        case 124: rect.origin.x += step  // →
        case 125: rect.origin.y -= step  // ↓
        default: rect.origin.y += step   // ↑
        }
        selection = SelectionGeometry.clamp(rect, in: bounds)
        layoutToolbar()
        needsDisplay = true
    }

    /// 复制光标处的颜色并结束截图
    private func copyColor(asRGB: Bool) {
        guard let cursor else { return }
        let size = CGSize(width: frozen.image.width, height: frozen.image.height)
        let pixel = Magnifier.pixel(at: cursor, viewHeight: bounds.height, scale: frozen.scale, imageSize: size)
        guard let color = PixelColor.read(from: frozen.image, x: pixel.x, y: pixel.y) else { return }
        session?.finish(.copyColor(asRGB ? color.rgb : color.hex))
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 选区以外压暗
        let highlight = selection ?? hoverWindow
        let mask = NSBezierPath(rect: bounds)
        if let highlight { mask.append(NSBezierPath(rect: highlight).reversed) }
        NSColor.black.withAlphaComponent(0.35).setFill()
        mask.fill()

        if let highlight {
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: -1, dy: -1))
            border.lineWidth = selection == nil ? 3 : 1.5
            border.stroke()
        }
        if let selection {
            if dragStart == nil, canvas == nil { drawHandles(for: selection) }
            drawSizeLabel(for: selection)
        }
        // 截图光标辅助十字线：框选前横竖两条线穿过光标
        if settings.crosshair, selection == nil, let cursor {
            NSColor.systemBlue.withAlphaComponent(0.6).setFill()
            CGRect(x: 0, y: cursor.y.rounded() - 0.5, width: bounds.width, height: 1).fill()
            CGRect(x: cursor.x.rounded() - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
        if showsMagnifier, let cursor {
            Magnifier.draw(image: frozen.image, cursor: cursor, viewBounds: bounds, scale: frozen.scale)
        }
    }

    /// 8 个白底蓝边的小方块
    private func drawHandles(for rect: CGRect) {
        let side: CGFloat = 7
        for handle in ResizeHandle.allCases {
            let center = handle.center(in: rect)
            let square = NSBezierPath(rect: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            NSColor.white.setFill()
            square.fill()
            NSColor.systemBlue.setStroke()
            square.stroke()
        }
    }

    /// 选区左上方显示像素尺寸
    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width * frozen.scale)) × \(Int(rect.height * frozen.scale))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + size.height + 4 > bounds.maxY { origin.y = rect.maxY - size.height - 10 }
        let background = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 2), withAttributes: attrs)
    }
}
