import AppKit

/// 贴图窗口：无边框、透明背景，层级 25（同 iShot），默认在所有桌面空间显示，可拖动背景移动
final class PinWindow: NSWindow {
    /// allSpaces：在所有桌面空间显示；设置里“固定在单个桌面上”时为 false
    init(frame: CGRect, allSpaces: Bool = true) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = allSpaces ? [.canJoinAllSpaces] : []
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        // 系统阴影关掉，光晕画在图片四周的留边里（同 iShot）
        hasShadow = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
