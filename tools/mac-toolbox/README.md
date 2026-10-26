# mac-toolbox

macOS 菜单栏工具箱（应用名 xTools）。第一版：截图、贴图；后续：粘贴板。

- 技术栈：Swift 6 + AppKit，SwiftPM 构建，最低 macOS 14
- 设计文档：[docs/mac-toolbox-design.md](../../docs/mac-toolbox-design.md)

## 构建与运行

```bash
swift test                 # 单元测试
./scripts/bundle.sh        # 生成 dist/xTools.app
open dist/xTools.app
```

只装命令行工具（没有 Xcode）也能构建。
已知问题：命令行工具自带的 Swift 6.4 偶尔会报 `plugin for module 'TestingMacros' not found`
（打包之后紧接着跑测试时最常见），代码没问题，重跑一次 `swift test` 即可。

**签名**：屏幕录制权限绑定在签名上。用临时签名时，每次重新编译后都要去「系统设置 → 隐私与安全性 → 屏幕录制」重新勾选。
有固定证书时这样打包：

```bash
SIGN_IDENTITY="证书名称" ./scripts/bundle.sh
```

## 当前功能

| 功能 | 操作 |
|---|---|
| 区域截图 | F1 或菜单栏「区域截图」（没开“将 F1、F2 等键用作标准功能键”时按 fn+F1） |
| 框选 | 拖拽；单击选中光标下的窗口（没有窗口则选整屏）；拖动选区内部可移动 |
| 复制 | 回车 / 双击选区 / ⌘C |
| 保存 | ⌘S，默认存到桌面 |
| 取消 | Esc / 右键 |

## 目录

```
Sources/
├── App/                # 入口：注册模块、菜单栏
├── ToolboxCore/        # 底座：模块协议、快捷键、设置、权限、剪贴板、服务注册
└── FeatureScreenshot/  # 截图模块
```

新增功能模块：建 `Sources/FeatureXxx/`，实现 `ToolModule`，在 `Package.swift` 和 `AppDelegate.modules` 各加一行。
功能模块之间不能互相 import，协作通过 `ServiceRegistry` 里的协议。
