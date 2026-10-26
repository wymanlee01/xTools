import AppKit

/// 设置窗口左侧菜单里的一页
public struct SettingsPageInfo {
    public let title: String
    /// 左侧菜单图标（SF Symbols）
    public let symbol: String
    /// 生成右侧 700×700 的页面
    public let makeView: @MainActor () -> NSView

    public init(title: String, symbol: String, makeView: @escaping @MainActor () -> NSView) {
        self.title = title
        self.symbol = symbol
        self.makeView = makeView
    }
}

/// 设置页容器：持有控件的事件对象（AppKit 控件不持有 target）
/// 坐标沿用 iShot 的界面里的数值（原点在左下）
@MainActor
public final class SettingsPageView: NSView {
    public static let size = CGSize(width: 700, height: 700)
    private var targets: [AnyObject] = []

    public init() {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 文字

    /// 分组标题，如“快捷键”“默认设置”
    @discardableResult
    public func addTitle(_ text: String, at frame: CGRect, in parent: NSView? = nil) -> NSTextField {
        addLabel(text, at: frame, font: .boldSystemFont(ofSize: 15), in: parent)
    }

    @discardableResult
    public func addLabel(_ text: String, at frame: CGRect, font: NSFont = .systemFont(ofSize: 13),
                         color: NSColor = .labelColor, alignment: NSTextAlignment = .left,
                         in parent: NSView? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.frame = frame
        (parent ?? self).addSubview(label)
        return label
    }

    /// 灰色小字说明，如“*仅对拖拽选取区域的截图有效”
    @discardableResult
    public func addNote(_ text: String, at frame: CGRect, in parent: NSView? = nil) -> NSTextField {
        addLabel(text, at: frame, font: .systemFont(ofSize: 11), color: .secondaryLabelColor, in: parent)
    }

    // MARK: - 容器

    /// 圆角分组框（对应 iShot 的 LCBox）
    @discardableResult
    public func addGroup(at frame: CGRect) -> NSView {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        box.contentViewMargins = .zero
        addSubview(box)
        return box.contentView ?? box
    }

    /// 横向分隔线
    public func addSeparator(at frame: CGRect, in parent: NSView? = nil) {
        let line = NSBox(frame: frame)
        line.boxType = .separator
        (parent ?? self).addSubview(line)
    }

    // MARK: - 控件

    @discardableResult
    public func addCheckbox(_ title: String, at frame: CGRect, isOn: Bool, in parent: NSView? = nil,
                            onChange: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.state = isOn ? .on : .off
        box.frame = frame
        bind(box) { onChange(($0 as? NSButton)?.state == .on) }
        (parent ?? self).addSubview(box)
        return box
    }

    /// 滑块；valueLabel 不为空时同步显示数值（如“15”“100”）
    @discardableResult
    public func addSlider(at frame: CGRect, range: ClosedRange<Double>, value: Double, valueLabel: NSTextField? = nil,
                          in parent: NSView? = nil, onChange: @escaping (Double) -> Void) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        slider.frame = frame
        slider.isContinuous = true
        valueLabel?.stringValue = Self.format(value)
        bind(slider) { control in
            let current = (control as? NSSlider)?.doubleValue ?? 0
            valueLabel?.stringValue = Self.format(current)
            onChange(current)
        }
        (parent ?? self).addSubview(slider)
        return slider
    }

    @discardableResult
    public func addPopup(_ items: [String], at frame: CGRect, selected: Int, disabled: Set<Int> = [],
                         in parent: NSView? = nil, onChange: @escaping (Int) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame, pullsDown: false)
        popup.addItems(withTitles: items)
        popup.autoenablesItems = false
        for index in disabled { popup.item(at: index)?.isEnabled = false }
        popup.selectItem(at: selected)
        bind(popup) { onChange(($0 as? NSPopUpButton)?.indexOfSelectedItem ?? 0) }
        (parent ?? self).addSubview(popup)
        return popup
    }

    @discardableResult
    public func addButton(_ title: String, at frame: CGRect, in parent: NSView? = nil,
                          onClick: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.frame = frame
        bind(button) { _ in onClick() }
        (parent ?? self).addSubview(button)
        return button
    }

    @discardableResult
    public func addColorWell(at frame: CGRect, color: NSColor, in parent: NSView? = nil,
                             onChange: @escaping (NSColor) -> Void) -> NSColorWell {
        let well = NSColorWell(frame: frame)
        well.color = color
        bind(well) { onChange(($0 as? NSColorWell)?.color ?? .black) }
        (parent ?? self).addSubview(well)
        return well
    }

    @discardableResult
    public func addHotkeyRecorder(at frame: CGRect, hotkey: Hotkey?, in parent: NSView? = nil,
                                  onChange: @escaping (Hotkey?) -> Void) -> HotkeyRecorderField {
        let field = HotkeyRecorderField(frame: frame, hotkey: hotkey)
        field.onChange = onChange
        (parent ?? self).addSubview(field)
        return field
    }

    /// 让控件的事件走闭包，并由页面持有事件对象
    public func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let target = ControlTarget(handler)
        control.target = target
        control.action = #selector(ControlTarget.fire(_:))
        targets.append(target)
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// 控件事件转闭包
private final class ControlTarget: NSObject {
    private let handler: (NSControl) -> Void

    init(_ handler: @escaping (NSControl) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ sender: NSControl) { handler(sender) }
}

/// 快捷键录制框（对应 iShot 的 SRRecorderControl，130×20）
/// 点击后按下组合键即可设置；Esc 取消；⌫ 清除
@MainActor
public final class HotkeyRecorderField: NSView {
    public var onChange: ((Hotkey?) -> Void)?
    private var hotkey: Hotkey?
    private var recording = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    public init(frame: CGRect, hotkey: Hotkey?) {
        self.hotkey = hotkey
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func mouseDown(with event: NSEvent) {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }
            switch Int(event.keyCode) {
            case 53:  // Esc：取消
                self.stopRecording()
            case 51, 117:  // ⌫ / ⌦：清除
                self.hotkey = nil
                self.onChange?(nil)
                self.stopRecording()
            default:
                let hotkey = Hotkey(keyCode: Int(event.keyCode), modifiers: event.modifierFlags)
                self.hotkey = hotkey
                self.onChange?(hotkey)
                self.stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = recording ? "请按快捷键…" : (hotkey?.displayName ?? "点击设置快捷键")
        let color: NSColor = recording || hotkey == nil ? .secondaryLabelColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}
