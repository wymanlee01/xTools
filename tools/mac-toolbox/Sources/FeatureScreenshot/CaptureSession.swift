import AppKit
import ToolboxCore

/// 一次截图的产出
struct CaptureOutput {
    let image: CGImage
    /// 选区在全局屏幕坐标里的位置（点）
    let frame: CGRect?
    /// 图片像素 / 点
    let scale: CGFloat
    /// 选区所在的显示器（录屏要用）
    let displayID: CGDirectDisplayID
}

/// 遮罩窗口：盖住整块屏幕，能成为 key window 才收得到键盘事件
/// 用不激活应用的浮动面板：不切换前台应用也能直接收键盘（和粘贴板面板一样），
/// 原来前台的窗口外观（标题栏、阴影）不会变，按下截图时画面不闪不抖
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 一次截图的完整过程：每块屏幕一个遮罩窗口，结束时统一关闭
@MainActor
final class CaptureSession {
    enum Result: Equatable {
        case copy, save, cancel
        /// 贴到屏幕上（放在选区原来的位置）
        case pin
        /// 保存至本地和剪切板（双击动作）
        case saveAndCopy
        /// 保存后用设置里的 App 打开（双击修饰键）
        case saveAndOpen
        /// 识别文字（工具栏 OCR 按钮 / O 键 / 双击动作）
        case ocr
        /// 只框选模式下确认选区（OCR 全局快捷键、录屏）
        case confirm
        /// 复制取到的颜色文本（HEX 或 RGB）
        case copyColor(String)
    }

    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var activeView: SelectionView?
    private let onFinish: (Result, CaptureOutput?) -> Void
    /// 按键兜底监听（截图结束时移除）
    private var keyMonitors: [Any] = []

    /// purpose 不为空时是“只框选”模式（OCR、录屏）：不显示标注工具栏，选区下方显示确认条
    init(screens: [FrozenScreen], windows visible: [VisibleWindow], shortcuts: ToolShortcuts, settings: ScreenshotSettings,
         purpose: CapturePurpose? = nil,
         onFinish: @escaping (Result, CaptureOutput?) -> Void) {
        self.onFinish = onFinish
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        for frozen in screens {
            let frame = frozen.screen.frame
            // 窗口超出本屏的部分裁掉，完全不在本屏的去掉
            let screenBounds = CGRect(origin: .zero, size: frame.size)
            let rects = visible.map {
                SelectionGeometry.viewRect(forGlobal: $0.frame, primaryScreenHeight: primaryHeight, screenFrame: frame)
                    .intersection(screenBounds)
            }.filter { !$0.isEmpty }
            let window = OverlayWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            // 面板默认在应用失去前台时隐藏、只在需要时才成为 key，遮罩都不要
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            // 关掉面板默认的出现 / 消失动画，冻结画面要一下子盖上，不能有缩放、淡入
            window.animationBehavior = .none
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
            let view = SelectionView(frozen: frozen, windowRects: rects, shortcuts: shortcuts, settings: settings, purpose: purpose,
                                     session: self)
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
            window.contentView = container
            windows.append(window)
            views.append(view)
        }
    }

    func show() {
        // 不调用 NSApp.activate()：切前台会让原来的窗口先变成未激活外观再被遮罩盖住，看起来就是画面抖一下
        for window in windows { window.orderFrontRegardless() }
        installKeyMonitors()
        // 光标所在屏幕的遮罩成为 key window，接收键盘
        let mouse = NSEvent.mouseLocation
        guard let target = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first else { return }
        let view = views.first { $0.window === target }
        target.makeKeyAndOrderFront(nil)
        target.makeFirstResponder(view)
        // 不用等鼠标动一下，遮罩一出来就高亮光标下的窗口
        view?.hover(atScreenPoint: mouse)
        // 从托盘菜单点进来时，菜单收起会把键盘焦点交给它留下的 ViewBridge 窗口，下一轮再抢回来一次
        DispatchQueue.main.async { [weak self] in
            guard let self, self.windows.contains(where: { $0 === target }) else { return }
            target.makeKeyAndOrderFront(nil)
            target.makeFirstResponder(view)
        }
    }

    /// 某块屏幕开始框选：其他屏幕清空，选区只存在于一块屏幕
    func willBeginSelection(in view: SelectionView) {
        activeView = view
        for other in views where other !== view { other.clearSelection() }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    /// 兜底：键盘焦点不在遮罩上时（落在 xTools 别的窗口里，或被其他应用拿走），按 Esc 也能退出截图。
    /// 焦点在遮罩上时不拦截，由 SelectionView 自己处理（比如正在编辑文字标注）
    private func installKeyMonitors() {
        // 按键送到了 xTools 别的窗口（比如刚隐藏的粘贴板面板还占着键盘），直接转给截图界面处理，
        // Esc、回车、⌘C 等照常可用；送到遮罩上的按键不拦，由遮罩自己处理（比如正在编辑文字标注）
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, !self.windows.contains(where: { $0 === event.window }),
                  let view = self.activeView ?? self.views.first(where: { $0.window?.isKeyWindow == true }) ?? self.views.first
            else { return event }
            view.keyDown(with: event)
            return nil
        }) { keyMonitors.append(local) }
        // 全局监听只收得到发给其他应用的按键（需要辅助功能权限，没有时不生效），只处理 Esc
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.finish(.cancel) }
        }) { keyMonitors.append(global) }
    }

    func finish(_ result: Result) {
        // 兜底监听和截图界面可能同时触发，只结束一次
        guard !windows.isEmpty else { return }
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
        // 复制、保存、贴图需要裁出选区图片；贴图还要记下选区在屏幕上的位置
        var output: CaptureOutput?
        let view = activeView ?? views.first { $0.selection != nil }
        switch result {
        case .copy, .save, .pin, .saveAndCopy, .saveAndOpen, .ocr, .confirm:
            if let view, let image = view.croppedImage() {
                output = CaptureOutput(image: image, frame: view.selectionOnScreen, scale: view.pixelScale,
                                       displayID: view.displayID)
            }
        case .cancel, .copyColor:
            break
        }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        onFinish(result, output)
    }
}
