import AppKit

/// 遮罩窗口：盖住整块屏幕，能成为 key window 才收得到键盘事件
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// 一次截图的完整过程：每块屏幕一个遮罩窗口，结束时统一关闭
@MainActor
final class CaptureSession {
    enum Result {
        case copy, save, cancel
        /// 复制取到的颜色文本（HEX 或 RGB）
        case copyColor(String)
    }

    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var activeView: SelectionView?
    private let onFinish: (Result, CGImage?) -> Void

    init(screens: [FrozenScreen], windows visible: [VisibleWindow], shortcuts: ToolShortcuts,
         onFinish: @escaping (Result, CGImage?) -> Void) {
        self.onFinish = onFinish
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        for frozen in screens {
            let frame = frozen.screen.frame
            let rects = visible.map {
                SelectionGeometry.viewRect(forGlobal: $0.frame, primaryScreenHeight: primaryHeight, screenFrame: frame)
            }
            let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            // 比菜单栏、Dock 高，但比弹出菜单低，工具栏里的下拉框菜单才不会被遮住
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            // 冻结画面放在底层图层里，SelectionView 叠在上面只画遮罩和标记
            let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
            container.wantsLayer = true
            container.layer?.contents = frozen.image
            container.layer?.contentsGravity = .resize
            let view = SelectionView(frozen: frozen, windowRects: rects, shortcuts: shortcuts, session: self)
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
            window.contentView = container
            windows.append(window)
            views.append(view)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        for window in windows { window.orderFrontRegardless() }
        // 光标所在屏幕的遮罩成为 key window，接收键盘
        let mouse = NSEvent.mouseLocation
        guard let target = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first else { return }
        target.makeKeyAndOrderFront(nil)
        target.makeFirstResponder(views.first { $0.window === target })
    }

    /// 某块屏幕开始框选：其他屏幕清空，选区只存在于一块屏幕
    func willBeginSelection(in view: SelectionView) {
        activeView = view
        for other in views where other !== view { other.clearSelection() }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    func finish(_ result: Result) {
        // 只有复制、保存需要裁出选区图片
        var image: CGImage?
        switch result {
        case .copy, .save: image = (activeView ?? views.first { $0.selection != nil })?.croppedImage()
        case .cancel, .copyColor: break
        }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        onFinish(result, image)
    }
}
