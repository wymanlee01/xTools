import AppKit
import Carbon.HIToolbox

/// 一个全局快捷键：Carbon 键码 + 修饰键
public struct Hotkey: Hashable, Sendable {
    public let keyCode: UInt32
    /// 存原始值，方便做字典 key 判断冲突
    private let modifierRaw: UInt

    public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierRaw) }

    public init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        self.modifierRaw = modifiers.intersection([.command, .option, .control, .shift]).rawValue
    }

    /// 存进设置的格式："键码:修饰键原始值"
    public var storageValue: String { "\(keyCode):\(modifierRaw)" }

    public init?(storageValue: String) {
        let parts = storageValue.split(separator: ":").compactMap { UInt($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: Int(parts[0]), modifiers: NSEvent.ModifierFlags(rawValue: parts[1]))
    }

    /// 显示用的文字，如 “⇧F3”“⌥A”
    public var displayName: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Hotkey.keyName(for: Int(keyCode))
    }

    /// 键码转键名：功能键、特殊键查表，其余按当前键盘布局转成字符
    static func keyName(for keyCode: Int) -> String {
        let special: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
            kVK_Space: "空格", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        if let name = special[keyCode] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// 转成 Carbon 需要的修饰键位
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// 菜单项的 keyEquivalent 字符：设上后菜单右侧会用系统样式显示这个快捷键（如 ⌃⌥←）
    /// 再配合 modifiers 设 keyEquivalentModifierMask；转不了的按键返回 nil
    public var menuKeyEquivalent: String? {
        func function(_ key: Int) -> String { String(Character(UnicodeScalar(UInt16(key))!)) }
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        switch Int(keyCode) {
        case kVK_LeftArrow: return function(NSLeftArrowFunctionKey)
        case kVK_RightArrow: return function(NSRightArrowFunctionKey)
        case kVK_UpArrow: return function(NSUpArrowFunctionKey)
        case kVK_DownArrow: return function(NSDownArrowFunctionKey)
        case kVK_Return: return "\r"
        case kVK_Delete: return "\u{8}"
        case kVK_ForwardDelete: return function(NSDeleteFunctionKey)
        case kVK_Escape: return "\u{1b}"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case let key where fKeys.contains(key): return function(NSF1FunctionKey + fKeys.firstIndex(of: key)!)
        default:
            let name = Hotkey.keyName(for: Int(keyCode))
            return name.count == 1 && name != "?" ? name.lowercased() : nil
        }
    }
}

extension NSMenuItem {
    /// 托盘菜单项右侧用系统样式显示快捷键（转不成 keyEquivalent 的按键拼在标题后面）。
    /// 菜单打开时按这个键由 HotkeyCenter.watchKeys 执行；托盘菜单的代理要拦住系统按 keyEquivalent 处理
    /// （见 AppDelegate.menuHasKeyEquivalent），否则系统会先收起菜单再执行，截图就截不到菜单了
    public func setHotkey(_ hotkey: Hotkey?) {
        guard let hotkey else { return }
        if let key = hotkey.menuKeyEquivalent {
            keyEquivalent = key
            keyEquivalentModifierMask = hotkey.modifiers
        } else {
            title += "  \(hotkey.displayName)"
        }
    }
}

public enum HotkeyError: Error, Equatable {
    /// 应用内已有模块占用了这个快捷键
    case conflict(owner: String)
    /// 系统或其他应用占用（注册失败）
    case registerFailed(OSStatus)
}

/// 统一注册全局快捷键，并检查模块之间的冲突
/// 用 Carbon RegisterEventHotKey 实现，不需要辅助功能权限
@MainActor
public final class HotkeyCenter {
    private struct Entry {
        let owner: String
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var owners: [Hotkey: UInt32] = [:]
    private var nextId: UInt32 = 1
    private var handlerInstalled = false
    /// 应用内按键监听（见 installHandlerIfNeeded）
    private var localMonitor: Any?
    /// 每个快捷键上次执行的时间：全局和应用内两条路可能同时收到同一次按键，0.3 秒内只执行一次
    private var lastFired: [UInt32: Date] = [:]

    /// 托盘菜单打开期间检查快捷键按键的定时器（见 watchKeys(whileOpen:)）
    private var menuTimer: Timer?
    /// 正打开着的托盘菜单
    private weak var openMenu: NSMenu?
    /// 菜单打开期间正按着的快捷键：只在刚按下时执行一次
    private var menuKeysDown: Set<UInt32> = []
    /// 菜单打开期间已执行过的快捷键和菜单关闭时间：菜单关闭时系统会补发积压的快捷键，要忽略
    private var firedInMenu: Set<UInt32> = []
    private var menuClosedAt = Date.distantPast

    /// 设置页的快捷键录入框正在录键时为 true：这时按下的组合键是要录进去的，不当快捷键执行
    public static var isRecordingShortcut = false

    public init() {}

    /// 注册快捷键；owner 一般传模块 id，方便排查冲突
    public func register(_ hotkey: Hotkey, owner: String, action: @escaping () -> Void) throws {
        if let id = owners[hotkey], let entry = entries[id] {
            throw HotkeyError.conflict(owner: entry.owner)
        }
        installHandlerIfNeeded()

        let id = nextId
        nextId += 1
        var ref: EventHotKeyRef?
        let hotkeyId = EventHotKeyID(signature: OSType(0x7854_6F6C), id: id) // 'xTol'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, hotkeyId,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotkeyError.registerFailed(status) }

        entries[id] = Entry(owner: owner, ref: ref, action: action)
        owners[hotkey] = id
    }

    /// 注销某个模块的全部快捷键
    public func unregisterAll(owner: String) {
        for (hotkey, id) in owners where entries[id]?.owner == owner {
            if let ref = entries[id]?.ref { UnregisterEventHotKey(ref) }
            entries[id] = nil
            owners[hotkey] = nil
        }
    }

    fileprivate func fire(id: UInt32) {
        let now = Date()
        if let last = lastFired[id], now.timeIntervalSince(last) < 0.3 { return }
        if firedInMenu.contains(id), openMenu != nil || now.timeIntervalSince(menuClosedAt) < 0.5 { return }
        lastFired[id] = now
        entries[id]?.action()
    }

    /// 托盘菜单打开时调用：菜单打开期间按键都被菜单拿走，全局快捷键要等菜单关了才送达。
    /// 这里定时检查已注册的快捷键有没有按下，按下就直接执行，菜单还开着（截图能截到菜单）
    public func watchKeys(whileOpen menu: NSMenu) {
        stopWatchingKeys()
        openMenu = menu
        firedInMenu = []
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let down = self.pressedIds()
                for id in down.subtracting(self.menuKeysDown) {
                    self.fire(id: id)
                    self.firedInMenu.insert(id)
                }
                self.menuKeysDown = down
            }
        }
        // 菜单打开期间 RunLoop 处于 eventTracking 模式，加到 common 才会触发
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    /// 托盘菜单关闭时调用
    public func stopWatchingKeys() {
        menuTimer?.invalidate()
        menuTimer = nil
        if openMenu != nil { menuClosedAt = Date() }
        openMenu = nil
        menuKeysDown = []
    }

    /// 收起正打开着的托盘菜单（截图冻结完屏幕、要显示遮罩时调用）
    public func dismissOpenMenu() {
        openMenu?.cancelTracking()
    }

    /// 正被按住的已注册快捷键（按键和修饰键都对上）
    private func pressedIds() -> Set<UInt32> {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        let pressed = flags.intersection([.command, .option, .control, .shift])
        let ids = owners.compactMap { hotkey, id in
            hotkey.modifiers == pressed && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(hotkey.keyCode)) ? id : nil
        }
        return Set(ids)
    }

    /// 这个按键是不是已注册的快捷键
    public func isRegistered(_ event: NSEvent) -> Bool {
        registeredId(for: event) != nil
    }

    /// 按键对应的已注册快捷键 id（修饰键只比较 ⌘⌥⌃⇧）
    private func registeredId(for event: NSEvent) -> UInt32? {
        owners[Hotkey(keyCode: Int(event.keyCode), modifiers: event.modifierFlags)]
    }

    /// 安装一次 Carbon 事件回调，按快捷键 id 分发
    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotkeyId = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyId)
            guard let userData else { return noErr }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.fire(id: hotkeyId.id) }
            return noErr
        }, 1, &eventType, selfPtr, nil)

        // xTools 自己的窗口拿着键盘时（偏好设置窗口、粘贴板这类不激活的浮动面板），
        // 系统把按键直接发给窗口、不会当全局快捷键触发，所以在应用内再匹配一次
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !Self.isRecordingShortcut, let id = self.registeredId(for: event) else { return event }
            // 按住不放产生的重复按键吞掉、不重复执行（全局快捷键本身也不会重复触发）
            if !event.isARepeat { self.fire(id: id) }
            return nil
        }
    }
}
