import Foundation
import Testing
import ToolboxCore
@testable import FeatureScreenshot

struct ToolShortcutsTests {
    func makeShortcuts() -> ToolShortcuts {
        let defaults = UserDefaults(suiteName: "xtools.tests.\(UUID().uuidString)")!
        return ToolShortcuts(settings: SettingsStore(defaults: defaults).scoped("screenshot"))
    }

    @Test func 默认快捷键和iShot一致() {
        let shortcuts = makeShortcuts()
        #expect(shortcuts.key(for: .rectangle) == "1")
        #expect(shortcuts.key(for: .highlight) == "9")
        #expect(shortcuts.key(for: .save) == "ㄩ")
        #expect(shortcuts.key(for: .copy) == "↩")
        #expect(shortcuts.action(forKey: "T") == .pin)
    }

    @Test func 改成已占用的键会互换() {
        let shortcuts = makeShortcuts()
        shortcuts.set("2", for: .rectangle)  // 2 原本是椭圆
        #expect(shortcuts.key(for: .rectangle) == "2")
        #expect(shortcuts.key(for: .ellipse) == "1")
    }

    @Test func 按键转快捷键名() {
        #expect(ToolShortcuts.key(characters: " ", keyCode: 49) == "ㄩ")
        #expect(ToolShortcuts.key(characters: "\r", keyCode: 36) == "↩")
        #expect(ToolShortcuts.key(characters: "t", keyCode: 17) == "T")
        #expect(ToolShortcuts.key(characters: "-", keyCode: 27) == nil)
    }

    @Test func 每个工具都有对应的快捷键操作() {
        for tool in AnnotationTool.allCases {
            #expect(ShortcutAction(tool: tool).tool == tool)
        }
    }
}
