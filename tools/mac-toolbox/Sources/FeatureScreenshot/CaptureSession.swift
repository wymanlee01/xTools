import AppKit

/// 遮罩窗口：盖住整块屏幕，能成为 key window 才收得到键盘事件
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// 一次截图的完整过程：每块屏幕一个遮罩窗口，结束时统一关闭
@MainActor
final class CaptureSession {
    enum Result { case copy, save, cancel }

    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var activeView: SelectionView?
    private let onFinish: (Result, CGImage?) -> Void

    init(screens: [FrozenScreen], windows visible: [VisibleWindow], onFinish: @escaping (Result, CGImage?) -> Void) {
        self.onFinish = onFinish
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        for frozen in screens {
            let frame = frozen.screen.frame
            let rects = visible.map {
                SelectionGeometry.viewRect(forGlobal: $0.frame, primaryScreenHeight: primaryHeight, screenFrame: frame)
            }
            let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            let view = SelectionView(frozen: frozen, windowRects: rects, session: self)
            window.contentView = view
            windows.append(window)
            views.append(view)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        for window in windows { window.orderFrontRegardless() }
        // 光标所在屏幕的遮罩成为 key window，接收键盘
        let mouse = NSEvent.mouseLocation
        let target = windows.first { $0.frame.contains(mouse) } ?? windows.first
        target?.makeKeyAndOrderFront(nil)
        target?.makeFirstResponder(target?.contentView)
    }

    /// 某块屏幕开始框选：其他屏幕清空，选区只存在于一块屏幕
    func willBeginSelection(in view: SelectionView) {
        activeView = view
        for other in views where other !== view { other.clearSelection() }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    func finish(_ result: Result) {
        let image = result == .cancel ? nil : (activeView ?? views.first { $0.selection != nil })?.croppedImage()
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        onFinish(result, image)
    }
}
