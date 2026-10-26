import CoreGraphics
import Foundation

/// 标注工具；rawValue 是数字快捷键（和 iShot 一致：1 矩形 … 9 高亮）
public enum AnnotationTool: Int, CaseIterable {
    case rectangle = 1, ellipse, line, arrow, pencil, mosaic, text, step, highlight

    public var title: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .pencil: return "画笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        case .step: return "步骤标注"
        case .highlight: return "高亮"
        }
    }

    /// 拖出一个矩形范围来画的工具
    var isBoxShaped: Bool { [.rectangle, .ellipse, .mosaic, .highlight].contains(self) }
}

/// 颜色（sRGB 分量），和界面无关，方便测试和导出
public struct AnnotationColor: Equatable {
    public var red, green, blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 5 个预设颜色，取值来自 iShot 的界面：红、粉、蓝、黄、绿（第 6 格是自定义颜色）
    public static let presets: [AnnotationColor] = [
        AnnotationColor(red: 1, green: 0, blue: 0),
        AnnotationColor(red: 0.927, green: 0.408, blue: 0.588),
        AnnotationColor(red: 0.295, green: 0.655, blue: 0.827),
        AnnotationColor(red: 0.973, green: 0.821, blue: 0.412),
        AnnotationColor(red: 0.283, green: 0.631, blue: 0.314),
    ]

    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 文字、步骤标注的背景（选项来自 iShot：无 / 底色 / 描边）
public enum TextBackground: Int, CaseIterable {
    case none, fill, stroke

    public var title: String { ["无", "底色", "描边"][rawValue] }
}

/// 画笔模式（选项来自 iShot：单一颜色 / 高斯模糊 / 马赛克）
public enum PencilMode: Int, CaseIterable {
    case color, blur, mosaic

    public var title: String { ["单一颜色", "高斯模糊", "马赛克"][rawValue] }
}

/// 文字背景可选的 9 种颜色（iShot 里是 9 个色块，具体色值没存在原版界面里，这里自定）
public let textBackgroundColors: [AnnotationColor] = [
    AnnotationColor(red: 1, green: 1, blue: 1),
    AnnotationColor(red: 0, green: 0, blue: 0),
    AnnotationColor(red: 1, green: 0, blue: 0),
    AnnotationColor(red: 1, green: 0.58, blue: 0),
    AnnotationColor(red: 0.973, green: 0.821, blue: 0.412),
    AnnotationColor(red: 0.283, green: 0.631, blue: 0.314),
    AnnotationColor(red: 0.295, green: 0.655, blue: 0.827),
    AnnotationColor(red: 0.6, green: 0.35, blue: 0.85),
    AnnotationColor(red: 0.5, green: 0.5, blue: 0.5),
]

/// 一个元素的样式；对应工具栏第二行的“大小、不透明度、颜色”和各工具的专属选项
public struct AnnotationStyle: Equatable {
    public var color = AnnotationColor.presets[0]
    /// “大小”滑块 1~100，不同工具换算成各自的尺寸
    public var size: CGFloat = 20
    /// “不透明度”滑块 0.1~1
    public var opacity: CGFloat = 1
    /// 矩形、椭圆：实心
    public var filled = false
    /// 矩形：圆角
    public var rounded = false
    /// 高亮：椭圆（否则圆角矩形）
    public var highlightOval = false
    /// 马赛克：毛玻璃（否则像素化）
    public var mosaicBlur = false
    /// 文字、步骤标注：背景方式和背景颜色
    public var textBackground = TextBackground.none
    public var textBackgroundColor = textBackgroundColors[0]
    /// 文字、步骤标注：字体，nil 为系统默认
    public var fontName: String?
    /// 画笔：单一颜色 / 高斯模糊 / 马赛克
    public var pencilMode = PencilMode.color

    public init() {}

    public var lineWidth: CGFloat { 1 + size * 0.15 }
    public var fontSize: CGFloat { 10 + size * 0.4 }
    public var stepRadius: CGFloat { 8 + size * 0.2 }
    /// 马赛克块大小 / 毛玻璃模糊半径（点）
    public var mosaicBlock: CGFloat { 4 + size * 0.2 }
}

/// 一个标注元素的形状数据（坐标都是选区内的点坐标，原点左下）
public enum AnnotationShape: Equatable {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case line(from: CGPoint, to: CGPoint)
    case arrow(from: CGPoint, to: CGPoint)
    case pencil([CGPoint])
    case mosaic(CGRect)
    /// origin 是文字左下角
    case text(String, origin: CGPoint)
    case step(number: Int, center: CGPoint)
    /// 聚光灯：选区内除这些区域外都压暗
    case highlight(CGRect)
}

/// 一个标注元素
public struct Annotation: Equatable, Identifiable {
    public let id: UUID
    public var shape: AnnotationShape
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle = AnnotationStyle()) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    /// 平移整个元素
    public func moved(by dx: CGFloat, _ dy: CGFloat) -> Annotation {
        func shift(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        func shift(_ r: CGRect) -> CGRect { r.offsetBy(dx: dx, dy: dy) }
        var copy = self
        switch shape {
        case .rectangle(let r): copy.shape = .rectangle(shift(r))
        case .ellipse(let r): copy.shape = .ellipse(shift(r))
        case .line(let a, let b): copy.shape = .line(from: shift(a), to: shift(b))
        case .arrow(let a, let b): copy.shape = .arrow(from: shift(a), to: shift(b))
        case .pencil(let points): copy.shape = .pencil(points.map(shift))
        case .mosaic(let r): copy.shape = .mosaic(shift(r))
        case .text(let s, let o): copy.shape = .text(s, origin: shift(o))
        case .step(let n, let c): copy.shape = .step(number: n, center: shift(c))
        case .highlight(let r): copy.shape = .highlight(shift(r))
        }
        return copy
    }
}

/// 标注列表 + 撤销重做（每次改动前存一份快照）
public final class AnnotationDocument {
    public private(set) var items: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// 下一个步骤标注的序号
    public var nextStepNumber: Int {
        let numbers = items.compactMap { item -> Int? in
            if case .step(let n, _) = item.shape { return n }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    public func add(_ item: Annotation) {
        checkpoint()
        items.append(item)
    }

    public func remove(id: UUID) {
        checkpoint()
        items.removeAll { $0.id == id }
    }

    /// 记一个撤销点。连续修改（如拖动移动）只在开始时调用一次，之后用 update 实时改
    public func checkpoint() {
        undoStack.append(items)
        redoStack.removeAll()
    }

    /// 修改元素，不单独记撤销点
    public func update(_ item: Annotation) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
    }
}
