import AppKit
import ApplicationServices

/// 用辅助功能接口读写其他应用窗口的位置和大小（需要“辅助功能”权限）
/// 对外都用 Cocoa 坐标，和辅助功能坐标的换算在这里做
@MainActor
enum WindowMover {
    enum Failure: Error {
        case notTrusted
        case noWindow
        case fullScreen
    }

    /// 前台应用当前的窗口
    static func focusedWindow() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw Failure.notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw Failure.noWindow }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = value as! AXUIElement
                if bool(window, "AXFullScreen") { throw Failure.fullScreen }
                return window
            }
        }
        throw Failure.noWindow
    }

    /// 窗口当前位置（Cocoa 坐标）
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position: CGPoint = value(window, kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = value(window, kAXSizeAttribute, type: .cgSize) else { return nil }
        return WindowGeometry.fromAX(CGRect(origin: position, size: size), primaryHeight: primaryHeight)
    }

    /// 移动并缩放窗口（Cocoa 坐标）
    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        let target = WindowGeometry.toAX(frame, primaryHeight: primaryHeight)
        // Chrome、Electron 等应用开着“增强界面”时，改大小会带动画、位置会错，操作期间临时关掉
        let app = application(of: window)
        let enhanced = app.map { bool($0, "AXEnhancedUserInterface") } ?? false
        if enhanced, let app { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        // 先改大小再移动，最后再设一次大小：跨屏时有的应用会被旧屏幕的尺寸限制住
        set(window, kAXSizeAttribute, target.size)
        set(window, kAXPositionAttribute, target.origin)
        set(window, kAXSizeAttribute, target.size)
        if enhanced, let app { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    /// 主屏高度：辅助功能坐标以主屏左上角为原点
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    private static func application(of window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(raw as! AXValue, type, pointer) ? pointer.pointee : nil
    }

    private static func set(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
    }

    private static func set(_ element: AXUIElement, _ attribute: String, _ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
    }
}

/// 记住每个窗口分屏前的位置，“恢复”时回到原处
/// 同一个窗口连续分屏只记第一次的位置；恢复后删掉记录
@MainActor
final class RestoreMemory {
    private var entries: [(window: AXUIElement, frame: CGRect)] = []
    private let limit = 50

    func rememberIfNeeded(_ window: AXUIElement, frame: CGRect) {
        guard index(of: window) == nil else { return }
        entries.append((window, frame))
        if entries.count > limit { entries.removeFirst() }
    }

    /// 有没有记录（菜单里“还原”是否可用）
    func contains(_ window: AXUIElement) -> Bool { index(of: window) != nil }

    /// 取出并删掉记录
    func take(_ window: AXUIElement) -> CGRect? {
        guard let index = index(of: window) else { return nil }
        return entries.remove(at: index).frame
    }

    private func index(of window: AXUIElement) -> Int? {
        entries.firstIndex { CFEqual($0.window, window) }
    }
}
