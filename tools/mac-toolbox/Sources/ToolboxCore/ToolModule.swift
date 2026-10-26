import AppKit

/// 每个功能模块都实现这个协议，App 启动时统一注册
@MainActor
public protocol ToolModule: AnyObject {
    /// 唯一标识，如 "screenshot"，也用作设置项前缀
    var id: String { get }
    /// 菜单和设置页里显示的名字
    var title: String { get }
    /// 模块需要的系统权限
    var requiredPermissions: [Permission] { get }
    /// 菜单栏里的入口
    func menuItems() -> [NSMenuItem]
    /// 模块启用时调用：在这里注册快捷键、服务
    func start(context: ToolContext)
    /// 模块关闭时调用：释放快捷键、窗口
    func stop()
    /// 设置窗口里属于本模块的页面（左侧菜单各一项）
    func settingsPages() -> [SettingsPageInfo]
    /// 设置被重置后重新读取（如重新注册快捷键）
    func reloadSettings()
}

extension Notification.Name {
    /// 模块请求打开偏好设置窗口（由 App 处理）
    public static let xToolsOpenSettings = Notification.Name("io.github.wymanlee01.xtools.openSettings")
}

extension ToolModule {
    public func settingsPages() -> [SettingsPageInfo] { [] }
    public func reloadSettings() {}
}

/// 底座提供给模块的公共能力，模块只通过它拿服务
@MainActor
public struct ToolContext {
    public let settings: SettingsStore
    public let hotkeys: HotkeyCenter
    public let permissions: PermissionCenter
    public let pasteboard: PasteboardService
    public let services: ServiceRegistry

    public init(settings: SettingsStore, hotkeys: HotkeyCenter, permissions: PermissionCenter,
                pasteboard: PasteboardService, services: ServiceRegistry) {
        self.settings = settings
        self.hotkeys = hotkeys
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.services = services
    }
}
