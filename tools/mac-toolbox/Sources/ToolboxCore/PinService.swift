import CoreGraphics

/// 贴图服务：由贴图模块实现并注册到 ServiceRegistry
/// 截图模块、以后的粘贴板模块都按这个协议调用，不直接依赖贴图模块
@MainActor
public protocol PinService: AnyObject {
    /// 把图片贴到屏幕上
    /// - frame: 贴图位置（全局坐标，原点在主屏左下，单位点）；nil 表示放在鼠标所在屏幕中央
    /// - scale: 图片像素 / 点，Retina 截图一般是 2
    func pin(image: CGImage, frame: CGRect?, scale: CGFloat)
}
