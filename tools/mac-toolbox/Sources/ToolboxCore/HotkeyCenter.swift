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
        entries[id]?.action()
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
    }
}
