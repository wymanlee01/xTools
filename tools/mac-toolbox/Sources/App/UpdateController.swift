import AppKit
import AppUpdater
import ToolboxCore

/// 检查更新的界面部分：启动时每天自动检查一次；设置页可手动检查
/// 发现新版本弹窗：安装并重启 / 以后再说 / 跳过这个版本
@MainActor
final class UpdateController {
    static let autoCheckKey = "general.autoCheckUpdates"
    private static let lastCheckKey = "general.lastUpdateCheck"
    private static let skippedKey = "general.skippedUpdateVersion"

    private let settings: SettingsStore
    private var busy = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// GitHub 仓库（owner/repo），打包时写进 Info.plist 的 XToolsUpdateRepo
    private var repo: String? { Bundle.main.object(forInfoDictionaryKey: "XToolsUpdateRepo") as? String }

    var currentVersion: Version {
        Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? Version("0")!
    }

    /// 启动时调用：开着自动检查、距上次检查超过一天才查；没有新版本或出错都不打扰
    func checkOnLaunch() {
        guard settings.bool(Self.autoCheckKey, default: true) else { return }
        let last = settings.double(Self.lastCheckKey, default: 0)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    /// 设置页“检查更新”按钮
    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !busy else { return }
        guard let repo else {
            if userInitiated { showAlert("没有配置更新地址", "打包时没有写入 GitHub 仓库。") }
            return
        }
        busy = true
        defer { busy = false }
        if userInitiated { HUD.show("正在检查更新…") }
        do {
            let release = try await UpdateChecker.newerRelease(than: currentVersion, repo: repo)
            settings.set(Date().timeIntervalSince1970, for: Self.lastCheckKey)
            guard let release, let version = release.version else {
                if userInitiated { showAlert("已是最新版本", "当前版本 \(currentVersion)") }
                return
            }
            // 自动检查时，用户跳过的版本不再提醒
            if !userInitiated, settings.string(Self.skippedKey, default: "") == version.description { return }
            if await askToInstall(release, version: version) { await install(release, version: version) }
        } catch {
            if userInitiated { showAlert("检查更新失败", error.localizedDescription) }
        }
    }

    /// 发现新版本的弹窗，返回是否要安装
    private func askToInstall(_ release: GitHubRelease, version: Version) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "发现新版本 xTools \(version)"
        let notes = (release.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = "当前版本 \(currentVersion)" + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(800)))
        alert.addButton(withTitle: "安装并重启")
        alert.addButton(withTitle: "以后再说")
        alert.addButton(withTitle: "跳过这个版本")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertThirdButtonReturn: settings.set(version.description, for: Self.skippedKey); return false
        default: return false
        }
    }

    /// 下载 → 解压 → 校验签名 → 替换当前 app → 退出并重新打开
    private func install(_ release: GitHubRelease, version: Version) async {
        do {
            guard let asset = release.appArchive else { throw UpdateError.noArchive }
            // 先确认当前 app 能用来校验，再下载
            let requirement = try UpdateInstaller.currentRequirement()
            HUD.show("正在下载 xTools \(version)…")
            let zip = try await UpdateInstaller.download(asset)
            let newApp = try UpdateInstaller.extractApp(from: zip)
            try UpdateInstaller.verify(newApp, bundleID: Bundle.main.bundleIdentifier ?? "", requirement: requirement)
            let current = Bundle.main.bundleURL
            try UpdateInstaller.replace(current, with: newApp)
            try UpdateInstaller.relaunchAfterExit(current)
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "安装更新失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "打开下载页")
            alert.addButton(withTitle: "关闭")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
