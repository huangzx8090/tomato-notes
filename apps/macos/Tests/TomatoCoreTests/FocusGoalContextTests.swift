import Foundation
import Testing
@testable import TomatoCore

struct FocusGoalContextTests {
    private func tab(_ title: String, url: String, isPrivate: Bool = false) -> GuardPage {
        .init(windowID: "local-window", tabID: "local-tab", url: url, title: title,
              isPrivate: isPrivate, bounds: .init(x: 0, y: 0, width: 1000, height: 700))
    }

    @Test func onlySelectedEntriesAndOrdinaryPagesReachTheContext() throws {
        let rule = FocusPageRule(kind: .site, value: "course.example", title: "课程网站")
        let plan = FocusGuardPlan(goal: "不应发送的旧目标", appIDs: ["local.editor", "com.zixuan.TomatoNotes"], pages: [rule], allowAIClosing: true)
        let context = FocusGoalContext(plan: plan, apps: [
            .init(name: "Xcode", bundleID: "local.editor"), .init(name: "未选应用", bundleID: "local.other"),
            .init(name: "番茄小记", bundleID: "com.zixuan.TomatoNotes")
        ], tabs: [tab("导数练习", url: "https://course.example/lesson?token=local-secret"),
                  tab("未选网页", url: "https://other.example/"),
                  tab("无痕内容", url: "https://course.example/private", isPrivate: true)])
        let encoded = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
        #expect(context.entries.count == 3)
        #expect(encoded.contains("Xcode") && encoded.contains("导数练习") && encoded.contains("course.example"))
        for secret in ["local.editor", "local.other", "local-secret", "/lesson", "旧目标", "未选", "无痕", "local-window", "local-tab", "番茄小记"] {
            #expect(!encoded.contains(secret))
        }
    }

    @Test func cleansURLsInsideTitlesAndKeepsOnlyTheHost() throws {
        let rule = FocusPageRule(kind: .page, value: "https://user:password@course.example/private/path?key=secret#part",
                                 title: "资料 https://user:password@course.example/private/path?key=secret#part")
        let context = FocusGoalContext(plan: .init(goal: "", appIDs: [], pages: [rule], allowAIClosing: false), apps: [])
        #expect(context.entries.first?.name == "资料 course.example")
        #expect(context.entries.first?.site == "course.example")
        let encoded = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
        for secret in ["user", "password", "private", "secret", "part"] { #expect(!encoded.contains(secret)) }
    }

    @Test func contextIsStableAndBoundedWithDuplicateOrLargeLists() throws {
        let pages = (0..<100).map { FocusPageRule(kind: .page, value: "https://course.example/\($0)", title: "课程 \($0)") }
        let first = FocusGoalContext(plan: .init(goal: "", appIDs: [], pages: pages + pages, allowAIClosing: false), apps: [])
        let second = FocusGoalContext(plan: .init(goal: "另一个目标", appIDs: [], pages: pages.reversed(), allowAIClosing: true), apps: [])
        #expect(first == second && first.entries.count == 64 && first.omittedCount == 36)
        #expect(try JSONEncoder().encode(first).count < 25_000)
    }

    @Test func invalidRulesAndUnresolvedAppsDoNotInventContext() {
        let context = FocusGoalContext(plan: .init(goal: "", appIDs: ["missing.app"],
            pages: [.init(kind: .page, value: "file:///private", title: "本机文件")], allowAIClosing: false), apps: [])
        #expect(context.isEmpty)
    }
}
