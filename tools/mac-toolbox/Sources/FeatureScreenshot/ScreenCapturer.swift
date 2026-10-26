import AppKit
import ScreenCaptureKit

/// 某块屏幕在按下快捷键那一刻的“冻结”画面
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    /// 图片像素 / 屏幕点，Retina 一般是 2
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

/// 屏幕上可被识别的窗口（全局坐标，原点在主屏左上）
struct VisibleWindow {
    let frame: CGRect
    let owner: String
}

enum ScreenCapturer {
    /// 截取所有屏幕的完整画面
    @MainActor
    static func captureAllScreens(showsCursor: Bool = false) async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [FrozenScreen] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = showsCursor
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(FrozenScreen(screen: screen, image: image))
        }
        return result
    }

    /// 当前屏幕上的普通窗口，按从前到后排序（命中测试取第一个）
    static func visibleWindows() -> [VisibleWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPid = ProcessInfo.processInfo.processIdentifier

        return list.compactMap { info in
            // 排除自己的遮罩窗口
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPid,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            guard isSelectable(layer: info[kCGWindowLayer as String] as? Int ?? -1,
                               alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                               size: bounds.size, bundleID: bundleID) else { return nil }
            return VisibleWindow(frame: bounds, owner: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    /// 某个窗口能不能被窗口识别选中
    /// - 层级 0~1000：普通窗口、浮动面板、菜单栏都能选中，桌面（负层级）除外
    /// - 程序坞在主屏上铺了一个整屏大小的透明窗口，层级比普通窗口高，不排除的话光标在哪都只能选中整屏
    /// - 全透明、太小的窗口（比如某些工具放的 1×1 窗口）不选
    static func isSelectable(layer: Int, alpha: Double, size: CGSize, bundleID: String?) -> Bool {
        guard (0...1000).contains(layer), alpha > 0.05, size.width > 20, size.height > 20 else { return false }
        return bundleID != "com.apple.dock"
    }
}

extension NSScreen {
    /// 屏幕对应的 CGDirectDisplayID，用来和 ScreenCaptureKit 的显示器对上
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
