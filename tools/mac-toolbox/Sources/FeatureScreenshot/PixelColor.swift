import CoreGraphics

/// 取色结果，统一换算到 sRGB（网页、设计稿用的都是 sRGB）
public struct PixelColor: Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// 读取图片某个像素的颜色（像素坐标，原点左上）；越界返回 nil
    public static func read(from image: CGImage, x: Int, y: Int) -> PixelColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // 画进 1×1 的 sRGB 画布，顺便完成色彩空间换算
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? PixelColor(red: bytes[0], green: bytes[1], blue: bytes[2]) : nil
    }
}
