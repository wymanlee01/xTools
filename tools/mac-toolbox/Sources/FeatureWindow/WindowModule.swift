import AppKit
import ToolboxCore

/// 分屏设置，键名都在 “window.” 下
struct WindowSettings {
    let store: SettingsStore

    static func hotkeyKey(_ action: WindowAction) -> String { "hotkey.\(action.rawValue)" }

    func hotkey(for action: WindowAction) -> Hotkey? {
        store.hotkey(Self.hotkeyKey(action), default: action.defaultHotkey)
    }

    /// 窗口之间、窗口和屏幕边缘的间距，默认 0
    var gap: CGFloat { CGFloat(store.double("gap", default: 0)) }

    /// 忽略的应用（bundle id）：这些应用的窗口快捷键和菜单都不分屏
    var ignoredApps: [String] {
        store.string("ignoredApps", default: "").split(separator: ",").map(String.init)
    }

    func set(ignoredApps: [String]) {
        store.set(ignoredApps.joined(separator: ","), for: "ignoredApps")
    }
}

/// 分屏模块：快捷键或托盘子菜单把当前窗口放到半屏、四分之一等位置；可恢复、可换屏
@MainActor
public final class WindowModule: ToolModule {
    public let id = "window"
    public let title = "分屏"
    /// 移动其他应用的窗口需要辅助功能权限
    public let requiredPermissions: [Permission] = [.accessibility]

    private var context: ToolContext?
    private var settings: WindowSettings?
    private let memory = RestoreMemory()

    public init() {}

    /// 托盘菜单只加一项“窗口分屏”，全部动作放在子菜单里：
    /// 每项前面有示意图标、右侧是快捷键；用不了的项变灰（只有一块屏幕时的换显示器、已经在那个位置的布局、没有可还原的位置）；
    /// 最后一项“忽略 当前应用”
    public func menuItems() -> [NSMenuItem] {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let state = MenuState(memory: memory, gap: settings?.gap ?? 0, ignoredApps: settings?.ignoredApps ?? [])
        let groups: [[WindowAction]] = [
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            [.topLeft, .topRight, .bottomLeft, .bottomRight],
            [.nextDisplay, .previousDisplay],
            [.maximize, .center, .restore],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for action in group {
                let item = NSMenuItem(title: action.menuTitle, action: #selector(menuClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                item.image = WindowMenuIcon.image(for: action)
                item.setHotkey(settings?.hotkey(for: action))
                item.isEnabled = state.isEnabled(action)
                submenu.addItem(item)
            }
        }
        if let app = state.app, let bundleID = app.bundleIdentifier {
            submenu.addItem(.separator())
            let ignore = NSMenuItem(title: "忽略“\(app.localizedName ?? bundleID)”", action: #selector(toggleIgnore(_:)),
                                    keyEquivalent: "")
            ignore.target = self
            ignore.representedObject = bundleID
            ignore.state = state.ignored ? .on : .off
            submenu.addItem(ignore)
        }
        let root = NSMenuItem(title: "窗口分屏", action: nil, keyEquivalent: "")
        // 和托盘菜单其他项一样用系统图标（子菜单里才用示意图）
        root.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        root.submenu = submenu
        return [root]
    }

    /// 打开菜单时当前窗口的情况，用来决定哪些项变灰
    @MainActor
    private struct MenuState {
        let app: NSRunningApplication?
        let ignored: Bool
        private let window: AXUIElement?
        private let current: CGRect?
        private let screens: [CGRect]
        private let visible: CGRect?
        private let gap: CGFloat
        private let canRestore: Bool

        init(memory: RestoreMemory, gap: CGFloat, ignoredApps: [String]) {
            let front = NSWorkspace.shared.frontmostApplication
            app = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            ignored = app?.bundleIdentifier.map(ignoredApps.contains) ?? false
            window = try? WindowMover.focusedWindow()
            current = window.flatMap(WindowMover.frame(of:))
            let screens = NSScreen.screens.map(\.visibleFrame)
            self.screens = screens
            visible = current.flatMap { WindowGeometry.screenIndex(for: $0, in: screens) }.map { screens[$0] }
            self.gap = gap
            canRestore = window.map(memory.contains) ?? false
        }

        func isEnabled(_ action: WindowAction) -> Bool {
            if ignored { return false }
            switch action {
            case .nextDisplay, .previousDisplay: return screens.count > 1
            case .restore: return canRestore
            case .center:
                guard let current, let visible else { return true }
                return !Self.same(WindowGeometry.centered(current, in: visible), current)
            default:
                // 窗口已经在这个位置了（比如已经最大化），这一项变灰
                guard let current, let visible, let target = WindowGeometry.frame(for: action, in: visible, gap: gap) else { return true }
                return !Self.same(target, current)
            }
        }

        /// 位置大小差 2 点以内算同一个位置（有的应用会把尺寸取整）
        private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
        }
    }

    @objc private func toggleIgnore(_ sender: NSMenuItem) {
        guard let settings, let bundleID = sender.representedObject as? String else { return }
        var apps = settings.ignoredApps
        if let index = apps.firstIndex(of: bundleID) { apps.remove(at: index) } else { apps.append(bundleID) }
        settings.set(ignoredApps: apps)
    }

    public func start(context: ToolContext) {
        self.context = context
        settings = WindowSettings(store: context.settings.scoped(id))
        registerHotkeys(showConflicts: false)
    }

    public func stop() {
        context?.hotkeys.unregisterAll(owner: id)
    }

    public func reloadSettings() {
        registerHotkeys(showConflicts: false)
    }

    public func settingsPages() -> [SettingsPageInfo] {
        guard let settings, let context else { return [] }
        return [WindowSettingsPage.make(settings: settings, permissions: context.permissions) { [weak self] in
            self?.registerHotkeys(showConflicts: true)
        }]
    }

    /// 注册全部动作的快捷键；从设置页改动时，被占用的快捷键用提示告诉用户
    private func registerHotkeys(showConflicts: Bool) {
        guard let context, let settings else { return }
        context.hotkeys.unregisterAll(owner: id)
        var failed: [String] = []
        for action in WindowAction.allCases {
            guard let hotkey = settings.hotkey(for: action) else { continue }
            do {
                try context.hotkeys.register(hotkey, owner: id) { [weak self] in self?.perform(action) }
            } catch {
                failed.append("\(action.title) \(hotkey.displayName)")
                NSLog("[window] 快捷键注册失败：\(action.title) \(hotkey.displayName) \(error)")
            }
        }
        if showConflicts, !failed.isEmpty { HUD.show("快捷键被占用：" + failed.joined(separator: "、")) }
    }

    @objc private func menuClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = WindowAction(rawValue: raw) else { return }
        perform(action)
    }

    /// 对当前前台窗口执行分屏动作
    func perform(_ action: WindowAction) {
        // 忽略的应用不分屏
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings?.ignoredApps.contains(bundleID) == true { return }
        do {
            let window = try WindowMover.focusedWindow()
            guard let current = WindowMover.frame(of: window) else { HUD.show("读不到这个窗口的位置"); return }
            let screens = NSScreen.screens.map(\.visibleFrame)
            guard !screens.isEmpty else { return }
            let index = WindowGeometry.screenIndex(for: current, in: screens) ?? 0
            let visible = screens[index]

            let target: CGRect
            switch action {
            case .restore:
                guard let original = memory.take(window) else { HUD.show("这个窗口没有分屏前的位置可恢复"); return }
                WindowMover.setFrame(original, of: window)
                return
            case .center:
                target = WindowGeometry.centered(current, in: visible)
            case .nextDisplay, .previousDisplay:
                guard screens.count > 1 else { HUD.show("只有一块屏幕"); return }
                let to = WindowGeometry.neighborIndex(of: index, in: screens, forward: action == .nextDisplay)
                target = WindowGeometry.moved(current, from: visible, to: screens[to])
            default:
                guard let frame = WindowGeometry.frame(for: action, in: visible, gap: settings?.gap ?? 0) else { return }
                target = frame
            }
            memory.rememberIfNeeded(window, frame: current)
            WindowMover.setFrame(target, of: window)
        } catch WindowMover.Failure.notTrusted {
            HUD.show("需要“辅助功能”权限才能移动窗口")
            context?.permissions.request(.accessibility)
        } catch WindowMover.Failure.fullScreen {
            HUD.show("全屏窗口不能分屏，先退出全屏")
        } catch {
            HUD.show("没有可以分屏的窗口")
        }
    }
}
