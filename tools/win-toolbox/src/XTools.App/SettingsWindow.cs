using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using XTools.Platform;

namespace XTools.App;

/// <summary>
/// 偏好设置窗口（同 Mac 版）：900×700，左侧 200 宽的菜单，右侧显示选中的页面。
/// 每个页面第一次打开时才创建，之后复用
/// </summary>
public sealed class SettingsWindow : Window
{
    private readonly Dictionary<SettingsPageInfo, FrameworkElement> _created = new();

    public SettingsWindow(IEnumerable<SettingsPageInfo> pages)
    {
        Title = "xTools 偏好设置";
        Width = 900;
        Height = 700;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var menu = new ListBox { BorderThickness = new Thickness(0), Padding = new Thickness(8) };
        foreach (var page in pages) menu.Items.Add(MenuItem(page));
        var content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        menu.SelectionChanged += (_, _) =>
        {
            if (menu.SelectedItem is not ListBoxItem { Tag: SettingsPageInfo page }) return;
            if (!_created.TryGetValue(page, out var element)) _created[page] = element = page.MakeContent();
            content.Content = element;
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(menu, 0);
        Grid.SetColumn(content, 1);
        grid.Children.Add(menu);
        grid.Children.Add(content);
        Content = grid;

        if (menu.Items.Count > 0) menu.SelectedIndex = 0;
    }

    /// <summary>左侧菜单的一项：图标 + 标题</summary>
    private static ListBoxItem MenuItem(SettingsPageInfo page)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 6, 4, 6) };
        row.Children.Add(new TextBlock
        {
            Text = page.Glyph,
            FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
            FontSize = 16,
            Width = 28,
            VerticalAlignment = VerticalAlignment.Center,
        });
        row.Children.Add(new TextBlock { Text = page.Title, FontSize = 14, VerticalAlignment = VerticalAlignment.Center });
        return new ListBoxItem { Content = row, Tag = page };
    }
}
