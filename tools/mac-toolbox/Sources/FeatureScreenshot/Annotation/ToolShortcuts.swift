import Foundation
import ToolboxCore

/// 截图界面里可以自定义单键快捷键的操作（和 iShot 工具栏的悬浮提示框一一对应）
public enum ShortcutAction: String, CaseIterable {
    case rectangle, ellipse, line, arrow, pencil, mosaic, text, step, highlight
    case pin, ocr, scroll, save, copy

    /// 默认快捷键，取自 iShot 的默认设置（ㄩ 是空格，↩ 是回车）
    var defaultKey: String {
        switch self {
        case .rectangle: return "1"
        case .ellipse: return "2"
        case .line: return "3"
        case .arrow: return "4"
        case .pencil: return "5"
        case .mosaic: return "6"
        case .text: return "7"
        case .step: return "8"
        case .highlight: return "9"
        case .pin: return "T"
        case .ocr: return "O"
        case .scroll: return "S"
        case .save: return ToolShortcuts.space
        case .copy: return ToolShortcuts.enter
        }
    }

    /// 对应的标注工具；贴图、OCR 等不是工具
    var tool: AnnotationTool? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .pencil: return .pencil
        case .mosaic: return .mosaic
        case .text: return .text
        case .step: return .step
        case .highlight: return .highlight
        default: return nil
        }
    }

    init(tool: AnnotationTool) {
        self = ShortcutAction.allCases.first { $0.tool == tool }!
    }
}

/// 快捷键设置：存在截图模块的设置里，键名如 "screenshot.shortcut.rectangle"
public final class ToolShortcuts {
    public static let space = "ㄩ"
    public static let enter = "↩"
    /// 下拉框可选的按键：0~9、A~Z；保存和复制额外可选空格、回车
    public static let keys = (0...9).map(String.init) + (65...90).map { String(UnicodeScalar($0)!) }
    public static let specialKeys = [space, enter]

    private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public func key(for action: ShortcutAction) -> String {
        settings.string("shortcut.\(action.rawValue)", default: action.defaultKey)
    }

    /// 设置快捷键；如果这个键已被别的操作占用，两者互换
    public func set(_ key: String, for action: ShortcutAction) {
        let old = self.key(for: action)
        if let other = self.action(forKey: key), other != action {
            settings.set(old, for: "shortcut.\(other.rawValue)")
        }
        settings.set(key, for: "shortcut.\(action.rawValue)")
    }

    public func action(forKey key: String) -> ShortcutAction? {
        ShortcutAction.allCases.first { self.key(for: $0) == key }
    }

    /// 把按键事件转成快捷键名：空格 → ㄩ，回车 → ↩，其余取大写字符
    public static func key(characters: String?, keyCode: UInt16) -> String? {
        switch keyCode {
        case 49: return space
        case 36, 76: return enter
        default:
            guard let char = characters?.uppercased(), keys.contains(char) else { return nil }
            return char
        }
    }
}
