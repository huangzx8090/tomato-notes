import Foundation

/// 白名单勾选的纯规则操作；URL 规范化和匹配沿用 FocusPageRule。
public enum FocusWhitelistSelection {
    /// 只保留有效的普通 HTTP(S) 页面，同一 pageKey 保留首次出现的页面。
    public static func uniquePages(_ pages: [GuardPage]) -> [GuardPage] {
        var seen: Set<String> = []
        return pages.filter { page in
            guard let key = selectableKey(page) else { return false }
            return seen.insert(key).inserted
        }
    }

    public static func isAllowed(_ page: GuardPage, rules: [FocusPageRule]) -> Bool {
        guard selectableKey(page) != nil else { return false }
        return rules.contains { $0.matches(page.url) }
    }

    public static func setting(_ page: GuardPage, allowed: Bool, in rules: [FocusPageRule],
                               availablePages: [GuardPage]) -> [FocusPageRule] {
        setting([page], allowed: allowed, in: rules, availablePages: availablePages)
    }

    /// availablePages 应传入完整快照，使取消网站规则后仍可保留其它当前页面的许可。
    /// 原规则按 id 保留首项和相对顺序，新精确页按目标或快照顺序追加。
    public static func setting(_ pages: [GuardPage], allowed: Bool, in rules: [FocusPageRule],
                               availablePages: [GuardPage]) -> [FocusPageRule] {
        let targets = uniquePages(pages)
        guard !targets.isEmpty else { return rules }

        guard allowed else {
            return excluding(Set(targets.compactMap(selectableKey)), in: rules, availablePages: availablePages)
        }
        return adding(targets, to: uniqueRules(rules))
    }

    /// 已关闭页面也必须排除覆盖它的网站规则，不能只删除精确页的 id。
    public static func removing(_ rule: FocusPageRule, in rules: [FocusPageRule],
                                availablePages: [GuardPage]) -> [FocusPageRule] {
        let remaining = uniqueRules(rules.filter { $0.id != rule.id })
        guard rule.kind == .page, let key = FocusPageRule.pageKey(rule.value),
              let host = URLComponents(string: key)?.host, !host.isEmpty else { return remaining }
        return excluding([key], in: remaining, availablePages: availablePages)
    }

    private static func excluding(_ keys: Set<String>, in rules: [FocusPageRule],
                                  availablePages: [GuardPage]) -> [FocusPageRule] {
        var result = uniqueRules(rules)
        let removedSites = result.filter { rule in rule.kind == .site && keys.contains { rule.matches($0) } }
        result.removeAll { rule in keys.contains { rule.matches($0) } }
        // 一次排除整批目标，再补回被移除网站规则覆盖的其它页面，避免恢复已取消项。
        let retainedPages = uniquePages(availablePages).filter { page in
            guard let key = selectableKey(page), !keys.contains(key) else { return false }
            return removedSites.contains { $0.matches(key) }
        }
        return adding(retainedPages, to: result)
    }

    private static func adding(_ pages: [GuardPage], to rules: [FocusPageRule]) -> [FocusPageRule] {
        var result = rules
        for page in pages {
            guard !isAllowed(page, rules: result), let key = selectableKey(page) else { continue }
            result.append(.init(kind: .page, value: key, title: page.title))
        }
        return result
    }

    private static func uniqueRules(_ rules: [FocusPageRule]) -> [FocusPageRule] {
        var ids: Set<String> = []
        return rules.filter { ids.insert($0.id).inserted }
    }

    private static func selectableKey(_ page: GuardPage) -> String? {
        guard !page.isPrivate, let key = FocusPageRule.pageKey(page.url),
              let host = URLComponents(string: key)?.host, !host.isEmpty else { return nil }
        return key
    }
}
