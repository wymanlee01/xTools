import AppKit

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

    /// 还没定下选区、或正在拖拽时才显示放大镜
    private var showsMagnifier: Bool {
        cursor != nil && (selection == nil || dragStart != nil || activeHandle != nil)
    }

    init(frozen: FrozenScreen, windowRects: [CGRect], session: CaptureSession) {
        self.frozen = frozen
        self.windowRects = windowRects
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// 清空本屏选区（其他屏开始框选时调用）
    func clearSelection() {
        selection = nil
        hoverWindow = nil
        cursor = nil
        needsDisplay = true
    }

    /// 选区对应的图片
    func croppedImage() -> CGImage? {
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
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, selection?.contains(point) == true {
            session?.finish(.copy)
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
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasCreating = dragStart != nil
        defer {
            dragStart = nil
            moveOffset = nil
            activeHandle = nil
            updateCursor(at: convert(event.locationInWindow, from: nil))
            needsDisplay = true
        }
        guard wasCreating else { return }
        // 拖动距离很小视为单击：选中光标下的窗口，没有窗口就选整屏
        if let rect = selection, rect.width > 3, rect.height > 3 { return }
        selection = hoverWindow ?? bounds
    }

    override func rightMouseDown(with event: NSEvent) {
        session?.finish(.cancel)
    }

    /// 按位置切换光标样式：手柄上显示调整箭头，选区内显示手形
    private func updateCursor(at point: CGPoint) {
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
        switch (event.keyCode, flags.contains(.command)) {
        case (53, _): session?.finish(.cancel)                // Esc
        case (36, _), (76, _): session?.finish(.copy)         // 回车
        case (8, true): session?.finish(.copy)                // ⌘C
        case (8, false): copyColor(asRGB: flags.contains(.shift)) // C / ⇧C
        case (1, true): session?.finish(.save)                // ⌘S
        case (123...126, false): nudge(keyCode: event.keyCode, step: flags.contains(.shift) ? 10 : 1)
        default: super.keyDown(with: event)
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
            if dragStart == nil { drawHandles(for: selection) }
            drawSizeLabel(for: selection)
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
