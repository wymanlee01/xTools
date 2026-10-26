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

    func fullKey(_ key: String) -> String {
        prefix.isEmpty ? key : "\(prefix).\(key)"
    }
}
