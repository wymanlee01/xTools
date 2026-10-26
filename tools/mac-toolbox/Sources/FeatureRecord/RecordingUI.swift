import AppKit

/// 开始录制前的倒计时（同 iShot 的 CircleCounterView：半透明黑底、白色圆弧随时间缩短、HelveticaNeue-Bold 45 号数字）
@MainActor
final class CountdownWindow: NSPanel {
    private let counter = CountdownView(frame: CGRect(x: 0, y: 0, width: 150, height: 150))

    init(center: CGPoint) {
        super.init(contentRect: CGRect(x: center.x - 75, y: center.y - 75, width: 150, height: 150),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        contentView = counter
    }

    /// 倒数 seconds 秒后回调；0 秒直接回调
    func run(seconds: Int, completion: @escaping () -> Void) {
        guard seconds > 0 else { completion(); return }
        orderFrontRegardless()
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let remaining = Double(seconds) - Date().timeIntervalSince(start)
                if remaining <= 0 {
                    timer.invalidate()
                    self.orderOut(nil)
                    completion()
                } else {
                    self.counter.update(remaining: remaining, total: Double(seconds))
                }
            }
        }
    }
}

private final class CountdownView: NSView {
    private var remaining: Double = 3
    private var total: Double = 3

    func update(remaining: Double, total: Double) {
        self.remaining = remaining
        self.total = total
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.5).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        // 圆弧从顶部开始，按剩余时间比例画
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let arc = NSBezierPath()
        let fraction = remaining / total
        arc.appendArc(withCenter: center, radius: bounds.width / 2 - 20, startAngle: 90,
                      endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = 6
        NSColor.white.setStroke()
        arc.stroke()

        let text = "\(Int(remaining.rounded(.up)))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "HelveticaNeue-Bold", size: 45) ?? .boldSystemFont(ofSize: 45),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }
}

/// 录制中在区域四周画一圈边框（不会被录进去：录制时排除了 xTools 自己的窗口）
@MainActor
final class RecordingBorderWindow: NSPanel {
    init(frame: CGRect) {
        // 边框画在区域外面一圈
        super.init(contentRect: frame.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = BorderView()
    }

    var isPaused = false { didSet { contentView?.needsDisplay = true; (contentView as? BorderView)?.paused = isPaused } }
}

private final class BorderView: NSView {
    var paused = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 2
        if paused { path.setLineDash([6, 4], count: 2, phase: 0) }
        (paused ? NSColor.systemOrange : NSColor.systemRed).setStroke()
        path.stroke()
    }
}

/// 录制中的菜单栏计时：“● 00:12”，点开可暂停/继续、停止
@MainActor
final class RecordingStatusItem {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var elapsed: TimeInterval = 0
    private var lastTick = Date()
    private(set) var isPaused = false
    private let pauseItem = NSMenuItem(title: "暂停录制", action: nil, keyEquivalent: "")

    init(pauseTitle: String, stopTitle: String, onPause: @escaping () -> Void, onStop: @escaping () -> Void) {
        let menu = NSMenu()
        pauseItem.title = pauseTitle
        let pause = MenuAction(onPause)
        pauseItem.target = pause
        pauseItem.action = #selector(MenuAction.run)
        let stop = MenuAction(onStop)
        let stopItem = NSMenuItem(title: stopTitle, action: #selector(MenuAction.run), keyEquivalent: "")
        stopItem.target = stop
        menu.addItem(stopItem)
        menu.addItem(pauseItem)
        item.menu = menu
        actions = [pause, stop]
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private var actions: [MenuAction] = []

    func setPaused(_ paused: Bool, pauseTitle: String) {
        isPaused = paused
        pauseItem.title = pauseTitle
        refresh()
    }

    func remove() {
        timer?.invalidate()
        NSStatusBar.system.removeStatusItem(item)
    }

    private func tick() {
        let now = Date()
        if !isPaused { elapsed += now.timeIntervalSince(lastTick) }
        lastTick = now
        refresh()
    }

    private func refresh() {
        let seconds = Int(elapsed)
        let text = String(format: "%@ %02d:%02d", isPaused ? "❚❚" : "●", seconds / 60, seconds % 60)
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: isPaused ? NSColor.systemOrange : NSColor.systemRed,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
        ])
    }
}

/// 菜单项事件转闭包
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}
