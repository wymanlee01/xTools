import CoreImage
import Vision

/// 文字识别，参数照 iShot（NSImage ocrFromImage: / analysisQRCode:）：
/// 先识别二维码，有就直接返回；否则用 Vision 精确识别，最小文字高度 0.001，
/// 语言：简体中文、繁体中文、英、法、意、德、西、葡，不做语言纠正
public enum TextRecognizer {
    public static let languages = ["zh-Hans", "zh-Hant", "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR"]

    /// 识别结果：二维码内容，或按行排列的文字
    public enum Result: Equatable {
        case qrCodes([String])
        case lines([String])

        public var text: String {
            switch self {
            case .qrCodes(let codes): return codes.joined(separator: "\n")
            case .lines(let lines): return lines.joined(separator: "\n")
            }
        }
    }

    public static func recognize(_ image: CGImage) -> Result {
        let codes = qrCodes(in: image)
        if !codes.isEmpty { return .qrCodes(codes) }
        return .lines(textLines(in: image))
    }

    static func qrCodes(in image: CGImage) -> [String] {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: CIImage(cgImage: image))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString } ?? []
    }

    static func textLines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.001
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        // Vision 按从上到下返回每一行，取每行最可信的候选
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    // MARK: - 结果窗口里的文字处理

    /// 取消换行：中文之间直接相连，英文单词之间用空格
    public static func joinLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.dropFirst().reduce(lines.first ?? "") { result, line in
            guard let last = result.last, let first = line.first else { return result + line }
            return result + (last.isASCII && first.isASCII ? " " : "") + line
        }
    }

    /// 强制英文符号：把中文标点换成英文标点
    public static func englishSymbols(_ text: String) -> String {
        let map: [Character: String] = [
            "，": ",", "。": ".", "：": ":", "；": ";", "！": "!", "？": "?", "（": "(", "）": ")",
            "【": "[", "】": "]", "「": "\"", "」": "\"", "“": "\"", "”": "\"", "‘": "'", "’": "'", "、": ",",
            "《": "<", "》": ">", "～": "~", "—": "-",
        ]
        return text.map { map[$0] ?? String($0) }.joined()
    }
}
