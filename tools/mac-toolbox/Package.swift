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

        // 应用入口：组装模块、菜单栏
        .executableTarget(name: "App", dependencies: ["ToolboxCore", "FeatureScreenshot", "FeaturePin", "FeatureOCR", "FeatureRecord"]),

        .testTarget(name: "ToolboxCoreTests", dependencies: ["ToolboxCore"]),
        .testTarget(name: "FeatureScreenshotTests", dependencies: ["FeatureScreenshot"]),
        .testTarget(name: "FeaturePinTests", dependencies: ["FeaturePin"]),
        .testTarget(name: "FeatureOCRTests", dependencies: ["FeatureOCR"]),
        .testTarget(name: "FeatureRecordTests", dependencies: ["FeatureRecord"]),
    ],
    swiftLanguageModes: [.v5]
)
