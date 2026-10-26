import CoreGraphics

/// 贴图交互的数值规则，参考 iShot 的实际效果
public enum PinRules {
    /// 最大缩放比例（%）
    public static let maxScale = 800
    /// 缩放后最小尺寸（点）
    public static let minSize = CGSize(width: 60, height: 30)

    /// 光晕：图片四周留边 6 点、模糊 9 点、不偏移（iShot 按 6 × 倍率留边、1.5 倍模糊）
    public static let glowPadding: CGFloat = 6
    public static let glowBlur: CGFloat = 9
    /// 选中（当前窗口）的贴图：蓝色光晕 (0, 0.51, 0.84)，和 iShot 一样用设备色彩空间
    public static let activeGlow = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0, 0.51, 0.84, 1])!
    /// 未选中的贴图：50% 黑色阴影
    public static let inactiveGlow = CGColor(gray: 0, alpha: 0.5)

    /// 截图贴回原位时，窗口要比选区四周各大一圈留边，图片才正好落在原位置
    public static func windowFrame(forContent content: CGRect) -> CGRect {
        content.insetBy(dx: -glowPadding, dy: -glowPadding)
    }

    /// 滚轮缩放步长（百分点）：滚得越快步长越大
    public static func zoomStep(forDelta delta: Int) -> Int {
        switch abs(delta) {
        case ..<6: return 1
        case ..<10: return 5
        case ..<20: return 10
        case ..<50: return 20
        default: return 30
        }
    }

    /// ⌥ + 滚轮调透明度的步长（百分点）
    public static func opacityStep(forDelta delta: Int) -> Int {
        switch abs(delta) {
        case ..<6: return 1
        case ..<10: return 2
        case ..<30: return 5
        case ..<80: return 10
        default: return 30
        }
    }

    /// 限制缩放比例：不超过最大值，且缩放后宽不小于 60、高不小于 30
    public static func clampScale(_ scale: Int, baseSize: CGSize) -> Int {
        var result = min(scale, maxScale)
        if baseSize.width > 0 { result = max(result, Int((minSize.width / baseSize.width * 100).rounded(.up))) }
        if baseSize.height > 0 { result = max(result, Int((minSize.height / baseSize.height * 100).rounded(.up))) }
        return result
    }

    /// 初始缩放：图片超过屏幕 90% 时缩小到能放下，否则 100%
    public static func initialScale(imageSize: CGSize, screenSize: CGSize) -> Int {
        let fit = min(screenSize.width * 0.9 / imageSize.width, screenSize.height * 0.9 / imageSize.height)
        return fit < 1 ? max(1, Int(fit * 100)) : 100
    }

    /// 透明度限制在 10%~100%
    public static func clampOpacity(_ value: CGFloat) -> CGFloat {
        min(1, max(0.1, value))
    }
}
