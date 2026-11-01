import Foundation
import Testing
@testable import TomatoCore

struct FocusWhitelistMemoryTests {
    @Test func titleKeywordsMatchDifferentURLsWithoutAllowingWholeVideoSite() {
        var plan = FocusGuardPlan(goal: "学习", appIDs: [], pages: [], allowAIClosing: false)
        plan.titleKeywords = ["小林 coding", "  "]
        #expect(plan.allows(appID: "com.google.Chrome", url: "https://example.test/mysql", title: "MySQL | 小林 Coding"))
        #expect(plan.allows(appID: "com.google.Chrome", url: "https://example.test/redis?chapter=2", title: "小林 coding - Redis"))
        #expect(!plan.allows(appID: "com.google.Chrome", url: "https://example.test/game", title: "游戏直播"))
        #expect(!plan.allows(appID: "com.google.Chrome", url: "https://example.test/小林 coding", title: "游戏"))
        #expect(!plan.allows(appID: "com.google.Chrome", url: "chrome://settings", title: "小林 coding"))
        #expect(!plan.allows(appID: "game.app", title: "小林 coding"))
        #expect(plan.applicationWhitelistBundleIDs == ["com.google.Chrome"])
    }

    @Test func historyRoundTripsWithLegacyRulesAndUnknownFields() throws {
        var settings = FocusGuardSettings()
        settings.favoritePages = [.init(kind: .site, value: "example.test", title: "旧网站")]
        var memory = FocusWhitelistMemory()
        memory.keywords = [FocusWhitelistMemory.normalized("  小林 Coding  ")]
        memory.record(["app:editor", "keyword:小林 coding"])
        memory.record(["keyword:小林 coding"])
        settings.whitelistMemory = memory
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(FocusGuardSettings.self, from: data)
        #expect(restored.whitelistMemory.keywords == ["小林 coding"])
        #expect(restored.whitelistMemory.counts["keyword:小林 coding"] == 2)
        #expect(restored.whitelistMemory.precedes("keyword:小林 coding", "app:editor"))
        #expect(restored.favoritePages == settings.favoritePages)
        #expect(!restored.lastAllowAIClosing)
        // 未识别扩展字段的旧端仍可保留对象，既有 page/site 枚举没有变化。
        #expect(restored.extraFields["macOSWhitelistMemory"] != nil)
        #expect(try JSONDecoder().decode(FocusGuardSettings.self, from: Data("{}".utf8)).whitelistMemory.keywords.isEmpty)
    }
}
