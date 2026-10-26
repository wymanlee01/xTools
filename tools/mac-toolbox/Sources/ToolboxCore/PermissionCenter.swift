import AppKit
import ApplicationServices

/// 模块可能用到的系统权限
public enum Permission: String, CaseIterable, Sendable {
    /// 屏幕录制：截图需要
    case screenRecording
    /// 辅助功能：以后粘贴板“自动粘贴到当前应用”需要
    case accessibility

    public var displayName: String {
        switch self {
        case .screenRecording: return "屏幕录制"
        case .accessibility: return "辅助功能"
        }
    }

    /// 系统设置里对应页面的地址
    var settingsURL: URL {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

/// 统一检查和引导系统权限
@MainActor
public final class PermissionCenter {
    public init() {}

    public func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility: return AXIsProcessTrusted()
        }
    }

    /// 触发系统授权弹窗；已拒绝过则直接打开系统设置对应页面
    public func request(_ permission: Permission) {
        switch permission {
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings(permission) }
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { openSettings(permission) }
        }
    }

    public func openSettings(_ permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
