# win-toolbox

xTools 的 Windows 版：系统托盘工具箱，功能和 Mac 版（[mac-toolbox](../mac-toolbox/)）保持一致，用 C# 原生实现。

- 技术栈：C# + .NET 10 + WPF，托盘和对话框用 WinForms 的 `NotifyIcon` / `TaskDialog`，更新用 Velopack
- 系统要求：Windows 10 22H2 / Windows 11，x64
- 设计文档：[docs/win-toolbox-design.md](../../docs/win-toolbox-design.md)

## 构建与测试

需要 .NET 10 SDK。Mac 上可以编译全部项目、跑逻辑测试，但不能运行 Windows 程序。

```bash
dotnet build              # 编译全部项目
dotnet test               # 逻辑测试（XTools.Core）
dotnet publish src/XTools.App -c Release -r win-x64 --self-contained false -o publish
```

版本号和 Mac 版共用 `../mac-toolbox/VERSION`，发布时 CI 用 tag 的版本覆盖。

## 发布

和 Mac 版走同一个 tag：推 `v<版本号>` 后，`.github/workflows/release.yml` 的 `windows` 任务会打出 `xTools-win-Setup.exe` 和自动更新用的 `.nupkg`、`releases.win.json`，传到同一个 Release。
安装包不自带 .NET 运行时（约 16 MB），用户电脑上没有时由安装程序自动安装；没有代码签名，SmartScreen 会提示，点「更多信息 → 仍要运行」。

## 当前功能（W0 底座）

| 功能 | 说明 |
|---|---|
| 托盘图标 | 右键菜单：各模块入口（以后加）、偏好设置…、退出；双击打开偏好设置 |
| 单实例 | 已经在运行时再次打开 xTools，会直接打开偏好设置 |
| 偏好设置 | 900×700，左侧菜单；「通用」页：开机自启动、自动检查更新、检查更新、初始化 |
| 设置存储 | `%APPDATA%\xTools\settings.json`，键名和 Mac 版一致 |
| 全局快捷键 | `HotkeyCenter`，按模块注册和注销，被占用时报错 |
| 检查更新 | 每天启动时检查一次 GitHub Releases；发现新版本可安装并重启或跳过；直接运行编译产物（开发版）时不检查 |

## 目录

```
XTools.slnx
src/
├── XTools.Core/        # 纯逻辑（跨平台）：设置存储、快捷键模型、服务注册
├── XTools.Platform/    # Windows 封装：模块协议、设置页搭建、全局快捷键、开机自启、数据目录
└── XTools.App/         # 入口：托盘、偏好设置窗口、通用页、检查更新
tests/
└── XTools.Core.Tests/  # xUnit v3（Microsoft Testing Platform）
```

新增功能模块：建 `src/XTools.Feature.Xxx/`，实现 `IToolModule`，在 `XTools.App` 引用它并加到 `XToolsApp` 的模块列表。
功能模块之间不能互相引用，协作通过 `ServiceRegistry` 里的接口。
