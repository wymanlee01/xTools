using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;
using Velopack;
using Velopack.Sources;
using XTools.Core;

namespace XTools.App;

/// <summary>
/// 检查更新（同 Mac 版 UpdateController）：启动时每天自动检查一次；设置页可手动检查。
/// 下载、替换、重启都交给 Velopack：它从 GitHub Releases 读 releases.win.json，
/// 和 Mac 版的 dmg / zip 放在同一个 Release 里互不影响
/// </summary>
public sealed class UpdateController
{
    public const string AutoCheckKey = "general.autoCheckUpdates";
    private const string LastCheckKey = "general.lastUpdateCheck";
    private const string SkippedKey = "general.skippedUpdateVersion";
    private const string RepoUrl = "https://github.com/wymanlee01/xTools";

    private readonly SettingsStore _settings;
    private readonly UpdateManager _manager = new(new GithubSource(RepoUrl, accessToken: null, prerelease: false));
    private bool _busy;

    public UpdateController(SettingsStore settings)
    {
        _settings = settings;
    }

    /// <summary>安装版用 Velopack 记录的版本；直接运行编译产物时用程序集版本并标明“开发版”</summary>
    public string CurrentVersion => _manager.IsInstalled
        ? _manager.CurrentVersion!.ToString()
        : $"{Assembly.GetExecutingAssembly().GetName().Version?.ToString(3)}（开发版）";

    /// <summary>启动时调用：开着自动检查、距上次检查超过一天才查；没有新版本或出错都不打扰</summary>
    public void CheckOnLaunch()
    {
        if (!_settings.GetBool(AutoCheckKey, true) || !_manager.IsInstalled) return;
        var last = _settings.GetDouble(LastCheckKey, 0);
        if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() - last < 24 * 3600) return;
        _ = CheckAsync(userInitiated: false);
    }

    /// <summary>设置页“检查更新”按钮</summary>
    public void CheckNow() => _ = CheckAsync(userInitiated: true);

    private async Task CheckAsync(bool userInitiated)
    {
        if (_busy) return;
        if (!_manager.IsInstalled)
        {
            if (userInitiated) Show("不能自动更新", "当前不是通过安装包安装的开发版，请从 GitHub Releases 下载安装。", TaskDialogIcon.Information);
            return;
        }
        _busy = true;
        try
        {
            var update = await _manager.CheckForUpdatesAsync();
            _settings.Set(LastCheckKey, (double)DateTimeOffset.UtcNow.ToUnixTimeSeconds());
            if (update is null)
            {
                if (userInitiated) Show("已是最新版本", $"当前版本 {CurrentVersion}", TaskDialogIcon.Information);
                return;
            }
            var version = update.TargetFullRelease.Version.ToString();
            // 自动检查时，用户跳过的版本不再提醒
            if (!userInitiated && _settings.GetString(SkippedKey, "") == version) return;
            if (AskToInstall(version, update.TargetFullRelease.NotesMarkdown)) await InstallAsync(update);
        }
        catch (Exception error)
        {
            if (userInitiated) ShowFailure("检查更新失败", error);
        }
        finally
        {
            _busy = false;
        }
    }

    /// <summary>发现新版本的弹窗：安装并重启 / 以后再说 / 跳过这个版本</summary>
    private bool AskToInstall(string version, string? notes)
    {
        var install = new TaskDialogButton("安装并重启");
        var later = new TaskDialogButton("以后再说");
        var skip = new TaskDialogButton("跳过这个版本");
        notes = notes?.Trim() ?? "";
        var page = new TaskDialogPage
        {
            Caption = "xTools",
            Heading = $"发现新版本 xTools {version}",
            Text = $"当前版本 {CurrentVersion}" + (notes.Length == 0 ? "" : "\n\n" + notes[..Math.Min(notes.Length, 800)]),
            Icon = TaskDialogIcon.Information,
            Buttons = { install, later, skip },
            DefaultButton = install,
        };
        var result = TaskDialog.ShowDialog(page);
        if (result == skip) _settings.Set(SkippedKey, version);
        return result == install;
    }

    /// <summary>下载新版本，退出后由 Velopack 替换并重新打开</summary>
    private async Task InstallAsync(UpdateInfo update)
    {
        try
        {
            await _manager.DownloadUpdatesAsync(update);
            _manager.ApplyUpdatesAndRestart(update);
        }
        catch (Exception error)
        {
            ShowFailure("安装更新失败", error);
        }
    }

    private static void Show(string heading, string text, TaskDialogIcon icon) =>
        TaskDialog.ShowDialog(new TaskDialogPage { Caption = "xTools", Heading = heading, Text = text, Icon = icon });

    /// <summary>出错时提示原因，并提供打开下载页手动安装</summary>
    private static void ShowFailure(string heading, Exception error)
    {
        var open = new TaskDialogButton("打开下载页");
        var page = new TaskDialogPage
        {
            Caption = "xTools",
            Heading = heading,
            Text = error.Message,
            Icon = TaskDialogIcon.Warning,
            Buttons = { open, TaskDialogButton.Close },
        };
        if (TaskDialog.ShowDialog(page) == open)
            Process.Start(new ProcessStartInfo($"{RepoUrl}/releases/latest") { UseShellExecute = true });
    }
}
