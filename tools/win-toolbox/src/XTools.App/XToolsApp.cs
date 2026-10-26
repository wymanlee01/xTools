using System.Windows;
using XTools.Core;
using XTools.Platform;

namespace XTools.App;

/// <summary>组装底座和各功能模块，生成托盘菜单和偏好设置窗口（同 Mac 版 AppDelegate）</summary>
public sealed class XToolsApp(SingleInstance instance) : Application
{
    /// <summary>新增功能模块只需加到这里</summary>
    private readonly List<IToolModule> _modules = [];

    private ToolContext? _context;
    private TrayIcon? _tray;
    private UpdateController? _updater;
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // 没有主窗口，只有托盘图标；退出只能从托盘菜单
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
#pragma warning disable WPF0001 // 跟随系统的浅色 / 深色 Fluent 样式（.NET 9 起提供，仍标记为实验）
        ThemeMode = ThemeMode.System;
#pragma warning restore WPF0001

        var settings = new SettingsStore(AppPaths.SettingsFile);
        _context = new ToolContext(settings, new HotkeyCenter(), new ServiceRegistry());
        foreach (var module in _modules) module.Start(_context);

        _updater = new UpdateController(settings);
        _tray = new TrayIcon(() => _modules.SelectMany(m => m.MenuItems()), OpenSettings, Shutdown);
        instance.ListenForActivation(() => Dispatcher.Invoke(OpenSettings));
        _updater.CheckOnLaunch();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        foreach (var module in _modules) module.Stop();
        _tray?.Dispose();
        _context?.Hotkeys.Dispose();
        base.OnExit(e);
    }

    private void OpenSettings()
    {
        if (_context is null || _updater is null) return;
        if (_settingsWindow is null || !_settingsWindow.IsLoaded)
        {
            var general = GeneralSettingsPage.Make(_context.Settings, _updater, ResetAllSettings);
            _settingsWindow = new SettingsWindow(_modules.SelectMany(m => m.SettingsPages()).Append(general));
        }
        _settingsWindow.Show();
        if (_settingsWindow.WindowState == WindowState.Minimized) _settingsWindow.WindowState = WindowState.Normal;
        _settingsWindow.Activate();
    }

    /// <summary>初始化：清空全部设置，各模块重新读取（如重新注册快捷键）</summary>
    private void ResetAllSettings()
    {
        if (_context is null) return;
        _context.Settings.Reset();
        foreach (var module in _modules) module.ReloadSettings();
        _settingsWindow?.Close();
        _settingsWindow = null;
        OpenSettings();
    }
}
