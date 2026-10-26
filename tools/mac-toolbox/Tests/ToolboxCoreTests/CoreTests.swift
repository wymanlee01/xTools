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

struct SettingsStoreTypesTests {
    func makeStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "xtools.tests.\(UUID().uuidString)")!)
    }

    @Test func 各种类型的读写和默认值() {
        let store = makeStore().scoped("pin")
        #expect(store.bool("showsControls", default: true))
        store.set(false, for: "showsControls")
        #expect(!store.bool("showsControls", default: true))
        store.set(18.0, for: "size")
        #expect(store.double("size", default: 0) == 18)
        store.set(4, for: "action")
        #expect(store.int("action", default: 0) == 4)
        store.remove("action")
        #expect(store.int("action", default: 7) == 7)
    }

    @Test func 重置只清本模块的设置() {
        let root = makeStore()
        let pin = root.scoped("pin"), shot = root.scoped("screenshot")
        pin.set(false, for: "a")
        shot.set(false, for: "a")
        pin.reset()
        #expect(pin.bool("a", default: true))
        #expect(!shot.bool("a", default: true))
    }

    @Test func 快捷键存取和清除() {
        let store = makeStore()
        let f3 = Hotkey(keyCode: 0x63, modifiers: [.shift])
        #expect(store.hotkey("k", default: f3) == f3)          // 没设置过用默认值
        store.set(Hotkey(keyCode: 0x7A, modifiers: []), for: "k")
        #expect(store.hotkey("k", default: f3) == Hotkey(keyCode: 0x7A, modifiers: []))
        store.set(nil as Hotkey?, for: "k")
        #expect(store.hotkey("k", default: f3) == nil)          // 清除后不用默认值
    }
}

struct HotkeyDisplayTests {
    @Test func 存储格式往返() {
        let hotkey = Hotkey(keyCode: 0x63, modifiers: [.shift, .command])
        #expect(Hotkey(storageValue: hotkey.storageValue) == hotkey)
        #expect(Hotkey(storageValue: "坏数据") == nil)
    }

    @Test func 显示名带修饰键符号() {
        #expect(Hotkey(keyCode: 0x63, modifiers: []).displayName == "F3")
        #expect(Hotkey(keyCode: 0x63, modifiers: [.shift]).displayName == "⇧F3")
        #expect(Hotkey(keyCode: 0x31, modifiers: [.control, .option]).displayName == "⌃⌥空格")
    }
}
