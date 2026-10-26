import CoreGraphics

/// 选区的 8 个调整手柄
public enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// 手柄中心点（视图坐标，原点左下）
    public func center(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

/// 选区相关的纯计算，不依赖界面，方便测试
public enum SelectionGeometry {
    /// 由拖拽起点和当前点得到规范化矩形（宽高为正）
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// 视图坐标（点，原点左下）→ 图片像素坐标（原点左上），并裁到图片范围内
    public static func pixelRect(for rect: CGRect, viewHeight: CGFloat, scale: CGFloat,
                                 imageSize: CGSize) -> CGRect {
        let flipped = CGRect(x: rect.minX * scale,
                             y: (viewHeight - rect.maxY) * scale,
                             width: rect.width * scale,
                             height: rect.height * scale)
        return flipped.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// 全局窗口坐标（原点在主屏左上）→ 某块屏幕的视图坐标（原点在该屏左下）
    public static func viewRect(forGlobal windowRect: CGRect, primaryScreenHeight: CGFloat,
                                screenFrame: CGRect) -> CGRect {
        let cocoaY = primaryScreenHeight - windowRect.maxY
        return CGRect(x: windowRect.minX - screenFrame.minX, y: cocoaY - screenFrame.minY,
                      width: windowRect.width, height: windowRect.height)
    }

    /// 点中了哪个手柄；tolerance 是可点中的范围（点）
    public static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat = 6) -> ResizeHandle? {
        ResizeHandle.allCases.first { handle in
            let center = handle.center(in: rect)
            return abs(center.x - point.x) <= tolerance && abs(center.y - point.y) <= tolerance
        }
    }

    /// 拖动手柄后的新选区：被拖的边跟随鼠标，对边不动；拖过对边会自动翻转
    /// rect 传开始拖动时的选区，这样翻转后再拖回来也正确
    public static func resize(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .left, .topLeft, .bottomLeft: minX = point.x
        case .right, .topRight, .bottomRight: maxX = point.x
        case .top, .bottom: break
        }
        switch handle {
        case .bottom, .bottomLeft, .bottomRight: minY = point.y
        case .top, .topLeft, .topRight: maxY = point.y
        case .left, .right: break
        }
        return self.rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }

    /// 移动选区时不让它跑出屏幕
    public static func clamp(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        result.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return result
    }

    /// 把点限制在屏幕范围内
    public static func clamp(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
