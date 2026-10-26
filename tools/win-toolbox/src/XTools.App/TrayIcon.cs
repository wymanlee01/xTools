using System.Drawing;
using System.Windows.Forms;
using XTools.Platform;

namespace XTools.App;

/// <summary>
/// 托盘图标（对应 Mac 版菜单栏图标）：右键弹出菜单，每次打开时重建，快捷键改了也能显示最新的；双击打开偏好设置
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ContextMenuStrip _menu = new();
    private readonly Func<IEnumerable<ToolMenuItem>> _moduleItems;
    private readonly Action _openSettings;
    private readonly Action _quit;

    public TrayIcon(Func<IEnumerable<ToolMenuItem>> moduleItems, Action openSettings, Action quit)
    {
        _moduleItems = moduleItems;
        _openSettings = openSettings;
        _quit = quit;
        _menu.Opening += (_, e) =>
        {
            Rebuild();
            e.Cancel = false;
        };
        Rebuild();
        _icon = new NotifyIcon
        {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application,
            Text = "xTools",
            ContextMenuStrip = _menu,
            Visible = true,
        };
        _icon.DoubleClick += (_, _) => _openSettings();
    }

    private void Rebuild()
    {
        _menu.Items.Clear();
        var items = _moduleItems().ToList();
        foreach (var item in items)
        {
            _menu.Items.Add(new ToolStripMenuItem(item.Title, null, (_, _) => item.Run())
            {
                ShortcutKeyDisplayString = item.Hotkey?.DisplayName,
            });
        }
        // 没有模块菜单项时不加分隔线
        if (items.Count > 0) _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem("偏好设置…", null, (_, _) => _openSettings()));
        _menu.Items.Add(new ToolStripMenuItem("退出 xTools", null, (_, _) => _quit()));
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _menu.Dispose();
    }
}
