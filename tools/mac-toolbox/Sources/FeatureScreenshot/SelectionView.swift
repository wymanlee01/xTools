import AppKit

/// 截图遮罩上的交互视图：显示冻结画面、压暗、框选、窗口识别
/// 操作：拖拽框选；单击选中光标下的窗口；拖动选区内部可移动
///      回车/双击 = 复制，⌘S = 保存，Esc/右键 = 取消
final class SelectionView: NSView {
    private let frozen: FrozenScreen
    /// 本屏内可识别的窗口（已转成本视图坐标，从前到后）
    private let windowRects: [CGRect]
    private weak var session: CaptureSession?

    private(set) var selection: CGRect?
    private var hoverWindow: CGRect?
    private var dragStart: CGPoint?
    private var moveOffset: CGPoint?

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
        guard selection == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoverWindow = windowRects.first { $0.contains(point) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, selection?.contains(point) == true {
            session?.finish(.copy)
            return
        }
        session?.willBeginSelection(in: self)
        if let selection, selection.contains(point) {
            // 在已有选区内按下：准备移动
            moveOffset = CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
        } else {
            dragStart = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let offset = moveOffset, var rect = selection {
            rect.origin = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
            selection = rect
        } else if let start = dragStart {
            selection = SelectionGeometry.rect(from: start, to: point)
            hoverWindow = nil
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; moveOffset = nil; needsDisplay = true }
        guard dragStart != nil else { return }
        // 拖动距离很小视为单击：选中光标下的窗口，没有窗口就选整屏
        if let rect = selection, rect.width > 3, rect.height > 3 { return }
        selection = hoverWindow ?? bounds
    }

    override func rightMouseDown(with event: NSEvent) {
        session?.finish(.cancel)
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let isCommand = event.modifierFlags.contains(.command)
        switch (event.keyCode, isCommand) {
        case (53, _): session?.finish(.cancel)                // Esc
        case (36, _), (76, _): session?.finish(.copy)         // 回车
        case (8, true): session?.finish(.copy)                // ⌘C
        case (1, true): session?.finish(.save)                // ⌘S
        default: super.keyDown(with: event)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.draw(frozen.image, in: bounds)

        // 选区以外压暗
        let highlight = selection ?? hoverWindow
        let mask = NSBezierPath(rect: bounds)
        if let highlight { mask.append(NSBezierPath(rect: highlight).reversed) }
        NSColor.black.withAlphaComponent(0.35).setFill()
        mask.fill()

        guard let highlight else { return }
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: -1, dy: -1))
        border.lineWidth = selection == nil ? 3 : 1.5
        border.stroke()

        if let selection { drawSizeLabel(for: selection) }
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
