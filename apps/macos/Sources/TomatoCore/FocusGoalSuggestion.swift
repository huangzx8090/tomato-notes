import Foundation

/// 仅包含本轮已选白名单的文字信息，不保存应用标识或完整网址。
public struct FocusGoalContext: Encodable, Equatable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case app, page, site }
        public let kind: Kind
        public let name: String
        public let site: String?
    }

    public let entries: [Entry]
    public let omittedCount: Int
    public var isEmpty: Bool { entries.isEmpty }

    public init(plan: FocusGuardPlan, apps: [AppIdentity], tabs: [GuardPage] = []) {
        var descriptions = Set<Entry>()
        func add(_ kind: Entry.Kind, name: String, site: String? = nil) {
            let name = ActivityPrivacy.clean(name, limit: 240).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !name.isEmpty else { return }
            descriptions.insert(.init(kind: kind, name: name, site: site.map { String($0.prefix(160)) }))
        }
        for app in apps where plan.appIDs.contains(app.bundleID) && !app.bundleID.hasPrefix("com.zixuan.TomatoNotes") {
            add(.app, name: app.name)
        }
        for rule in plan.pages {
            switch rule.kind {
            case .page:
                guard let key = FocusPageRule.pageKey(rule.value), let host = URLComponents(string: key)?.host else { continue }
                let title = tabs.first { !$0.isPrivate && rule.matches($0.url) }?.title ?? rule.title
                add(.page, name: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : title, site: host)
            case .site:
                guard let host = FocusPageRule.siteHost(rule.value) else { continue }
                add(.site, name: host, site: host)
                for tab in tabs where !tab.isPrivate && rule.matches(tab.url) && FocusPageRule.pageKey(tab.url) != nil {
                    add(.page, name: tab.title, site: tab.host)
                }
            }
        }
        // 固定顺序和体积，连续勾选或调整顺序不会产生相同资料的重复请求。
        let sorted = descriptions.sorted { ($0.kind.rawValue, $0.site ?? "", $0.name) < ($1.kind.rawValue, $1.site ?? "", $1.name) }
        var selected: [Entry] = [], byteCount = 0
        for entry in sorted {
            let size = (try? JSONEncoder().encode(entry).count) ?? 24_577
            guard selected.count < 64, size <= 24_576 - byteCount else { continue }
            selected.append(entry)
            byteCount += size
        }
        entries = selected
        omittedCount = descriptions.count - selected.count
    }
}

public struct FocusGoalSuggestion: Sendable {
    public let title: String
    public let inputTokens: Int
    public let outputTokens: Int

    public init(title: String, inputTokens: Int = 0, outputTokens: Int = 0) {
        self.title = title
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum FocusGoalError: LocalizedError {
    case emptyWhitelist, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .emptyWhitelist: "请先选择本轮白名单，再让 AI 生成学习名称。"
        case .invalidResponse: "这次未能生成有效名称，可重试或手动填写。"
        }
    }
}
