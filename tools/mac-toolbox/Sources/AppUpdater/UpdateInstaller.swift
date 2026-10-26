import Foundation
import Security

/// 下载并安装新版本：下载 zip → 解压 → 校验签名 → 替换当前 app → 退出后重新打开
/// 签名校验用当前 app 自己的“指定要求”（同一个证书 + 同一个 bundle id），
/// 所以只有用同一张证书签名的 xTools 才能装上，别人换掉安装包也装不进来
public enum UpdateInstaller {
    /// 下载安装包到临时目录，返回 zip 路径
    public static func download(_ asset: GitHubRelease.Asset, session: URLSession = .shared) async throws -> URL {
        let (temp, response) = try await session.download(from: asset.downloadURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.badResponse(code) }
        let zip = try makeWorkDirectory().appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temp, to: zip)
        return zip
    }

    /// 用系统的 ditto 解压，返回里面的 .app（在顶层或者一层文件夹里）
    public static func extractApp(from zip: URL) throws -> URL {
        let folder = zip.deletingLastPathComponent().appendingPathComponent("unzipped")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        let manager = FileManager.default
        let top = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        if let app = top.first(where: { $0.pathExtension == "app" }) { return app }
        for sub in top where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let inner = (try? manager.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? []
            if let app = inner.first(where: { $0.pathExtension == "app" }) { return app }
        }
        throw UpdateError.noAppInArchive
    }

    /// 当前 app 的签名要求；临时签名（没有证书）时没法用来校验新版本
    public static func currentRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              (info as? [String: Any])?[kSecCodeInfoCertificates as String] != nil,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateError.unsignedCurrentApp }
        return requirement
    }

    /// 校验新 app：bundle id 一致，签名完整且满足当前 app 的签名要求
    public static func verify(_ app: URL, bundleID: String, requirement: SecRequirement) throws {
        let newID = Bundle(url: app)?.bundleIdentifier ?? "未知"
        guard newID == bundleID else { throw UpdateError.wrongApp(newID) }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.badSignature("读不到签名")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "错误码 \(status)"
            throw UpdateError.badSignature(reason)
        }
    }

    /// 用新 app 替换当前 app（运行中的 app 可以直接替换，退出后再打开就是新版本）
    public static func replace(_ current: URL, with newApp: URL) throws {
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateError.notWritable(parent.path) }
        _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
    }

    /// 等当前进程退出后重新打开 app（调用后由调用方退出 app）
    public static func relaunchAfterExit(_ app: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$1\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "relaunch", app.path]
        try process.run()
    }

    private static func makeWorkDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xTools-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.noAppInArchive }
    }
}
