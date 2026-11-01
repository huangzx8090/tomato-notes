import Foundation

/// 独立扩展字段保存关键词与用户选择频次，旧端通过未知字段保留它。
/// 次数仅供排序；AI 自动勾选、打开窗口和刷新均不累计。
public struct FocusWhitelistMemory: Codable, Sendable {
    public var keywords: [String] = []
    public var counts: [String: Int] = [:]
    public init() {}
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public mutating func record(_ keys: Set<String>) {
        for key in keys { counts[key] = min(1_000_000, max(0, counts[key] ?? 0) + 1) }
    }
    public func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let a = counts[lhs] ?? 0, b = counts[rhs] ?? 0
        return a == b ? lhs.localizedStandardCompare(rhs) == .orderedAscending : a > b
    }
}

extension FocusGuardSettings {
    public var whitelistMemory: FocusWhitelistMemory {
        get {
            guard let value = extraFields["macOSWhitelistMemory"],
                  let data = try? JSONEncoder().encode(value),
                  let memory = try? JSONDecoder().decode(FocusWhitelistMemory.self, from: data) else { return .init() }
            return memory
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
            extraFields["macOSWhitelistMemory"] = value
        }
    }
}
