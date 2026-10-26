import AppKit

/// 菜单里每个分屏动作前面的示意图标：灰色圆角矩形代表屏幕，亮色部分是窗口要去的位置
/// 用绘制回调画，颜色在显示时按菜单的深浅色取，不用图片文件
@MainActor
enum WindowMenuIcon {
    static let size = CGSize(width: 22, height: 15)

    static func image(for action: WindowAction) -> NSImage {
        NSImage(size: size, flipped: false) { bounds in
            let screen = bounds.insetBy(dx: 1, dy: 1.5)
            NSColor.labelColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3).fill()
            NSColor.labelColor.withAlphaComponent(0.9).setFill()
            let inner = screen.insetBy(dx: 1.5, dy: 1.5)
            switch action {
            case .nextDisplay, .previousDisplay:
                arrow(in: inner.insetBy(dx: 2, dy: 1), pointingRight: action == .nextDisplay).fill()
            case .center:
                block(CGRect(x: inner.midX - inner.width * 0.25, y: inner.midY - inner.height * 0.25,
                             width: inner.width * 0.5, height: inner.height * 0.5))
            case .restore:
                // 小一号的窗口，表示回到原来的大小
                block(CGRect(x: inner.minX + 1, y: inner.midY, width: inner.width * 0.45, height: inner.height * 0.45))
            default:
                // 亮色区域贴满屏幕对应的那一部分，按屏幕外框的圆角裁掉
                if let r = action.region() {
                    let rect = CGRect(x: screen.minX + screen.width * r.x0, y: screen.minY + screen.height * r.y0,
                                      width: screen.width * (r.x1 - r.x0), height: screen.height * (r.y1 - r.y0))
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3).addClip()
                    rect.fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            return true
        }
    }

    private static func block(_ rect: CGRect) {
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    /// 五边形箭头：表示移到旁边的显示器
    private static func arrow(in rect: CGRect, pointingRight: Bool) -> NSBezierPath {
        let tip = rect.width * 0.35
        let path = NSBezierPath()
        if pointingRight {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX - tip, y: rect.maxY))
            path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.line(to: CGPoint(x: rect.minX + tip, y: rect.minY))
            path.line(to: CGPoint(x: rect.minX, y: rect.midY))
            path.line(to: CGPoint(x: rect.minX + tip, y: rect.maxY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.close()
        return path
    }
}
