# win-toolbox 设计方案

xTools 的 Windows 版。功能、交互、默认值和 Mac 版（[mac-toolbox-design.md](mac-toolbox-design.md)）保持一致，代码单独用 C# 写原生实现。

## 1. 目标与范围

| 阶段 | 内容 | 验收 |
|---|---|---|
| W0 | 底座：托盘图标、模块注册、设置存储、全局快捷键、偏好设置窗口框架；CI 编译和测试；Velopack 打包和自动更新；Mac 版更新包匹配规则收紧 | 推 tag 后 Release 里同时有 Mac 和 Windows 安装包，两边都能检查到更新（代码已完成，待发版验证） |
| W1 | 截图核心：冻结屏幕、遮罩、框选、窗口识别、调整手柄、放大镜和取色、复制和保存 | 多显示器、不同缩放比例下框选位置和截图像素都准确 |
| W2 | 标注工具栏：和 Mac 版同样的工具、样式栏、撤销重做、悬浮提示 | 布局、快捷键和 Mac 版一致 |
| W3 | 贴图：截图贴到屏幕、剪贴板贴图、缩放、透明度、光晕、右键菜单 | 交互数值和 Mac 版 `PinRules` 一致 |
| W4 | 粘贴板：历史、搜索、分类、收藏、预览、自动粘贴、贴到屏幕、隐私忽略、面板跟随鼠标 | 历史文件格式和 Mac 版相同 |
| W5 | OCR 和录屏 | 中英文识别；录制区域 MP4，可暂停 |

不做：Mac 版也没做的功能（翻译、长截图、贴图库等），等 Mac 版做了再跟进。

## 2. 技术选型

| 项 | 选择 | 理由 |
|---|---|---|
| 语言和运行时 | C# + .NET 10（LTS） | Windows 原生开发最成熟；能直接调用 Win32 和 WinRT |
| 界面 | WPF | 无边框置顶透明窗口、逐像素绘制都很成熟；WinUI 3 做全屏透明遮罩和不抢焦点的浮窗反而受限 |
| 托盘图标 | WinForms `NotifyIcon`（`UseWindowsForms`） | 系统自带，不加第三方依赖 |
| Win32 调用 | .NET 自带的 `LibraryImport` | 编译期生成调用代码，用到的函数不多，不引入 CsWin32 |
| WinRT 调用 | 目标框架 `net10.0-windows10.0.19041.0` | 直接用 Windows.Graphics.Capture、Windows.Media.Ocr |
| 二维码 | ZXing.Net | Windows 没有系统自带的二维码识别 |
| 打包和更新 | Velopack | 生成 `Setup.exe`，从 GitHub Releases 自动更新，支持增量包；程序运行时无法替换自己的 exe，由它的更新程序完成 |
| 测试 | xUnit | 逻辑库跨平台，在 Mac 上也能跑 |
| 系统要求 | Windows 10 22H2 / Windows 11，x64 | 覆盖绝大多数机器；arm64 以后需要再加 |
| 发布形式 | 不自带运行时，安装时由 Velopack 检查并自动安装 .NET 10 桌面运行时 | 实测安装包 16 MB、更新包 9 MB；自带运行时的话分别是 92 MB 和 85 MB |

## 3. 架构：和 Mac 版同样的“底座 + 功能模块”

```
XTools.App ──▶ XTools.Feature.* ──▶ XTools.Platform ──▶ XTools.Core
```

| 项目 | 目标框架 | 内容 |
|---|---|---|
| `XTools.Core` | `net10.0`（跨平台） | 纯逻辑：设置读写、快捷键模型、服务注册；以后加粘贴板历史存储和筛选、卡片样式识别、标注数据模型、贴图交互规则。Mac 上也能编译和测试 |
| `XTools.Platform` | `net10.0-windows…` | Windows 封装：模块协议 `IToolModule`（要用 WPF 类型）、设置页搭建工具、全局快捷键、开机自启、数据目录；以后加剪贴板监听、屏幕和窗口枚举、DPI 换算、截屏、模拟按键 |
| `XTools.Feature.Screenshot` / `Pin` / `Ocr` / `Record` / `Clipboard` | `net10.0-windows…` | 各功能模块，只引用 `Platform` 和 `Core` |
| `XTools.App` | `net10.0-windows…` | 入口：托盘菜单、注册模块、偏好设置窗口、更新提示 |
| `XTools.Core.Tests` | `net10.0` | 逻辑测试 |

- 和 Mac 版一样，**功能模块之间不能互相引用**，由项目引用关系在编译期保证；协作通过 `ServiceRegistry` 里的服务接口（`IPinService`、`ICaptureService`、`IOcrService`）。
- 代码放在 `tools/win-toolbox/`，解决方案文件 `XTools.slnx`。

## 4. macOS 能力对照

| 功能 | Mac 版 | Windows 版 | 注意 |
|---|---|---|---|
| 截屏（静态） | `SCScreenshotManager` | 每块屏用 GDI `BitBlt` 抓取 | 进程要声明 Per-Monitor V2 DPI 感知，否则高缩放屏上坐标和像素都会错 |
| 遮罩窗口 | 每屏一个 NSPanel | 每屏一个无边框、置顶、不进任务栏的 WPF 窗口 | 遮罩在全屏游戏或独占全屏程序上可能盖不住 |
| 窗口识别 | `CGWindowList` | `EnumWindows` + `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` | 要排除不可见、被遮挡（cloaked）的窗口和自身窗口 |
| 全局快捷键 | Carbon `RegisterEventHotKey` | `RegisterHotKey` | 被其他程序占用时注册失败，要提示 |
| 贴图窗口 | 无边框浮动 NSPanel + 光晕 | 分层透明窗口（`WS_EX_LAYERED`、`WS_EX_TOPMOST`、`WS_EX_TOOLWINDOW`） | 光晕用 WPF `DropShadowEffect` |
| OCR | Vision | `Windows.Media.Ocr` | 离线；识别中文需要系统装中文语言包，缺包时提示用户安装 |
| 二维码 | `CIDetector` | ZXing.Net | |
| 录屏 | `SCStream` + `AVAssetWriter` | Windows.Graphics.Capture + `MediaStreamSource` / `MediaTranscoder` 编码 MP4 | 风险最高的部分，放在最后做；Windows 10 上录制时窗口边缘会出现黄色边框 |
| 麦克风 | AVAudio | WinRT `AudioGraph` | |
| 剪贴板监听 | 轮询 `changeCount` | `AddClipboardFormatListener`（隐藏消息窗口收通知） | |
| 隐私跳过 | nspasteboard.org 的 Concealed / Transient 类型 | `ExcludeClipboardContentFromMonitorProcessing`、`CanIncludeInClipboardHistory = 0`、`Clipboard Viewer Ignore` 格式 | 密码管理器在 Windows 上用这些格式 |
| 来源应用 | `frontmostApplication` | 剪贴板变化时的前台窗口 → 进程 → exe 图标 | |
| 面板不抢焦点 | `.nonactivatingPanel` | `WS_EX_NOACTIVATE` | 不抢焦点时，搜索框打字需要单独处理 |
| 自动粘贴 | CGEvent ⌘V，需辅助功能权限 | `SendInput` Ctrl+V，不需要授权 | 以管理员身份运行的程序收不到普通程序发的按键（UIPI），要提示 |
| 系统权限 | 屏幕录制、辅助功能 | 基本不需要 | 设置页的“权限”分组改成说明 |
| 开机自启 | `SMAppService` | `HKCU\…\Run` 注册表项 | |
| 设置存储 | `UserDefaults` | `%APPDATA%\xTools\settings.json` | 键名和 Mac 版相同 |
| 粘贴板历史 | `~/Library/Application Support/xTools/clipboard/` | `%APPDATA%\xTools\clipboard\` | `items.json`、`images/`、`rtf/` 结构和 Mac 版相同 |

## 5. 和 Mac 版保持一致的地方

- **默认快捷键**：F1 截图、F3 贴剪贴板、⇧F3 隐藏 / 显示贴图、F4 OCR、F5 / ⇧F5 录屏 / 暂停、F6 粘贴板。F1 在很多 Windows 程序里是“帮助”，被全局快捷键占用后那些程序按 F1 就没反应了，设置页要能改。
- **托盘菜单**：区域截图、贴剪贴板到屏幕、粘贴板历史、偏好设置、检查权限 / 关于、退出，和 Mac 版精简后的菜单相同。
- **默认值和交互规则**：阴影、圆角、十字线默认不勾选、贴图缩放步长、粘贴板条数和天数等，都从 Mac 版对应的设置类搬过来，`XTools.Core` 里的测试用例也照着 Mac 版写。
- **数据格式**：设置键名、粘贴板 `items.json` 字段保持一致，以后做两端同步时直接对得上。

## 6. 发布和更新

**版本号**：Mac 和 Windows 共用一个版本号，同一个 `v*` tag 同时发两个平台。Windows 项目在打包时从 tag 取版本号。

**Actions**：发布工作流 `.github/workflows/release.yml` 里有两个任务，`windows` 任务在 `windows-latest` 上：

1. 在 Mac 任务建好 Release 之后运行（`needs`）。
2. `dotnet test` 跑逻辑测试 → `dotnet publish -r win-x64 --self-contained false` → `vpk pack --framework net10.0-x64-desktop --noPortable` 生成安装包。
3. 用 `gh release upload` 把文件传到同一个 Release。

**同一个 Release 里的附件**：

| 文件 | 给谁用 |
|---|---|
| `xTools-<版本>.dmg` | Mac 手动安装 |
| `xTools-<版本>.zip` | Mac 检查更新 |
| `xTools-win-Setup.exe` | Windows 手动安装 |
| `xTools-<版本>-full.nupkg`、`releases.win.json` 等 | Windows 检查更新（Velopack 自动读取） |

**Mac 版的更新包匹配**：`GitHubRelease.appArchive` 原来挑“名字里有 xTools 的 zip”，可能误选 Windows 的文件。W0 里改成精确匹配 `xTools-<版本>.zip` 并补了测试；另外 Windows 打包时加了 `--noPortable`，Release 里不会出现 Windows 的 zip，已安装的旧版 Mac 也不会选错。

**签名**：先不签名，用户第一次运行时 SmartScreen 会提示“已保护你的电脑”，点“更多信息 → 仍要运行”。以后需要时接入 Azure Trusted Signing（约每月 10 美元），在 Actions 里签名。

## 7. 开发和测试环境

- **Mac 上**：装 .NET SDK 后，可以编译和测试 `XTools.Core`。Windows 项目在 Mac 上开启 `EnableWindowsTargeting` 后也能编译，但不能运行。
- **CI**：`.github/workflows/win-toolbox-ci.yml`，改到 `tools/win-toolbox` 时在 `windows-latest` 上编译全部项目、跑测试。
- **手动试用**：截图、贴图、粘贴板这类交互必须在真实的 Windows 上试，在现有的 Windows 电脑上安装 Actions 产物或 Release 里的安装包。

## 8. 风险

| 风险 | 应对 |
|---|---|
| 多显示器、不同缩放比例下坐标错位 | W1 一开始就做 Per-Monitor V2 和坐标换算，并写测试 |
| 录屏编码复杂 | 放到最后；WinRT 编码做不好时再考虑带上 ffmpeg（注意许可证和体积） |
| 不能在本机运行，调试慢 | 尽量把逻辑放进 `XTools.Core` 在 Mac 上测；界面交互集中在 Windows 上一次试完 |
| 两套代码功能漂移 | 两边共用设计文档和默认值；新功能先写进文档再分别实现 |

## 9. 已确认

| 事项 | 决定 |
|---|---|
| 手动试用 | 用现有的 Windows 电脑，安装 Release 或 Actions 产物里的安装包试用 |
| 系统要求 | Windows 10 22H2 + Windows 11，只支持 x64 |
| Mac 本机 | 安装 .NET SDK，用来编译全部项目、跑逻辑测试 |
| 分支 | 继续在 `feat/mac-toolbox` 上开发，和 Mac 版共用发布流程 |
