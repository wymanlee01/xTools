import CryptoKit
import Foundation

/// 一条粘贴板历史
public struct ClipItem: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable {
        case text, image, files
    }

    public let id: UUID
    public var kind: Kind
    /// 纯文本（文字类）；图片类为空；文件类是文件名列表
    public var text: String
    /// 富文本数据文件名（RTF，存在 rtf 目录）
    public var rtfFile: String?
    /// 图片文件名（PNG，存在 images 目录）
    public var imageFile: String?
    /// 图片像素尺寸
    public var imageWidth: Int?
    public var imageHeight: Int?
    /// 文件路径
    public var filePaths: [String]
    /// 复制时的前台应用
    public var sourceBundleID: String?
    public var sourceName: String?
    /// xTools 自己写入时的模块（如 "screenshot"）
    public var origin: String?
    public var date: Date
    /// 收藏：不会被自动清理
    public var pinned: Bool
    /// 内容指纹，用来去重
    public var fingerprint: String

    public init(id: UUID = UUID(), kind: Kind, text: String = "", rtfFile: String? = nil, imageFile: String? = nil,
                imageWidth: Int? = nil, imageHeight: Int? = nil, filePaths: [String] = [], sourceBundleID: String? = nil,
                sourceName: String? = nil, origin: String? = nil, date: Date = Date(), pinned: Bool = false,
                fingerprint: String) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtfFile = rtfFile
        self.imageFile = imageFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.origin = origin
        self.date = date
        self.pinned = pinned
        self.fingerprint = fingerprint
    }

    /// 面板里显示的一行摘要
    public var summary: String {
        switch kind {
        case .text: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return "图片 \(imageWidth ?? 0)×\(imageHeight ?? 0)"
        case .files: return filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: "、")
        }
    }

    /// 是否匹配搜索词（文字内容、文件名、来源应用，不区分大小写）
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [text, filePaths.joined(separator: " "), sourceName ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// 内容指纹：种类 + 内容的 SHA256
    public static func fingerprint(kind: Kind, data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return kind.rawValue + ":" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// 面板上方的分类
public enum ClipFilter: Int, CaseIterable {
    case all, text, image, files, pinned

    public var title: String { ["全部", "文字", "图片", "文件", "收藏"][rawValue] }

    public func includes(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text
        case .image: return item.kind == .image
        case .files: return item.kind == .files
        case .pinned: return item.pinned
        }
    }
}
