import AppKit
import Carbon.HIToolbox
import ToolboxCore

/// 分屏动作：快捷键、菜单、设置页都按这个顺序列出
/// （半屏 → 四分之一 → 换显示器 → 最大化 / 居中 / 还原）
public enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case nextDisplay, previousDisplay
    case maximize, center, restore

    /// 菜单里的短名字（前面有示意图标）
    public var menuTitle: String {
        switch self {
        case .leftHalf: return "左"
        case .rightHalf: return "右"
        case .topHalf: return "上"
        case .bottomHalf: return "下"
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        case .nextDisplay: return "下一个显示器"
        case .previousDisplay: return "上一个显示器"
        case .maximize: return "最大化"
        case .center: return "居中"
        case .restore: return "还原"
        }
    }

    public var title: String {
        switch self {
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .topHalf: return "上半屏"
        case .bottomHalf: return "下半屏"
        case .topLeft: return "左上四分之一"
        case .topRight: return "右上四分之一"
        case .bottomLeft: return "左下四分之一"
        case .bottomRight: return "右下四分之一"
        case .maximize: return "最大化"
        case .center: return "居中"
        case .restore: return "还原"
        case .nextDisplay: return "移到下一个显示器"
        case .previousDisplay: return "移到上一个显示器"
        }
    }

    /// 默认快捷键：⌃⌥ + 方向键 / 字母（多屏移动再加 ⌘）
    public var defaultHotkey: Hotkey {
        let base: NSEvent.ModifierFlags = [.control, .option]
        switch self {
        case .leftHalf: return Hotkey(keyCode: kVK_LeftArrow, modifiers: base)
        case .rightHalf: return Hotkey(keyCode: kVK_RightArrow, modifiers: base)
        case .topHalf: return Hotkey(keyCode: kVK_UpArrow, modifiers: base)
        case .bottomHalf: return Hotkey(keyCode: kVK_DownArrow, modifiers: base)
        case .topLeft: return Hotkey(keyCode: kVK_ANSI_U, modifiers: base)
        case .topRight: return Hotkey(keyCode: kVK_ANSI_I, modifiers: base)
        case .bottomLeft: return Hotkey(keyCode: kVK_ANSI_J, modifiers: base)
        case .bottomRight: return Hotkey(keyCode: kVK_ANSI_K, modifiers: base)
        case .maximize: return Hotkey(keyCode: kVK_Return, modifiers: base)
        case .center: return Hotkey(keyCode: kVK_ANSI_C, modifiers: base)
        case .restore: return Hotkey(keyCode: kVK_Delete, modifiers: base)
        case .nextDisplay: return Hotkey(keyCode: kVK_RightArrow, modifiers: base.union(.command))
        case .previousDisplay: return Hotkey(keyCode: kVK_LeftArrow, modifiers: base.union(.command))
        }
    }

    /// 占屏幕的比例区域（0~1，原点在左下）；居中、恢复、多屏移动不是固定区域，返回 nil
    func region() -> (x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat)? {
        switch self {
        case .leftHalf: return (0, 0, 0.5, 1)
        case .rightHalf: return (0.5, 0, 1, 1)
        case .topHalf: return (0, 0.5, 1, 1)
        case .bottomHalf: return (0, 0, 1, 0.5)
        case .topLeft: return (0, 0.5, 0.5, 1)
        case .topRight: return (0.5, 0.5, 1, 1)
        case .bottomLeft: return (0, 0, 0.5, 0.5)
        case .bottomRight: return (0.5, 0, 1, 0.5)
        case .maximize: return (0, 0, 1, 1)
        case .center, .restore, .nextDisplay, .previousDisplay: return nil
        }
    }
}
