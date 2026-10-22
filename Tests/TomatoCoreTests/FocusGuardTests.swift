import Foundation
import Testing
@testable import TomatoCore

struct FocusGuardTests {
    private var settings: FocusGuardSettings {
        var value = FocusGuardSettings(); value.enabled = true; value.remindAfterSeconds = 5; value.graceSeconds = 5
        return value
    }
    @Test func remindsThenAssessesOnceAndChangingTargetRestartsDwell() {
        var watch = GuardDwellMonitor()
        #expect(watch.update(identity: "tab-a", at: 0, settings: settings, mayAssess: true) == .none)
        for time in 1...4 { #expect(watch.update(identity: "tab-a", at: Double(time), settings: settings, mayAssess: true) == .none) }
        #expect(watch.update(identity: "tab-a", at: 5, settings: settings, mayAssess: true) == .remind)
        for time in 6...9 { #expect(watch.update(identity: "tab-a", at: Double(time), settings: settings, mayAssess: true) == .none) }
        #expect(watch.update(identity: "tab-a", at: 10, settings: settings, mayAssess: true) == .assess)
        for time in 11...20 { #expect(watch.update(identity: "tab-a", at: Double(time), settings: settings, mayAssess: true) == .none) }
        #expect(watch.update(identity: "tab-b", at: 21, settings: settings, mayAssess: true) == .none)
        for time in 22...25 { #expect(watch.update(identity: "tab-b", at: Double(time), settings: settings, mayAssess: true) == .none) }
        #expect(watch.update(identity: "tab-b", at: 26, settings: settings, mayAssess: true) == .remind)
    }
    @Test func whitelistingPauseAndSleepDoNotCountTowardEnforcement() {
        var watch = GuardDwellMonitor()
        _ = watch.update(identity: "tab", at: 0, settings: settings, mayAssess: true)
        _ = watch.update(identity: "tab", at: 4, settings: settings, mayAssess: true)
        #expect(watch.update(identity: nil, at: 5, settings: settings, mayAssess: true) == .none)
        #expect(watch.update(identity: "tab", at: 200, settings: settings, mayAssess: true) == .none)
        #expect(watch.update(identity: "tab", at: 201, settings: settings, mayAssess: true) == .none)
        #expect(watch.update(identity: "tab", at: 900, settings: settings, mayAssess: true) == .none)
        #expect(watch.update(identity: "tab", at: 901, settings: settings, mayAssess: true) == .none)
    }

    @Test func applicationWhitelistDoesNotDependOnAIClosePermission() {
        let pages = [FocusPageRule(kind: .site, value: "example.test", title: "课程")]
        let remindersOnly = FocusGuardPlan(goal: "学习", appIDs: ["test.editor"], pages: pages, allowAIClosing: false)
        let aiClosing = FocusGuardPlan(goal: "学习", appIDs: ["test.editor"], pages: pages, allowAIClosing: true)
        #expect(remindersOnly.applicationWhitelistBundleIDs == ["com.google.Chrome", "test.editor"])
        #expect(aiClosing.applicationWhitelistBundleIDs == remindersOnly.applicationWhitelistBundleIDs)
    }
    @Test func reminderOnlyNeverAsksAI() {
        var watch = GuardDwellMonitor()
        var reminders = 0
        for time in 0...30 {
            let action = watch.update(identity: "other-app", at: Double(time), settings: settings, mayAssess: false)
            #expect(action != .assess)
            if action == .remind { reminders += 1 }
        }
        #expect(reminders == 1)
    }
    @Test func siteRulesRespectHostBoundariesAndPageRulesKeepVideoQuery() throws {
        let domain = FocusPageRule(kind: .site, value: "example.com", title: "学习网站")
        #expect(domain.matches("https://course.example.com/lesson"))
        #expect(!domain.matches("https://example.com.attacker.test/"))
        #expect(!domain.matches("https://fakeexample.com/"))
        let key = try #require(FocusPageRule.pageKey("https://www.youtube.com/watch?v=math#chapter1"))
        let page = FocusPageRule(kind: .page, value: key, title: "微积分课程")
        #expect(page.matches("https://www.youtube.com/watch?v=math#chapter2"))
        #expect(!page.matches("https://www.youtube.com/watch?v=game"))
        #expect(FocusPageRule.pageKey("chrome://settings") == nil)
        let plan = FocusGuardPlan(goal: "数学", appIDs: ["com.google.Chrome", "com.apple.Preview"], pages: [page], allowAIClosing: true)
        #expect(!plan.allows(appID: "com.google.Chrome", url: "https://example.net/"))
        #expect(plan.allows(appID: "com.apple.Preview"))
        #expect(plan.allows(appID: "com.zixuan.TomatoNotes.QA"))
    }
    @Test func onlyConfidentUnrelatedVerdictMayClose() {
        #expect(FocusRelevance(verdict: .unrelated, confidence: 0.9, reason: "明确的娱乐页面").permitsClosing)
        for verdict in [FocusRelevance.Verdict.related, .uncertain] {
            #expect(!FocusRelevance(verdict: verdict, confidence: 1, reason: "有学习用途").permitsClosing)
        }
        for confidence in [0.89, -1, 1.1, Double.nan] {
            #expect(!FocusRelevance(verdict: .unrelated, confidence: confidence, reason: "不确定").permitsClosing)
        }
        #expect(!FocusRelevance(verdict: .unrelated, confidence: 1, reason: " \n ").permitsClosing)
    }
    @Test func savedDraftRequiresOptInAndNeverCarriesClosingPermission() throws {
        var settings = FocusGuardSettings()
        #expect(!settings.reuseLastPlan && settings.reusablePlan == nil)
        let plan = FocusGuardPlan(goal: "极限练习", appIDs: [], pages: [.init(kind: .site, value: "example.test", title: "课程")], allowAIClosing: true)
        settings.rememberDraft(plan)
        #expect(settings.lastPages.isEmpty && settings.lastGoal.isEmpty)
        settings.reuseLastPlan = true
        settings.rememberDraft(plan)
        settings.lastAllowAIClosing = true
        let reopened = try JSONDecoder().decode(FocusGuardSettings.self, from: JSONEncoder().encode(settings))
        let draft = try #require(reopened.reusablePlan)
        #expect(draft.goal == plan.goal && draft.pages == plan.pages && !draft.allowAIClosing)
        #expect(!reopened.lastAllowAIClosing)
        settings.reuseLastPlan = false
        settings.rememberDraft(nil)
        #expect(settings.reusablePlan == nil && settings.lastGoal.isEmpty && settings.lastPages.isEmpty)
    }
}
