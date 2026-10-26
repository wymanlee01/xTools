using System.Windows;
using XTools.Core;

namespace XTools.Platform;

/// <summary>每个功能模块都实现这个接口，App 启动时统一注册（同 Mac 版 ToolModule）</summary>
public interface IToolModule
{
    /// <summary>唯一标识，如 “screenshot”，也用作设置项前缀</summary>
    string Id { get; }

    /// <summary>菜单和设置页里显示的名字</summary>
    string Title { get; }

    /// <summary>托盘菜单里的入口</summary>
    IEnumerable<ToolMenuItem> MenuItems();

    /// <summary>模块启用时调用：在这里注册快捷键、服务</summary>
    void Start(ToolContext context);

    /// <summary>模块关闭时调用：释放快捷键、窗口</summary>
    void Stop();

    /// <summary>设置窗口里属于本模块的页面（左侧菜单各一项）</summary>
    IEnumerable<SettingsPageInfo> SettingsPages() => [];

    /// <summary>设置被重置后重新读取（如重新注册快捷键）</summary>
    void ReloadSettings() { }
}

/// <summary>托盘菜单的一项：标题、显示在右侧的快捷键、点击后的动作</summary>
public sealed record ToolMenuItem(string Title, Hotkey? Hotkey, Action Run);

/// <summary>设置窗口左侧菜单的一项：标题、图标（Segoe Fluent Icons 字符）、页面内容</summary>
public sealed record SettingsPageInfo(string Title, string Glyph, Func<FrameworkElement> MakeContent);

/// <summary>底座提供给模块的公共能力，模块只通过它拿服务</summary>
public sealed record ToolContext(SettingsStore Settings, HotkeyCenter Hotkeys, ServiceRegistry Services);
