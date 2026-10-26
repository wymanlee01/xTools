import AppKit
import ToolboxCore

/// 只框选模式（OCR、录屏）下选区旁边的确认条：确认按钮 + 取消按钮，深色底和标注工具栏一致
final class SelectionConfirmBar: NSView {
    static let size = CGSize(width: 190, height: 40)

    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    init(purpose: CapturePurpose) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .darkAqua)
        let (title, symbol) = purpose == .ocr ? ("识别文字", "text.viewfinder") : ("开始录制", "record.circle")
        let confirm = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(),
                               target: self, action: #selector(confirmClicked))
        confirm.bezelStyle = .rounded
        confirm.keyEquivalent = "\r"
        confirm.frame = CGRect(x: 8, y: 6, width: 120, height: 28)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: 132, y: 6, width: 50, height: 28)
        addSubview(confirm)
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 点在空白处不往下传，避免被当成重新框选
    override func mouseDown(with event: NSEvent) {}

    @objc private func confirmClicked() { onConfirm?() }
    @objc private func cancelClicked() { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1).setFill()
        path.fill()
        NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1).setStroke()
        path.stroke()
    }
}
