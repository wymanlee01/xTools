import AppKit
import CoreImage
import Testing
@testable import FeatureOCR

struct TextRecognizerTests {
    /// 把文字画成白底黑字的图片（2 倍像素）
    func render(_ text: String) -> CGImage {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 28)])
        let size = attributed.size()
        let scale: CGFloat = 2
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: Int((size.width + 40) * scale), height: Int((size.height + 40) * scale),
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(at: CGPoint(x: 20, y: 20))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    @Test func 识别中英文文字() {
        let result = TextRecognizer.recognize(render("Hello xTools 你好世界"))
        guard case .lines(let lines) = result else { Issue.record("应该是文字结果"); return }
        let text = lines.joined()
        #expect(text.contains("Hello"))
        #expect(text.contains("你好"))
    }

    @Test func 有二维码时优先返回二维码内容() throws {
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.com".utf8)]))
        let output = try #require(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)))
        // 四周留白，方便识别
        let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -40, dy: -40)))
        let image = try #require(CIContext().createCGImage(padded, from: padded.extent))
        #expect(TextRecognizer.recognize(image) == .qrCodes(["https://example.com"]))
    }

    @Test func 取消换行() {
        #expect(TextRecognizer.joinLines("你好\n世界") == "你好世界")
        #expect(TextRecognizer.joinLines("hello\nworld") == "hello world")
        #expect(TextRecognizer.joinLines("第一行\n\nsecond") == "第一行second")
    }

    @Test func 强制英文符号() {
        #expect(TextRecognizer.englishSymbols("你好，世界！（测试）") == "你好,世界!(测试)")
    }
}
