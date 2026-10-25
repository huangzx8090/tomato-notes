import Foundation
import Testing
@testable import TomatoCore

struct FocusWhitelistSelectionTests {
    @Test func removingUnopenedRuleAlsoRemovesCoveringWebsiteAndKeepsOtherOpenPages() throws {
        let closed = page("https://course.example.test/closed", title: "未打开的课程")
        let current = page("https://course.example.test/current", title: "当前课程")
        let other = try exact(page("https://saved.test/notes"))
        let closedRule = try exact(closed)
        let result = FocusWhitelistSelection.removing(closedRule, in: [site("example.test"), closedRule, other],
                                                     availablePages: [current])
        #expect(result == [other, try exact(current)])
        expectPermission(false, for: closed, rules: result)
        expectPermission(true, for: current, rules: result)
        #expect(FocusWhitelistSelection.removing(closedRule, in: result, availablePages: [current]) == result)
    }

    @Test func removingExplicitWebsiteRetainsIndependentlySelectedPages() throws {
        let current = page("https://example.test/lesson")
        let currentRule = try exact(current)
        let broad = site("example.test")
        let result = FocusWhitelistSelection.removing(broad, in: [broad, currentRule], availablePages: [current])
        #expect(result == [currentRule])
        expectPermission(true, for: current, rules: result)
        expectPermission(false, for: page("https://example.test/future"), rules: result)
    }

    private func page(_ url: String, title: String = "课程", tabID: String = "1",
                      isPrivate: Bool = false) -> GuardPage {
        .init(windowID: "window", tabID: tabID, url: url, title: title, isPrivate: isPrivate,
              bounds: .init(x: 0, y: 0, width: 0, height: 0))
    }

    private func exact(_ page: GuardPage, title: String? = nil) throws -> FocusPageRule {
        .init(kind: .page, value: try #require(FocusPageRule.pageKey(page.url)),
              title: title ?? page.title)
    }

    private func site(_ host: String, title: String = "网站") -> FocusPageRule {
        .init(kind: .site, value: host, title: title)
    }

    private var invalidPages: [GuardPage] {
        ["", " \n ", "not a URL", "/relative", "https://", "https:///lesson", "http:///lesson",
         "chrome://example.test/settings", "file:///tmp/lesson", "ftp://example.test/lesson"]
            .map { page($0) }
    }

    private func expectPermission(_ allowed: Bool, for page: GuardPage, rules: [FocusPageRule]) {
        #expect(FocusWhitelistSelection.isAllowed(page, rules: rules) == allowed)
        let plan = FocusGuardPlan(goal: "学习", appIDs: [], pages: rules, allowAIClosing: false)
        #expect(plan.allows(appID: "com.google.Chrome", url: page.url) == allowed)
    }

    @Test func uniquePagesUsesNormalizedURLAndKeepsFirstInputAndDifferentQueries() {
        let first = page(" \nHTTPS://user:password@EXAMPLE.TEST#first\t ", title: "首个页面", tabID: "first")
        let duplicate = page("https://example.test/#second", title: "重复页面", tabID: "duplicate")
        let firstQuery = page("https://example.test/watch?v=one#chapter1")
        let queryDuplicate = page("https://EXAMPLE.TEST/watch?v=one#chapter2", tabID: "other")
        let secondQuery = page("https://example.test/watch?v=two")
        let httpPage = page("http://example.test/")
        let input = [first, duplicate, firstQuery, queryDuplicate, secondQuery, httpPage, first]

        let unique = FocusWhitelistSelection.uniquePages(input)

        #expect(unique == [first, firstQuery, secondQuery, httpPage])
        #expect(FocusWhitelistSelection.uniquePages(unique) == unique)
    }

    @Test func uniquePagesIgnoresPrivateAndInvalidPagesWithoutRequiringCaptureBounds() {
        let normal = page("https://example.test/lesson", title: "普通页面")
        let privateTwin = page(normal.url, title: "无痕页面", isPrivate: true)

        #expect(!normal.mayAssess)
        #expect(FocusWhitelistSelection.uniquePages([privateTwin] + invalidPages + [normal]) == [normal])
        #expect(FocusWhitelistSelection.uniquePages([]).isEmpty)
    }

    @Test func isAllowedUsesExistingExactPageAndSiteMatching() throws {
        let lesson = page("https://docs.example.test/watch?v=one#chapter1")
        let lessonRule = try exact(lesson)
        expectPermission(true, for: page("HTTPS://DOCS.EXAMPLE.TEST/watch?v=one#chapter2"), rules: [lessonRule])
        expectPermission(false, for: page("https://docs.example.test/watch?v=two"), rules: [lessonRule])

        let rules = [site("example.test")]
        for url in ["https://example.test/", "http://docs.example.test/lesson", "https://deep.docs.example.test/lesson"] {
            expectPermission(true, for: page(url), rules: rules)
        }
        for url in ["https://fakeexample.test/", "https://example.test.attacker.test/"] {
            expectPermission(false, for: page(url), rules: rules)
        }
        for invalid in invalidPages + [page(lesson.url, isPrivate: true)] {
            #expect(!FocusWhitelistSelection.isAllowed(invalid, rules: rules + [lessonRule]))
        }
    }

    @Test func singleSelectionAddsOnlyExactPageAndIsIdempotent() throws {
        let target = page("HTTPS://DOCS.EXAMPLE.TEST/watch?v=one#chapter1", title: "课程一")
        let available = [target, page("https://docs.example.test/watch?v=two")]

        let selected = FocusWhitelistSelection.setting(target, allowed: true, in: [], availablePages: available)

        #expect(selected == [try exact(target)])
        expectPermission(true, for: target, rules: selected)
        expectPermission(false, for: available[1], rules: selected)
        expectPermission(false, for: page("https://docs.example.test/future"), rules: selected)
        #expect(FocusWhitelistSelection.setting(target, allowed: true, in: selected, availablePages: available) == selected)
    }

    @Test func selectionDeduplicatesRulesByIDPreservingFirstTitleAndOrder() throws {
        let saved = try exact(page("https://saved.test/unopened"), title: "原始标题")
        let savedDuplicate = FocusPageRule(kind: .page, value: saved.value, title: "重复标题")
        let unrelatedSite = site("other.test", title: "保留网站")
        let duplicateSite = site("other.test", title: "重复网站")
        let target = page("https://example.test/lesson")
        let rules = [saved, unrelatedSite, savedDuplicate, duplicateSite]

        let selected = FocusWhitelistSelection.setting(target, allowed: true, in: rules, availablePages: [])

        #expect(selected == [saved, unrelatedSite, try exact(target)])
        #expect(Set(selected.map(\.id)).count == selected.count)
        #expect(FocusWhitelistSelection.setting(target, allowed: true, in: selected, availablePages: []) == selected)
    }

    @Test func selectingPageAlreadyAllowedBySiteDoesNotAddRedundantRules() {
        let rules = [site("example.test")]
        let target = page("https://docs.example.test/lesson")

        #expect(FocusWhitelistSelection.setting(target, allowed: true, in: rules, availablePages: [target]) == rules)
    }

    @Test func batchSelectionUsesOnlyFilteredSubsetWithoutExpandingWebsite() throws {
        let first = page("https://docs.example.test/lesson?unit=one", title: "第一课")
        let second = page("https://video.example.test/watch?v=two", title: "第二课")
        let hidden = page("https://docs.example.test/lesson?unit=hidden")
        let duplicate = page(first.url + "#section", title: "重复", tabID: "duplicate")
        let privatePage = page("https://docs.example.test/private", isPrivate: true)
        let available = [first, hidden, second, privatePage]
        let filtered = [second, first, duplicate, privatePage] + invalidPages

        let selected = FocusWhitelistSelection.setting(filtered, allowed: true, in: [], availablePages: available)

        #expect(selected == [try exact(second), try exact(first)])
        expectPermission(true, for: first, rules: selected)
        expectPermission(true, for: second, rules: selected)
        expectPermission(false, for: hidden, rules: selected)
        expectPermission(false, for: page("https://video.example.test/future"), rules: selected)
        #expect(FocusWhitelistSelection.setting(filtered, allowed: true, in: selected, availablePages: available) == selected)
    }

    @Test func cancellingExactPageRemovesEveryMatchingDuplicateAndKeepsOtherQueries() throws {
        let target = page("https://example.test/watch?v=one#chapter2")
        let first = try exact(target, title: "首个标题")
        let duplicate = try exact(target, title: "另一个标题")
        let otherQuery = try exact(page("https://example.test/watch?v=two"))
        let unopened = try exact(page("https://saved.test/unopened"))
        let rules = [first, otherQuery, duplicate, unopened, first]

        let remaining = FocusWhitelistSelection.setting(target, allowed: false, in: rules, availablePages: [target])

        #expect(remaining == [otherQuery, unopened])
        #expect(!remaining.contains { $0.matches(target.url) })
        expectPermission(false, for: target, rules: remaining)
        expectPermission(true, for: page(otherQuery.value), rules: remaining)
        #expect(FocusWhitelistSelection.setting(target, allowed: false, in: remaining, availablePages: [target]) == remaining)
    }

    @Test func cancellingAlreadyDisallowedPageDoesNotAddSnapshotPages() throws {
        let existing = try exact(page("https://saved.test/unopened"))
        let target = page("https://example.test/unchecked")
        let available = [target, page("https://example.test/other"), page("https://other.test/lesson")]

        #expect(FocusWhitelistSelection.setting(target, allowed: false, in: [existing], availablePages: available) == [existing])
    }

    @Test func cancellingSiteConvertsOtherSnapshotPagesToExactRulesInSnapshotOrder() throws {
        let target = page("https://example.test/watch?v=one#chapter1")
        let targetDuplicate = page("https://EXAMPLE.TEST/watch?v=one#chapter2", tabID: "duplicate")
        let second = page("https://example.test/watch?v=two", title: "第二课")
        let third = page("https://example.test/notes", title: "笔记")
        let thirdDuplicate = page(third.url + "#part", title: "重复笔记", tabID: "other")
        let privatePage = page("https://example.test/private", isPrivate: true)
        let available = [targetDuplicate, second, third, target, thirdDuplicate, privatePage] + invalidPages

        let remaining = FocusWhitelistSelection.setting(target, allowed: false, in: [site("example.test")], availablePages: available)

        #expect(remaining == [try exact(second), try exact(third)])
        expectPermission(false, for: target, rules: remaining)
        expectPermission(false, for: targetDuplicate, rules: remaining)
        expectPermission(true, for: second, rules: remaining)
        expectPermission(true, for: third, rules: remaining)
        expectPermission(false, for: page("https://example.test/private"), rules: remaining)
        expectPermission(false, for: page("https://example.test/future"), rules: remaining)
        #expect(FocusWhitelistSelection.setting(target, allowed: false, in: remaining, availablePages: available) == remaining)
    }

    @Test func cancellingParentSitePreservesPagesAcrossSiblingAndNestedSubdomains() throws {
        let target = page("https://course.example.test/lesson")
        let root = page("https://example.test/overview")
        let sibling = page("https://docs.example.test/reference")
        let nested = page("https://deep.docs.example.test/reference")
        let unrelated = page("https://fakeexample.test/lesson")
        let available = [root, target, sibling, nested, unrelated]

        let remaining = FocusWhitelistSelection.setting(target, allowed: false, in: [site("example.test")], availablePages: available)

        #expect(remaining == [try exact(root), try exact(sibling), try exact(nested)])
        expectPermission(false, for: target, rules: remaining)
        for kept in [root, sibling, nested] { expectPermission(true, for: kept, rules: remaining) }
        expectPermission(false, for: unrelated, rules: remaining)
        expectPermission(false, for: page("https://new.example.test/future"), rules: remaining)
    }

    @Test func cancellingOverlappingSitesRemovesAllCoveringRulesAndKeepsUnrelatedSite() throws {
        let target = page("https://deep.course.example.test/lesson")
        let root = page("https://example.test/overview")
        let course = page("https://course.example.test/notes")
        let deep = page("https://deep.course.example.test/notes")
        let sibling = page("https://docs.example.test/reference")
        let siblingSite = site("docs.example.test")
        let saved = try exact(page("https://saved.test/unopened"))
        let rules = [site("example.test"), siblingSite, site("course.example.test"), saved,
                     site("deep.course.example.test"), try exact(target),
                     site("example.test", title: "重复父域"), try exact(target, title: "重复目标")]

        let remaining = FocusWhitelistSelection.setting(target, allowed: false, in: rules,
                                                         availablePages: [target, root, course, sibling, deep])

        #expect(remaining == [siblingSite, saved, try exact(root), try exact(course), try exact(deep)])
        #expect(!remaining.contains { $0.matches(target.url) })
        expectPermission(false, for: target, rules: remaining)
        for kept in [root, course, sibling, deep] { expectPermission(true, for: kept, rules: remaining) }
        expectPermission(false, for: page("https://deep.course.example.test/future"), rules: remaining)
    }

    @Test func batchCancellationExcludesEntireBatchAndIsIndependentOfTargetOrder() throws {
        let first = page("https://course.example.test/watch?v=one")
        let second = page("https://docs.example.test/watch?v=two")
        let kept = page("https://docs.example.test/watch?v=three")
        let duplicate = page(second.url + "#chapter", tabID: "duplicate")
        let available = [second, kept, first, duplicate]
        let rules = [site("example.test"), site("docs.example.test"), try exact(second)]

        let remaining = FocusWhitelistSelection.setting([first, second, duplicate], allowed: false, in: rules, availablePages: available)

        #expect(remaining == [try exact(kept)])
        expectPermission(false, for: first, rules: remaining)
        expectPermission(false, for: second, rules: remaining)
        expectPermission(true, for: kept, rules: remaining)
        #expect(FocusWhitelistSelection.setting([second, first], allowed: false, in: rules, availablePages: available) == remaining)
        #expect(FocusWhitelistSelection.setting([first, second], allowed: false, in: remaining, availablePages: available) == remaining)
    }

    @Test func sequentialCancellationDoesNotRestorePreviouslyCancelledPage() throws {
        let first = page("https://example.test/first")
        let second = page("https://example.test/second")
        let kept = page("https://example.test/kept")
        let available = [first, second, kept]
        let rules = [site("example.test")]

        let afterFirst = FocusWhitelistSelection.setting(first, allowed: false, in: rules, availablePages: available)
        let afterSecond = FocusWhitelistSelection.setting(second, allowed: false, in: afterFirst, availablePages: available)

        #expect(afterFirst == [try exact(second), try exact(kept)])
        #expect(afterSecond == [try exact(kept)])
        expectPermission(false, for: first, rules: afterSecond)
        expectPermission(false, for: second, rules: afterSecond)
        expectPermission(true, for: kept, rules: afterSecond)
        #expect(FocusWhitelistSelection.setting([first, second], allowed: false, in: rules, availablePages: available) == afterSecond)
    }

    @Test func cancellingTargetMissingFromSnapshotStillRemovesItsRules() throws {
        let target = page("https://course.example.test/closed")
        let kept = page("https://docs.example.test/open")
        let rules = [site("example.test"), try exact(target)]

        let remaining = FocusWhitelistSelection.setting(target, allowed: false, in: rules, availablePages: [kept])

        #expect(remaining == [try exact(kept)])
        expectPermission(false, for: target, rules: remaining)
        expectPermission(true, for: kept, rules: remaining)
    }

    @Test func cancellationPreservesUnrelatedAndUnopenedExactRulesAndTheirOrder() throws {
        let target = page("https://example.test/target")
        let opened = page("https://example.test/opened")
        let unopened = try exact(page("https://example.test/unopened"), title: "尚未打开")
        let unrelatedSite = site("other.test")
        let unrelatedPage = try exact(page("https://saved.test/unopened"))
        let nonmatchingLegacy = FocusPageRule(kind: .page, value: "https://example.test/target#legacy", title: "原值保留")
        let existingOpened = try exact(opened, title: "已有标题")
        let rules = [unopened, site("example.test"), unrelatedSite, unrelatedPage, nonmatchingLegacy,
                     existingOpened, try exact(opened, title: "重复标题")]

        let remaining = FocusWhitelistSelection.setting(target, allowed: false, in: rules,
                                                         availablePages: [opened, target, page("https://outside.test/unchecked")])

        #expect(remaining == [unopened, unrelatedSite, unrelatedPage, nonmatchingLegacy, existingOpened])
        expectPermission(false, for: target, rules: remaining)
        expectPermission(true, for: page(unopened.value), rules: remaining)
        expectPermission(true, for: opened, rules: remaining)
        #expect(Set(remaining.map(\.id)).count == remaining.count)
    }

    @Test func invalidPrivateAndEmptyInputsLeaveRulesUnchangedIncludingDuplicates() throws {
        let normal = page("https://example.test/lesson")
        let rules = [site("example.test"), try exact(normal), site("example.test", title: "保留重复")]
        let ignored = invalidPages + [page(normal.url, isPrivate: true)]

        for allowed in [true, false] {
            for invalid in ignored {
                #expect(FocusWhitelistSelection.setting(invalid, allowed: allowed, in: rules, availablePages: [normal]) == rules)
            }
            #expect(FocusWhitelistSelection.setting(ignored, allowed: allowed, in: rules, availablePages: [normal]) == rules)
            #expect(FocusWhitelistSelection.setting([], allowed: allowed, in: rules, availablePages: [normal]) == rules)
        }
    }

    @Test func mixedCancellationIgnoresPrivateTargetsAndDoesNotRestorePrivateSnapshotPages() throws {
        let target = page("https://example.test/target")
        let kept = page("https://example.test/kept", title: "普通页面")
        let privateTwin = page(kept.url, title: "无痕页面", isPrivate: true)
        let privateOnly = page("https://example.test/private-only", isPrivate: true)
        let ignored = invalidPages + [privateTwin, privateOnly]

        let remaining = FocusWhitelistSelection.setting([target] + ignored, allowed: false,
                                                         in: [site("example.test")],
                                                         availablePages: [target, privateTwin, kept, privateOnly] + invalidPages)

        #expect(remaining == [try exact(kept)])
        expectPermission(false, for: target, rules: remaining)
        expectPermission(true, for: kept, rules: remaining)
        expectPermission(false, for: page(privateOnly.url), rules: remaining)
    }
}
