using System.IO;
using Microsoft.Win32;

namespace XTools.Platform;

/// <summary>数据目录：%APPDATA%\xTools（对应 Mac 版 ~/Library/Application Support/xTools）</summary>
public static class AppPaths
{
    public static string DataDirectory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "xTools");

    public static string SettingsFile => Path.Combine(DataDirectory, "settings.json");
}

/// <summary>开机自启：写当前用户的注册表 Run 项（对应 Mac 版 SMAppService）</summary>
public static class AutoStart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "xTools";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(ValueName) is string;
        }
    }

    /// <summary>
    /// 安装版的 exe 在 %LOCALAPPDATA%\xTools\current\ 下，更新后路径不变，所以直接记当前 exe 路径
    /// </summary>
    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(ValueName, $"\"{Environment.ProcessPath}\"");
        else key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}
