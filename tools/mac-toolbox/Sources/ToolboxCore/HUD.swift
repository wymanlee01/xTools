import AppKit

/// 屏幕中央短暂显示的提示
@MainActor
public enum HUD {
    public static func show(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 40, height: 44)
        let screen = NSScreen.main?.frame ?? .zero
        let panel = NSPanel(contentRect: CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        label.frame.origin = CGPoint(x: 20, y: (size.height - label.frame.height) / 2)
        background.addSubview(label)
        panel.contentView = background
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { panel.orderOut(nil) }
    }
}
