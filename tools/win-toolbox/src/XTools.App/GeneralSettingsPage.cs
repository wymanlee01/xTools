using System.Windows;
using XTools.Core;
using XTools.Platform;

namespace XTools.App;

/// <summary>“通用”设置页：开机自启动、检查更新、初始化（同 Mac 版通用页；Windows 不需要授权，没有“权限”分组）</summary>
public static class GeneralSettingsPage
{
    public static SettingsPageInfo Make(SettingsStore settings, UpdateController updater, Action onResetAll) =>
        new("通用", "", () =>
        {
            var page = new SettingsPage();

            page.AddTitle("启动");
            page.AddCheckbox("开机自启动", AutoStart.IsEnabled, enabled =>
            {
                try
                {
                    AutoStart.SetEnabled(enabled);
                }
                catch (Exception error)
                {
                    MessageBox.Show(error.Message, "设置开机自启动失败", MessageBoxButton.OK, MessageBoxImage.Warning);
                }
            });

            page.AddTitle("更新");
            page.AddCheckbox("自动检查更新", settings.GetBool(UpdateController.AutoCheckKey, true),
                enabled => settings.Set(UpdateController.AutoCheckKey, enabled));
            page.AddNote($"*当前版本 {updater.CurrentVersion}，每天启动时检查一次 GitHub 上的新版本");
            page.AddButton("检查更新", updater.CheckNow);

            page.AddTitle("初始化");
            page.AddNote("所有快捷键和偏好设置恢复成默认值");
            page.AddButton("初始化", () =>
            {
                var answer = MessageBox.Show("所有快捷键和偏好设置都会恢复成默认值。", "恢复全部默认设置？",
                    MessageBoxButton.OKCancel, MessageBoxImage.Question);
                if (answer == MessageBoxResult.OK) onResetAll();
            });
            return page;
        });
}
