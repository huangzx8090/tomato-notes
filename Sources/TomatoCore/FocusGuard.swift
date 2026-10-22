import Foundation

public struct FocusGuardSettings: Codable, Sendable {
    public var enabled = false
    public var remindAfterSeconds = 60
    public var graceSeconds = 60
    public var maxChecks = 3
    public var reuseLastPlan = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, remindAfterSeconds, graceSeconds, maxChecks, reuseLastPlan, lastGoal, lastAppIDs, lastPages, lastAllowAIClosing, favoritePages }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        remindAfterSeconds = min(1800, max(5, try values.decodeIfPresent(Int.self, forKey: .remindAfterSeconds) ?? 60))
        graceSeconds = min(600, max(5, try values.decodeIfPresent(Int.self, forKey: .graceSeconds) ?? 60))
        maxChecks = min(5, max(1, try values.decodeIfPresent(Int.self, forKey: .maxChecks) ?? 3))
        reuseLastPlan = try values.decodeIfPresent(Bool.self, forKey: .reuseLastPlan) ?? false
        lastGoal = try values.decodeIfPresent(String.self, forKey: .lastGoal) ?? ""
        lastAppIDs = try values.decodeIfPresent(Set<String>.self, forKey: .lastAppIDs) ?? []
        lastPages = try values.decodeIfPresent([FocusPageRule].self, forKey: .lastPages) ?? []
        lastAllowAIClosing = try values.decodeIfPresent(Bool.self, forKey: .lastAllowAIClosing) ?? false
        favoritePages = try values.decodeIfPresent([FocusPageRule].self, forKey: .favoritePages) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(remindAfterSeconds, forKey: .remindAfterSeconds)
        try values.encode(graceSeconds, forKey: .graceSeconds)
        try values.encode(maxChecks, forKey: .maxChecks)
        try values.encode(reuseLastPlan, forKey: .reuseLastPlan)
        try values.encode(lastGoal, forKey: .lastGoal)
        try values.encode(lastAppIDs, forKey: .lastAppIDs)
        try values.encode(lastPages, forKey: .lastPages)
        try values.encode(false, forKey: .lastAllowAIClosing)
        try values.encode(favoritePages, forKey: .favoritePages)
    }
    /// 跨轮次保留的常用白名单；由用户在设置弹窗里显式保存或清除。
    /// 仅在用户开启沿用时保存候选名单；生效计划绑定新一轮，不带关闭授权。
    public var lastGoal = ""
    public var lastAppIDs: Set<String> = []
    public var lastPages: [FocusPageRule] = []
    public var lastAllowAIClosing = false
    public var favoritePages: [FocusPageRule] = []
    public var hasLastPlan: Bool { !lastGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var reusablePlan: FocusGuardPlan? {
        guard reuseLastPlan, hasLastPlan else { return nil }
        return .init(goal: lastGoal, appIDs: lastAppIDs, pages: lastPages, allowAIClosing: false)
    }
    public mutating func rememberDraft(_ plan: FocusGuardPlan?) {
        let saved = reuseLastPlan ? plan : nil
        lastGoal = saved?.goal ?? ""
        lastAppIDs = saved?.appIDs ?? []
        lastPages = saved?.pages ?? []
        lastAllowAIClosing = false
    }
}

public struct FocusPageRule: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case page, site }
    public var kind: Kind
    public var value: String
    public var title: String
    public var id: String { kind.rawValue + ":" + value }
    public init(kind: Kind, value: String, title: String) {
        self.kind = kind
        self.value = value
        self.title = title
    }

    public static func pageKey(_ address: String) -> String? {
        guard var url = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        url.scheme = url.scheme?.lowercased()
        url.host = url.host?.lowercased()
        url.user = nil
        url.password = nil
        url.fragment = nil
        if url.path.isEmpty { url.path = "/" }
        // 保留查询条件，避免将不同的 YouTube 视频等当成同一学习页面。
        return url.string
    }

    public static func siteHost(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: text.contains("://") ? text : "https://" + text),
              var host = url.host?.lowercased(), !host.isEmpty,
              host.contains(".") || host == "localhost" else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    public func matches(_ address: String) -> Bool {
        switch kind {
        case .page: return Self.pageKey(address) == value
        case .site:
            guard let host = URLComponents(string: address)?.host?.lowercased() else { return false }
            return host == value || host.hasSuffix("." + value)
        }
    }
}

public struct FocusGuardPlan: Sendable {
    public var goal: String
    public var appIDs: Set<String>
    public var pages: [FocusPageRule]
    public var allowAIClosing: Bool
    public init(goal: String, appIDs: Set<String>, pages: [FocusPageRule], allowAIClosing: Bool) {
        self.goal = goal
        self.appIDs = appIDs.subtracting(["com.google.Chrome"])
        self.pages = pages
        self.allowAIClosing = allowAIClosing
    }
    public func allows(appID: String, url: String? = nil) -> Bool {
        if appID.hasPrefix("com.zixuan.TomatoNotes") { return true }
        if appID == "com.google.Chrome" { return url.map { address in pages.contains { $0.matches(address) } } ?? false }
        return appIDs.contains(appID)
    }
}

public struct GuardPage: Codable, Sendable, Equatable, Identifiable {
    public struct Bounds: Codable, Sendable, Equatable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }
    public var windowID: String
    public var tabID: String
    public var url: String
    public var title: String
    public var isPrivate: Bool
    public var bounds: Bounds
    public var id: String { "\(windowID):\(tabID):\(url)" }
    public var host: String { URLComponents(string: url)?.host ?? "Chrome 页面" }
    public var mayAssess: Bool {
        !isPrivate && FocusPageRule.pageKey(url) != nil &&
            [bounds.x, bounds.y, bounds.width, bounds.height].allSatisfy(\.isFinite) &&
            bounds.width > 100 && bounds.height > 100
    }
    public init(windowID: String, tabID: String, url: String, title: String, isPrivate: Bool, bounds: Bounds) {
        self.windowID = windowID; self.tabID = tabID; self.url = url
        self.title = title; self.isPrivate = isPrivate; self.bounds = bounds
    }
}

public struct GuardDwellMonitor: Sendable {
    public enum Action: Equatable, Sendable { case none, remind, assess }
    public private(set) var identity: String?
    private var beganAt: Double?
    private var remindedAt: Double?
    private var assessed = false
    private var lastTick: Double?
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func update(identity next: String?, at uptime: Double,
                                settings: FocusGuardSettings, mayAssess: Bool) -> Action {
        guard let next, uptime.isFinite else { reset(); return .none }
        if identity != next || lastTick.map({ uptime < $0 || uptime - $0 > 8 }) == true {
            identity = next; beganAt = uptime; remindedAt = nil; assessed = false
        }
        lastTick = uptime
        if remindedAt == nil, uptime - (beganAt ?? uptime) >= Double(max(5, settings.remindAfterSeconds)) {
            remindedAt = uptime
            return .remind
        }
        if let remindedAt, !assessed, mayAssess,
           uptime - remindedAt >= Double(max(5, settings.graceSeconds)) {
            assessed = true
            return .assess
        }
        return .none
    }
}

public struct FocusRelevance: Codable, Equatable, Sendable {
    public enum Verdict: String, Codable, Sendable { case related, unrelated, uncertain }
    public var verdict: Verdict
    public var confidence: Double
    public var reason: String
    public var permitsClosing: Bool { verdict == .unrelated && confidence.isFinite && confidence >= 0.9 && confidence <= 1 && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public init(verdict: Verdict, confidence: Double, reason: String) {
        self.verdict = verdict; self.confidence = confidence; self.reason = reason
    }
}

public struct FocusAssessment: Sendable {
    public var relevance: FocusRelevance
    public var inputTokens: Int
    public var outputTokens: Int
    public init(relevance: FocusRelevance, inputTokens: Int, outputTokens: Int) {
        self.relevance = relevance; self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }
}
