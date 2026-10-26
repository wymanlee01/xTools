import AppKit

/// 标注画布：盖在选区上，处理画图、选中移动、文字输入
/// 操作：按当前工具拖拽画图；点中已有元素可拖动移动；Delete 删除选中元素；
///      滚轮调选中元素的不透明度（步骤标注是改序号）
final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    let document = AnnotationDocument()
    private let renderer: AnnotationRenderer

    var tool: AnnotationTool = .rectangle { didSet { finishTextEditing(); selectedId = nil; needsDisplay = true } }
    /// 当前样式（来自工具栏）；改动时同时作用到选中的元素
    var style = AnnotationStyle() { didSet { applyStyleToSelection() } }
    /// 当前选中元素的样式，工具栏据此回显
    var selectedStyle: AnnotationStyle? {
        guard let id = selectedId else { return nil }
        return document.items.first { $0.id == id }?.style
    }
    /// 选中元素变化时通知工具栏
    var onSelectionChange: ((AnnotationStyle?) -> Void)?
    /// 撤销重做状态变化时通知工具栏刷新按钮
    var onChange: (() -> Void)?

    /// 正在画的元素（还没放进 document）
    private var drawing: Annotation?
    private var dragStart: CGPoint = .zero
    /// 选中的元素
    private var selectedId: UUID?
    /// 移动选中元素时上一次的鼠标位置；moved 表示是否已记过撤销点
    private var lastMovePoint: CGPoint?
    private var movedSinceMouseDown = false
    /// 文字输入框
    private var textField: NSTextField?

    init(frame: CGRect, baseImage: CGImage) {
        renderer = AnnotationRenderer(baseImage: baseImage, canvasSize: frame.size)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// 导出合成后的图片
    func renderedImage() -> CGImage? {
        finishTextEditing()
        return renderer.render(document.items)
    }

    func undo() { finishTextEditing(); document.undo(); selectedId = nil; changed() }
    func redo() { finishTextEditing(); document.redo(); selectedId = nil; changed() }

    func deleteSelection() {
        guard let id = selectedId else { return }
        document.remove(id: id)
        selectedId = nil
        changed()
    }

    private func changed() {
        needsDisplay = true
        onChange?()
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        finishTextEditing()

        // 点中已有元素：选中并准备移动
        if let hit = element(at: point) {
            selectedId = hit.id
            onSelectionChange?(hit.style)
            lastMovePoint = point
            movedSinceMouseDown = false
            needsDisplay = true
            return
        }
        if selectedId != nil { selectedId = nil; onSelectionChange?(nil) }
        dragStart = point

        switch tool {
        case .text:
            beginTextEditing(at: point)
        case .step:
            document.add(Annotation(shape: .step(number: document.nextStepNumber, center: point), style: style))
            changed()
        default:
            drawing = Annotation(shape: shape(for: tool, from: point, to: point), style: style)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), in: bounds)

        if let last = lastMovePoint, let id = selectedId, let item = document.items.first(where: { $0.id == id }) {
            if !movedSinceMouseDown { document.checkpoint(); movedSinceMouseDown = true }
            document.update(item.moved(by: point.x - last.x, point.y - last.y))
            lastMovePoint = point
            changed()
            return
        }
        guard var current = drawing else { return }
        if case .pencil(let points) = current.shape {
            current.shape = .pencil(points + [point])
        } else {
            current.shape = shape(for: tool, from: dragStart, to: point, shift: event.modifierFlags.contains(.shift))
        }
        drawing = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastMovePoint = nil
        defer { drawing = nil; needsDisplay = true }
        // 太小的元素视为误点，不保留
        guard let current = drawing, isMeaningful(current.shape) else { return }
        document.add(current)
        changed()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let id = selectedId, var item = document.items.first(where: { $0.id == id }),
              event.scrollingDeltaY != 0 else { return }
        document.checkpoint()
        let up = event.scrollingDeltaY > 0
        if case .step(let number, let center) = item.shape {
            item.shape = .step(number: max(1, number + (up ? 1 : -1)), center: center)
        } else {
            item.style.opacity = min(1, max(0.1, item.style.opacity + (up ? 0.1 : -0.1)))
        }
        document.update(item)
        changed()
    }

    /// 由拖拽起止点生成形状；按住 ⇧ 时矩形/椭圆变正方形/圆，直线/箭头锁 45° 角
    private func shape(for tool: AnnotationTool, from start: CGPoint, to end: CGPoint, shift: Bool = false) -> AnnotationShape {
        var end = end
        if shift { end = constrained(from: start, to: end, square: tool.isBoxShaped) }
        let box = SelectionGeometry.rect(from: start, to: end)
        switch tool {
        case .rectangle: return .rectangle(box)
        case .ellipse: return .ellipse(box)
        case .line: return .line(from: start, to: end)
        case .arrow: return .arrow(from: start, to: end)
        case .pencil: return .pencil([start])
        case .mosaic: return .mosaic(box)
        case .highlight: return .highlight(box)
        case .text: return .text("", origin: start)
        case .step: return .step(number: 1, center: start)
        }
    }

    private func constrained(from start: CGPoint, to end: CGPoint, square: Bool) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        // 锁定到最近的 45° 方向
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + length * cos(angle), y: start.y + length * sin(angle))
    }

    private func isMeaningful(_ shape: AnnotationShape) -> Bool {
        switch shape {
        case .rectangle(let r), .ellipse(let r), .mosaic(let r), .highlight(let r): return r.width > 3 && r.height > 3
        case .line(let a, let b), .arrow(let a, let b): return hypot(b.x - a.x, b.y - a.y) > 3
        case .pencil(let points): return points.count > 1
        case .text(let s, _): return !s.isEmpty
        case .step: return true
        }
    }

    /// 从最上层往下找点中的元素（用外接矩形判断，留 4 点余量）
    private func element(at point: CGPoint) -> Annotation? {
        document.items.last { AnnotationHitTest.bounds(of: $0).insetBy(dx: -4, dy: -4).contains(point) }
    }

    /// 改颜色、粗细时，同时作用到选中的元素
    private func applyStyleToSelection() {
        guard let id = selectedId, var item = document.items.first(where: { $0.id == id }), item.style != style else { return }
        document.checkpoint()
        item.style = style
        document.update(item)
        changed()
    }

    // MARK: - 文字输入

    private func beginTextEditing(at point: CGPoint) {
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 200, height: style.fontSize + 8))
        field.font = AnnotationRenderer.font(for: style, size: style.fontSize)
        field.textColor = NSColor(cgColor: style.color.cgColor()) ?? .red
        field.isBordered = true
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "输入文字，回车完成"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    /// 结束输入：有内容就生成文字元素
    private func finishTextEditing() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        let origin = CGPoint(x: field.frame.minX + 2, y: field.frame.minY + 4)
        field.removeFromSuperview()
        window?.makeFirstResponder(superview)
        guard !text.isEmpty else { return }
        document.add(Annotation(shape: .text(text, origin: origin), style: style))
        changed()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            finishTextEditing()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            textField?.stringValue = ""
            finishTextEditing()
            return true
        default:
            return false
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var items = document.items
        if let drawing { items.append(drawing) }
        renderer.draw(items, in: context)

        // 选中的元素画虚线框
        if let id = selectedId, let item = document.items.first(where: { $0.id == id }) {
            let frame = NSBezierPath(rect: AnnotationHitTest.bounds(of: item).insetBy(dx: -4, dy: -4))
            frame.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.white.setStroke()
            frame.stroke()
        }
    }
}

/// 元素的外接矩形，用于点选和画选中框
public enum AnnotationHitTest {
    public static func bounds(of item: Annotation) -> CGRect {
        let pad = item.style.lineWidth
        switch item.shape {
        case .rectangle(let r), .ellipse(let r), .mosaic(let r), .highlight(let r):
            return r
        case .line(let a, let b), .arrow(let a, let b):
            return SelectionGeometry.rect(from: a, to: b).insetBy(dx: -pad, dy: -pad)
        case .pencil(let points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -pad, dy: -pad)
        case .text(let string, let origin):
            let font = AnnotationRenderer.font(for: item.style, size: item.style.fontSize)
            let size = (string as NSString).size(withAttributes: [.font: font])
            return CGRect(origin: origin, size: size)
        case .step(_, let center):
            let r = item.style.stepRadius
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }
}
