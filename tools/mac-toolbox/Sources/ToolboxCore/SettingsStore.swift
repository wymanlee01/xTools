import Foundation

/// 设置存储：每个模块拿到带自己前缀的实例，如 "screenshot.saveDirectory"
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "") {
        self.defaults = defaults
        self.prefix = prefix
    }

    /// 生成某个模块专用的设置实例
    public func scoped(_ moduleId: String) -> SettingsStore {
        SettingsStore(defaults: defaults, prefix: fullKey(moduleId))
    }

    public func string(_ key: String, default value: String) -> String {
        defaults.string(forKey: fullKey(key)) ?? value
    }

    public func set(_ value: String, for key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: fullKey(key)) as? Bool ?? value
    }

    public func set(_ value: Bool, for key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func double(_ key: String, default value: Double) -> Double {
        defaults.object(forKey: fullKey(key)) as? Double ?? value
    }

    public func set(_ value: Double, for key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func int(_ key: String, default value: Int) -> Int {
        defaults.object(forKey: fullKey(key)) as? Int ?? value
    }

    public func set(_ value: Int, for key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    /// 删除一项设置，恢复它的默认值
    public func remove(_ key: String) {
        defaults.removeObject(forKey: fullKey(key))
    }

    /// 清掉本前缀下的全部设置，恢复默认值（设置页的“重置”“初始化”按钮）
    public func reset() {
        let head = prefix.isEmpty ? "" : prefix + "."
        for key in defaults.dictionaryRepresentation().keys where head.isEmpty || key.hasPrefix(head) {
            // 没有前缀时只清本应用写的键：带点号的模块设置
            if head.isEmpty && !key.contains(".") { continue }
            defaults.removeObject(forKey: key)
        }
    }

    func fullKey(_ key: String) -> String {
        prefix.isEmpty ? key : "\(prefix).\(key)"
    }
}

extension SettingsStore {
    /// 读取保存的快捷键；没设置过用默认值，设置过“无”返回 nil
    public func hotkey(_ key: String, default value: Hotkey?) -> Hotkey? {
        let stored = string(key, default: value?.storageValue ?? "")
        return stored.isEmpty ? nil : Hotkey(storageValue: stored)
    }

    /// 保存快捷键；nil 表示清除（存空字符串，和“没设置过”区分）
    public func set(_ hotkey: Hotkey?, for key: String) {
        set(hotkey?.storageValue ?? "", for: key)
    }
}
