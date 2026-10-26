import CoreGraphics

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
}
