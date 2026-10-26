import Foundation
import Security
import Testing
@testable import AppUpdater

struct VersionTests {
    @Test func 按段比较数字() throws {
        #expect(try #require(Version("v0.2.0")) > #require(Version("0.1.9")))
        #expect(try #require(Version("1.10")) > #require(Version("1.9.9")))
        #expect(try #require(Version("1.2")) == #require(Version("1.2.0")))
        #expect(Version("0.1.0")?.description == "0.1.0")
    }

    @Test func 不是版本号返回nil() {
        #expect(Version("") == nil)
        #expect(Version("latest") == nil)
        #expect(Version("1.2-beta") == nil)
    }
}

struct GitHubReleaseTests {
    let json = """
    {"tag_name": "v0.2.0", "name": "xTools 0.2.0", "body": "- 新增检查更新",
     "html_url": "https://github.com/wymanlee01/xTools/releases/tag/v0.2.0",
     "assets": [
       {"name": "source.tar.gz", "size": 10, "browser_download_url": "https://example.com/source.tar.gz"},
       {"name": "xTools-0.2.0.zip", "size": 2048, "browser_download_url": "https://example.com/xTools-0.2.0.zip"}
     ]}
    """

    @Test func 解析版本和安装包() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.version?.description == "0.2.0")
        #expect(release.notes == "- 新增检查更新")
        #expect(release.appArchive?.name == "xTools-0.2.0.zip")
    }
}

struct UpdateInstallerTests {
    /// 在临时目录造一个最小的 .app 并用 ditto 打成 zip（和 release.sh 一样带外层文件夹）
    func makeZip(bundleID: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("updater-tests-\(UUID().uuidString)")
        let app = folder.appendingPathComponent("xTools.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "xTools", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        let zip = folder.appendingPathComponent("xTools-9.9.9.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.appendingPathComponent("xTools.app").path, zip.path]
        try process.run()
        process.waitUntilExit()
        return zip
    }

    func requirement() throws -> SecRequirement {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString("identifier \"io.github.wymanlee01.xtools\" and anchor apple generic" as CFString,
                                                    [], &requirement)
        #expect(status == errSecSuccess)
        return try #require(requirement)
    }

    @Test func 解压出app() throws {
        let app = try UpdateInstaller.extractApp(from: makeZip(bundleID: "io.github.wymanlee01.xtools"))
        #expect(app.lastPathComponent == "xTools.app")
    }

    @Test func bundle不对或没签名时拒绝安装() throws {
        let other = try UpdateInstaller.extractApp(from: makeZip(bundleID: "com.example.other"))
        #expect(throws: UpdateError.self) { try UpdateInstaller.verify(other, bundleID: "io.github.wymanlee01.xtools", requirement: requirement()) }
        let unsigned = try UpdateInstaller.extractApp(from: makeZip(bundleID: "io.github.wymanlee01.xtools"))
        #expect(throws: UpdateError.self) { try UpdateInstaller.verify(unsigned, bundleID: "io.github.wymanlee01.xtools", requirement: requirement()) }
    }
}
