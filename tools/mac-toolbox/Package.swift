// swift-tools-version:6.0
import PackageDescription

// 依赖方向：App → Feature 模块 → ToolboxCore
// 功能模块之间禁止互相依赖，协作只能通过 ToolboxCore 里的协议
let package = Package(
    name: "MacToolbox",
    platforms: [.macOS(.v14)],
    targets: [
        // 底座：模块协议、快捷键、设置、权限、剪贴板、服务注册
        .target(name: "ToolboxCore"),

        // 功能模块：截图
        .target(name: "FeatureScreenshot", dependencies: ["ToolboxCore"]),
        // 功能模块：贴图（通过 ToolboxCore 里的 PinService 给截图模块用）
        .target(name: "FeaturePin", dependencies: ["ToolboxCore"]),
        // 功能模块：OCR（实现 OCRService，通过 CaptureService 框选）
        .target(name: "FeatureOCR", dependencies: ["ToolboxCore"]),
        // 功能模块：录屏（通过 CaptureService 框选）
        .target(name: "FeatureRecord", dependencies: ["ToolboxCore"]),
        // 功能模块：粘贴板（用底座的剪贴板监听和 PinService）
        .target(name: "FeatureClipboard", dependencies: ["ToolboxCore"]),
        // 功能模块：分屏（用辅助功能接口移动和缩放其他应用的窗口）
        .target(name: "FeatureWindow", dependencies: ["ToolboxCore"]),

        // 检查更新：从 GitHub Releases 下载新版本、校验签名、替换安装（不依赖界面）
        .target(name: "AppUpdater"),

        // 应用入口：组装模块、菜单栏
        .executableTarget(name: "App", dependencies: ["ToolboxCore", "AppUpdater", "FeatureScreenshot", "FeaturePin", "FeatureOCR", "FeatureRecord", "FeatureClipboard", "FeatureWindow"]),

        .testTarget(name: "ToolboxCoreTests", dependencies: ["ToolboxCore"]),
        .testTarget(name: "FeatureScreenshotTests", dependencies: ["FeatureScreenshot"]),
        .testTarget(name: "FeaturePinTests", dependencies: ["FeaturePin"]),
        .testTarget(name: "FeatureOCRTests", dependencies: ["FeatureOCR"]),
        .testTarget(name: "FeatureRecordTests", dependencies: ["FeatureRecord"]),
        .testTarget(name: "FeatureClipboardTests", dependencies: ["FeatureClipboard"]),
        .testTarget(name: "FeatureWindowTests", dependencies: ["FeatureWindow"]),
        .testTarget(name: "AppUpdaterTests", dependencies: ["AppUpdater"]),
    ],
    swiftLanguageModes: [.v5]
)
