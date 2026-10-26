## Mac 安装

仅支持 Apple 芯片（M 系列）的 Mac，需要 macOS 14 或更新版本。

1. 下载下面的 `xTools-<版本>.dmg`，双击打开，把 **xTools** 拖进「应用程序」文件夹。
2. 第一次打开时 macOS 会提示「无法验证开发者」（xTools 用的是自签名证书，没有经过苹果公证）：
   打开「系统设置 → 隐私与安全性」，在下方找到 xTools，点「仍要打开」，再输入密码确认。
   也可以在终端运行 `xattr -dr com.apple.quarantine /Applications/xTools.app` 后再打开。
3. 按提示授予「屏幕录制」（截图、录屏需要）和「辅助功能」（自动粘贴需要）权限。

装好后可以在「偏好设置 → 通用」里检查更新，新版本会自动下载安装（`xTools-<版本>.zip` 就是给自动更新用的）。

## Windows 安装

支持 Windows 10 22H2 和 Windows 11（x64）。

1. 下载下面的 `xTools-win-Setup.exe` 并运行。电脑上没有 .NET 10 桌面运行时的话，安装程序会先自动下载安装。
2. 安装包没有代码签名，SmartScreen 会提示「Windows 已保护你的电脑」：点「更多信息 → 仍要运行」。
3. 装好后 xTools 在任务栏右下角的托盘里，右键打开菜单，双击打开偏好设置。

新版本会在「偏好设置 → 通用」里自动检查并安装（`.nupkg` 和 `releases.win.json` 是给 Windows 自动更新用的）。

