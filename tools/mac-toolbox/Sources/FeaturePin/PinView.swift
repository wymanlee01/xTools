import AppKit

/// 贴图内容视图：显示图片（圆角 + 四周光晕，选中时蓝色）+ 鼠标移入时显示的控件
/// 控件布局取自 iShot（视图原点在左下，h 为高度）：
/// - 左上关闭按钮 20×20，位于 (8, h − 28)；右上帮助按钮 20×20
/// - 顶部居中透明度滑块 100×20，宽 ≥ 160 且高 ≥ 60 时才显示；下方一行“透明度”
/// - 底部居中缩放百分比，缩放时短暂显示
final class PinView: NSView {
    /// 事件交给 PinController 处理
    weak var controller: PinController?

    private let imageLayer = CALayer()
    private let closeButton = PinView.makeButton(symbol: "xmark.circle.fill", label: "关闭")
    private let helpButton = PinView.makeButton(symbol: "questionmark.circle.fill", label: "帮助")
    private let opacitySlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let opacityLabel = PinView.makeLabel()
    private let scaleLabel = PinView.makeLabel()
    private var hintTimer: Timer?
    private var hoverArea: NSTrackingArea?
    private var mouseInside = false

    /// image 是已经切好圆角、画好光晕的显示图
    init(frame: CGRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)

        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        helpButton.target = self
        helpButton.action = #selector(helpClicked)
        opacitySlider.controlSize = .small
        opacitySlider.target = self
        opacitySlider.action = #selector(sliderChanged)
        for view in [closeButton, helpButton, opacitySlider, opacityLabel, scaleLabel] as [NSView] {
            view.isHidden = true
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 拖动贴图任意位置都能移动窗口
    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func setImage(_ image: CGImage) {
        imageLayer.contents = image
    }

    func setOpacity(_ value: CGFloat) {
        imageLayer.opacity = Float(value)
        opacitySlider.doubleValue = Double(value * 100)
    }

    /// 缩放或调透明度时，在底部短暂显示提示（如“120%”“透明度 80%”）
    func showHint(_ text: String) {
        scaleLabel.stringValue = text
        scaleLabel.sizeToFit()
        needsLayout = true
        scaleLabel.isHidden = false
        hintTimer?.invalidate()
        hintTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.scaleLabel.isHidden = true }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()

        let w = bounds.width, h = bounds.height
        closeButton.frame = CGRect(x: 8, y: h - 28, width: 20, height: 20)
        helpButton.frame = CGRect(x: w - 28, y: h - 28, width: 20, height: 20)
        opacitySlider.frame = CGRect(x: w / 2 - 50, y: h - 28, width: 100, height: 20)
        opacityLabel.stringValue = "透明度"
        opacityLabel.sizeToFit()
        opacityLabel.frame.origin = CGPoint(x: w / 2 - opacityLabel.frame.width / 2, y: h - 48)
        scaleLabel.frame.origin = CGPoint(x: w / 2 - scaleLabel.frame.width / 2, y: 6)
        refreshControls()
    }

    // MARK: - 鼠标

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        refreshControls()
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        refreshControls()
    }

    /// 鼠标在贴图里才显示控件；滑块只在贴图够大时显示
    private func refreshControls() {
        let show = mouseInside && (controller?.showsControls ?? true)
        closeButton.isHidden = !show
        helpButton.isHidden = !show
        let roomy = bounds.width >= 160 && bounds.height >= 60
        opacitySlider.isHidden = !(show && roomy)
        opacityLabel.isHidden = !(show && roomy)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { controller?.close() }
    }

    override func scrollWheel(with event: NSEvent) {
        // 用像素级滚动量判断速度，和 iShot 一样分档
        let delta = Int(event.cgEvent?.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) ?? Double(event.scrollingDeltaY))
        guard event.scrollingDeltaY != 0 else { return }
        let direction = event.scrollingDeltaY > 0 ? 1 : -1
        if event.modifierFlags.contains(.option) {
            controller?.adjustOpacity(byPercent: direction * PinRules.opacityStep(forDelta: delta))
        } else {
            controller?.zoom(byPercent: direction * PinRules.zoomStep(forDelta: delta), anchor: convert(event.locationInWindow, from: nil))
        }
    }

    override func magnify(with event: NSEvent) {
        controller?.zoom(byPercent: Int(event.magnification * 100), anchor: convert(event.locationInWindow, from: nil))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.contextMenu()
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }

    // MARK: - 控件事件

    @objc private func closeClicked() { controller?.close() }
    @objc private func helpClicked() { controller?.showHelp() }

    @objc private func sliderChanged() {
        controller?.setOpacity(CGFloat(opacitySlider.doubleValue) / 100)
    }

    private static func makeButton(symbol: String, label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular).applying(.init(hierarchicalColor: .white)))
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.toolTip = label
        return button
    }

    /// 白字黑底小标签（iShot 用 12pt 字号，透明度 0.8）
    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.drawsBackground = true
        label.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        label.alphaValue = 0.8
        return label
    }
}
