import CoreGraphics

/// 分屏的位置计算，全是纯函数，方便测试
/// 坐标约定：除了 toAX / fromAX，都用 Cocoa 坐标（原点在主屏左下角，y 向上）
enum WindowGeometry {
    /// 某个分屏动作在可用区域里的目标位置；gap 是窗口之间、窗口和屏幕边缘的间距
    /// 居中、恢复、多屏移动不是固定区域，返回 nil
    static func frame(for action: WindowAction, in visible: CGRect, gap: CGFloat = 0) -> CGRect? {
        guard let r = action.region() else { return nil }
        // 先整体往里缩一圈 gap，再按比例切；切出来的内侧边各让出半个 gap，相邻窗口之间正好一个 gap
        let area = visible.insetBy(dx: gap, dy: gap)
        var minX = area.minX + area.width * r.x0, maxX = area.minX + area.width * r.x1
        var minY = area.minY + area.height * r.y0, maxY = area.minY + area.height * r.y1
        if r.x0 > 0 { minX += gap / 2 }
        if r.x1 < 1 { maxX -= gap / 2 }
        if r.y0 > 0 { minY += gap / 2 }
        if r.y1 < 1 { maxY -= gap / 2 }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    /// 大小不变（放不下就缩小），移到可用区域正中间
    static func centered(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    }

    /// 换到另一块屏幕：位置和大小按两块屏幕可用区域的比例换算，分好的屏在新屏幕上还是同样的布局
    static func moved(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        let sx = new.width / old.width, sy = new.height / old.height
        let moved = CGRect(x: new.minX + (frame.minX - old.minX) * sx, y: new.minY + (frame.minY - old.minY) * sy,
                           width: frame.width * sx, height: frame.height * sy)
        return clamped(moved, in: new).integral
    }

    /// 缩到能放下，并整个放进可用区域
    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var f = frame
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }

    /// 窗口大部分所在的屏幕（按可用区域重叠面积），一块都不重叠时返回 nil
    static func screenIndex(for frame: CGRect, in screens: [CGRect]) -> Int? {
        func overlap(_ screen: CGRect) -> CGFloat {
            let rect = screen.intersection(frame)
            return rect.isNull ? 0 : rect.width * rect.height
        }
        guard let best = screens.indices.max(by: { overlap(screens[$0]) < overlap(screens[$1]) }),
              overlap(screens[best]) > 0 else { return nil }
        return best
    }

    /// 下一块 / 上一块屏幕：按屏幕从左到右（同一列从上到下）排序后循环
    static func neighborIndex(of index: Int, in screens: [CGRect], forward: Bool) -> Int {
        let order = screens.indices.sorted {
            screens[$0].minX != screens[$1].minX ? screens[$0].minX < screens[$1].minX : screens[$0].maxY > screens[$1].maxY
        }
        guard let position = order.firstIndex(of: index) else { return index }
        let next = (position + (forward ? 1 : -1) + order.count) % order.count
        return order[next]
    }

    /// Cocoa 坐标 → 辅助功能接口的坐标（原点在主屏左上角，y 向下）
    static func toAX(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// 辅助功能接口的坐标 → Cocoa 坐标（换算是对称的）
    static func fromAX(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        toAX(frame, primaryHeight: primaryHeight)
    }
}
