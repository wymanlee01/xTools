import Foundation

/// GitHub Releases 接口返回的一个发布版本（只取用得到的字段）
public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let size: Int
        public let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case downloadURL = "browser_download_url"
        }
    }

    public let tag: String
    public let title: String?
    public let notes: String?
    public let pageURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case title = "name"
        case notes = "body"
        case pageURL = "html_url"
        case assets
    }

    /// tag 里的版本号（“v0.2.0” → 0.2.0）
    public var version: Version? { Version(tag) }

    /// 安装包：名字正好是 xTools-<版本>.zip（release.sh 生成）
    public var appArchive: Asset? {
        guard let version else { return nil }
        let name = "xTools-\(version).zip"
        return assets.first { $0.name == name }
    }
}

public enum UpdateError: LocalizedError {
    case noRelease
    case badResponse(Int)
    case noArchive
    case noAppInArchive
    case wrongApp(String)
    case badSignature(String)
    case notWritable(String)
    case unsignedCurrentApp

    public var errorDescription: String? {
        switch self {
        case .noRelease: return "还没有发布过版本，或仓库不是公开的。"
        case .badResponse(let code): return "GitHub 返回了错误（HTTP \(code)），请稍后再试。"
        case .noArchive: return "这个版本没有附带 xTools 的 zip 安装包。"
        case .noAppInArchive: return "安装包里没有找到 xTools.app。"
        case .wrongApp(let id): return "安装包里的应用不是 xTools（\(id)）。"
        case .badSignature(let reason): return "安装包签名校验失败：\(reason)"
        case .notWritable(let path): return "没有权限替换 \(path)，请手动下载安装。"
        case .unsignedCurrentApp: return "当前 xTools 是临时签名，没法确认新版本的来源，请手动下载安装。"
        }
    }
}

/// 检查 GitHub 上的最新版本（公开仓库不需要登录）
public enum UpdateChecker {
    /// 取 owner/repo 的最新正式版（草稿和预发布不算）
    public static func latestRelease(repo: String, session: URLSession = .shared) async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("xTools-updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw UpdateError.noRelease }
        guard code == 200 else { throw UpdateError.badResponse(code) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// 比当前版本新才返回
    public static func newerRelease(than current: Version, repo: String) async throws -> GitHubRelease? {
        let release = try await latestRelease(repo: repo)
        guard let version = release.version, version > current else { return nil }
        return release
    }
}
