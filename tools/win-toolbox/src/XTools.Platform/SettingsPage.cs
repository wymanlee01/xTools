using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace XTools.Platform;

/// <summary>
/// 设置页的简单搭建工具：从上往下依次加标题、勾选框、说明、按钮（对应 Mac 版 SettingsKit）。
/// 各模块的设置页都用它，保证样式一致
/// </summary>
public sealed class SettingsPage : StackPanel
{
    public SettingsPage()
    {
        Margin = new Thickness(32, 24, 32, 24);
    }

    /// <summary>分组标题</summary>
    public TextBlock AddTitle(string text)
    {
        var title = new TextBlock
        {
            Text = text,
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, Children.Count == 0 ? 0 : 20, 0, 8),
        };
        Children.Add(title);
        return title;
    }

    /// <summary>勾选框，改动时立即回调</summary>
    public CheckBox AddCheckbox(string text, bool isOn, Action<bool> onChange)
    {
        var box = new CheckBox { Content = text, IsChecked = isOn, Margin = new Thickness(0, 4, 0, 4) };
        box.Click += (_, _) => onChange(box.IsChecked == true);
        Children.Add(box);
        return box;
    }

    /// <summary>灰色小字说明</summary>
    public TextBlock AddNote(string text)
    {
        var note = new TextBlock
        {
            Text = text,
            FontSize = 12,
            Opacity = 0.65,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(22, 0, 0, 6),
        };
        Children.Add(note);
        return note;
    }

    /// <summary>按钮，靠左放</summary>
    public Button AddButton(string text, Action onClick)
    {
        var button = new Button
        {
            Content = text,
            MinWidth = 110,
            Padding = new Thickness(12, 4, 12, 4),
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(0, 6, 0, 6),
        };
        button.Click += (_, _) => onClick();
        Children.Add(button);
        return button;
    }

    /// <summary>分隔线</summary>
    public void AddSeparator()
    {
        Children.Add(new Border
        {
            Height = 1,
            Background = new SolidColorBrush(Color.FromArgb(0x30, 0x80, 0x80, 0x80)),
            Margin = new Thickness(0, 12, 0, 4),
        });
    }
}
