import AppKit

/// 贴图窗口：无边框、透明背景，层级 25（同 iShot），默认在所有桌面空间显示，可拖动背景移动
final class PinWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces]
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        // 系统阴影关掉，光晕画在图片四周的留边里（同 iShot）
        hasShadow = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
