import Foundation
import Testing
@testable import ToolboxCore

struct SettingsStoreTests {
    @Test func 模块设置带前缀互不干扰() {
        let defaults = UserDefaults(suiteName: "xtools.tests.\(UUID().uuidString)")!
        let root = SettingsStore(defaults: defaults)
        let screenshot = root.scoped("screenshot")
        let clipboard = root.scoped("clipboard")

        screenshot.set("/tmp/a", for: "saveDirectory")
        #expect(defaults.string(forKey: "screenshot.saveDirectory") == "/tmp/a")
        #expect(clipboard.string("saveDirectory", default: "默认") == "默认")
    }
}

@MainActor
struct ServiceRegistryTests {
    protocol Greeter { func hello() -> String }
    struct English: Greeter { func hello() -> String { "hi" } }

    @Test func 按协议注册和取用服务() {
        let registry = ServiceRegistry()
        #expect(registry.resolve(Greeter.self) == nil)
        registry.register(Greeter.self, English())
        #expect(registry.resolve(Greeter.self)?.hello() == "hi")
    }
}

@MainActor
struct HotkeyCenterTests {
    @Test func 同一快捷键被两个模块注册会报冲突() throws {
        let center = HotkeyCenter()
        // 用一个不常用的组合，避免和系统冲突
        let hotkey = Hotkey(keyCode: 0x6F, modifiers: [.control, .option, .shift, .command]) // F12
        try center.register(hotkey, owner: "screenshot") {}
        #expect(throws: HotkeyError.conflict(owner: "screenshot")) {
            try center.register(hotkey, owner: "clipboard") {}
        }
        center.unregisterAll(owner: "screenshot")
        try center.register(hotkey, owner: "clipboard") {}
        center.unregisterAll(owner: "clipboard")
    }
}
