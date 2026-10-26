import Foundation

/// 版本号：“0.2.0”、“v1.10.3” 这种点分数字，按段比较（1.10 > 1.9）
public struct Version: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    /// 去掉开头的 v，按点拆成数字；有非数字段就认为不是版本号
    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        let parts = value.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// 段数不同时缺的段当 0（1.2 == 1.2.0）
    public static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
