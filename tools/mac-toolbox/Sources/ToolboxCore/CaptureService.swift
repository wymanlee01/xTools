import CoreGraphics

/// 框选的用途：决定选区下方显示什么按钮
public enum CapturePurpose {
    /// 识别文字（OCR 全局快捷键）
    case ocr
    /// 录屏选区
    case record
}

/// 框选的结果
public struct CaptureResult {
    /// 选区截图
    public let image: CGImage
    /// 选区在全局屏幕坐标里的位置（点，原点在主屏左下）
    public let frame: CGRect
    /// 图片像素 / 点
    public let scale: CGFloat
    /// 选区所在的显示器
    public let displayID: CGDirectDisplayID

    public init(image: CGImage, frame: CGRect, scale: CGFloat, displayID: CGDirectDisplayID) {
        self.image = image
        self.frame = frame
        self.scale = scale
        self.displayID = displayID
    }
}

/// 框选服务：由截图模块实现，OCR、录屏模块按协议调用
@MainActor
public protocol CaptureService: AnyObject {
    /// 让用户框选一个区域（不显示标注工具栏），确认后回调；取消时回调 nil
    func selectRegion(purpose: CapturePurpose, completion: @escaping (CaptureResult?) -> Void)
    /// 直接截取屏幕上的固定区域（OCR 固定区域模式）
    func captureRegion(_ frame: CGRect, completion: @escaping (CaptureResult?) -> Void)
}

/// 文字识别服务：由 OCR 模块实现，截图工具栏的 OCR 按钮按协议调用
@MainActor
public protocol OCRService: AnyObject {
    /// 识别图片里的文字（优先识别二维码），按设置弹出结果窗口或直接复制
    /// - frame: 选区位置，用于“固定区域模式”
    func recognize(image: CGImage, frame: CGRect?)
}
