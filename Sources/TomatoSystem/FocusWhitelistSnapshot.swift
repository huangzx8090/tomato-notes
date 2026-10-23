import Foundation
import TomatoCore

/// AI 只接触匿名候选；真正的 App ID 和页面规则始终在本机映射。
public struct FocusWhitelistSnapshot: Sendable {
    public struct Item: Identifiable, Sendable {
        public let candidate: FocusWhitelistCandidate
        public let appID: String?
        public let pageRule: FocusPageRule?
        public var id: String { candidate.id }
    }

    public let items: [Item]
    public var candidates: [FocusWhitelistCandidate] { items.map(\.candidate) }
    public var appCount: Int { items.filter { $0.appID != nil }.count }
    public var pageCount: Int { items.count - appCount }

    public init(apps: [AppIdentity], pages: [GuardPage]) {
        var entries: [Item] = []
        var seenApps: Set<String> = []
        for app in apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            guard !app.bundleID.isEmpty, app.bundleID != "com.google.Chrome",
                  !app.bundleID.hasPrefix("com.zixuan.TomatoNotes"), seenApps.insert(app.bundleID).inserted else { continue }
            let candidate = FocusWhitelistCandidate(id: "app-\(entries.count)", kind: .app,
                                                     name: String(app.name.prefix(240)), detail: "当前正在运行的应用")
            entries.append(Item(candidate: candidate, appID: app.bundleID, pageRule: nil))
        }
        var seenPages: Set<String> = []
        for page in pages {
            guard !page.isPrivate, let key = FocusPageRule.pageKey(page.url), seenPages.insert(key).inserted else { continue }
            let title = ActivityPrivacy.clean(page.title, limit: 240)
            let candidate = FocusWhitelistCandidate(id: "page-\(entries.count)", kind: .page,
                                                     name: String((title.isEmpty ? page.host : title).prefix(240)),
                                                     detail: String(page.host.prefix(160)))
            entries.append(Item(candidate: candidate, appID: nil,
                                pageRule: .init(kind: .page, value: key, title: page.title)))
        }
        items = entries
    }

    /// 只有确认按钮调用此方法；AI 无法增加快照之外的 App、网址或网站规则。
    public func adding(_ selectedIDs: Set<String>, to plan: FocusGuardPlan) -> FocusGuardPlan {
        var result = plan
        for item in items where selectedIDs.contains(item.id) {
            if let appID = item.appID { result.appIDs.insert(appID) }
            if let rule = item.pageRule, !result.pages.contains(where: { $0.matches(rule.value) }) {
                result.pages.append(rule)
            }
        }
        return result
    }
}
