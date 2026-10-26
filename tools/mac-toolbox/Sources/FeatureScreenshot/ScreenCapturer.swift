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
    static func captureAllScreens() async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [FrozenScreen] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
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
            // 层级 0~1000：普通窗口、浮动面板、Dock、菜单栏都能选中，桌面（负层级）除外
            // 排除自己的遮罩窗口和全透明窗口
            guard let layer = info[kCGWindowLayer as String] as? Int, (0...1000).contains(layer),
                  (info[kCGWindowOwnerPID as String] as? Int32) != myPid,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 20, bounds.height > 20 else { return nil }
            return VisibleWindow(frame: bounds, owner: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}

extension NSScreen {
    /// 屏幕对应的 CGDirectDisplayID，用来和 ScreenCaptureKit 的显示器对上
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
