import AppKit

/// 统一写剪贴板，并打上来源标记
/// 以后粘贴板模块据此识别“来自截图”的内容，避免重复记录
@MainActor
public final class PasteboardService {
    /// 自定义类型：记录是哪个模块写入的
    public static let sourceType = NSPasteboard.PasteboardType("io.github.wymanlee01.xtools.source")

    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// 写入图片（PNG），source 一般传模块 id
    @discardableResult
    public func write(image: CGImage, source: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        pasteboard.setString(source, forType: Self.sourceType)
        return true
    }

    /// 写入纯文本，如取色得到的 "#1E90FF"
    public func write(string: String, source: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        pasteboard.setString(source, forType: Self.sourceType)
    }

    /// 读出当前内容的来源模块；不是本应用写入的返回 nil
    public func currentSource() -> String? {
        pasteboard.string(forType: Self.sourceType)
    }
}
