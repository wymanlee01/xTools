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
final class OverlayWindow: NSWindow {
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

    /// purpose 不为空时是“只框选”模式（OCR、录屏）：不显示标注工具栏，选区下方显示确认条
    init(screens: [FrozenScreen], windows visible: [VisibleWindow], shortcuts: ToolShortcuts, settings: ScreenshotSettings,
         purpose: CapturePurpose? = nil,
         onFinish: @escaping (Result, CaptureOutput?) -> Void) {
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
