import Foundation
import Testing
import TomatoCore
import TomatoSystem

struct FocusWhitelistSnapshotTests {
    private func page(_ url: String, title: String = "课程资料", privateWindow: Bool = false) -> GuardPage {
        .init(windowID: "private-window-id", tabID: UUID().uuidString, url: url, title: title,
              isPrivate: privateWindow, bounds: .init(x: 0, y: 0, width: 1000, height: 700))
    }

    @Test func onlyPublicPagesAndOtherAppsBecomeCandidates() throws {
        let app = AppIdentity(name: "Xcode", bundleID: "com.apple.dt.Xcode")
        let snapshot = FocusWhitelistSnapshot(apps: [app, app, .init(name: "Chrome", bundleID: "com.google.Chrome"),
                                                     .init(name: "番茄小记", bundleID: "com.zixuan.TomatoNotes.QA")],
                                               pages: [page("https://example.test/lesson"), page("https://example.test/lesson#part2"),
                                                       page("https://secret.test/", privateWindow: true), page("file:///Users/me/private"),
                                                       page("chrome://settings")])
        #expect(snapshot.appCount == 1)
        #expect(snapshot.pageCount == 1)
        let json = String(decoding: try JSONEncoder().encode(snapshot.candidates), as: UTF8.self)
        #expect(!json.contains("secret.test"))
        #expect(!json.contains("com.apple.dt.Xcode"))
        #expect(!json.contains("private-window-id"))
        #expect(!json.contains("/lesson"))
    }

    @Test func querySpecificPagesStayDistinctWithoutSendingAddresses() throws {
        let snapshot = FocusWhitelistSnapshot(apps: [], pages: [page("https://user:password@example.test/watch?v=secret1"),
                                                                 page("https://example.test/watch?v=secret2")])
        #expect(snapshot.pageCount == 2)
        let json = String(decoding: try JSONEncoder().encode(snapshot.candidates), as: UTF8.self)
        for secret in ["password", "secret1", "secret2", "/watch", "user:"] { #expect(!json.contains(secret)) }
        let plan = snapshot.adding(Set(snapshot.items.map(\.id)), to: .init(goal: "学习", appIDs: [], pages: [], allowAIClosing: false))
        #expect(plan.pages.count == 2)
        #expect(plan.pages.allSatisfy { $0.kind == .page })
        #expect(!plan.pages[0].value.contains("password"))
        #expect(plan.pages[0].matches("https://example.test/watch?v=secret1"))
        #expect(!plan.pages[0].matches("https://example.test/watch?v=secret2"))
    }

    @Test func titleURLsNeverExposeCredentialsPathsOrQueriesInCandidateJSON() throws {
        let cases = [
            ("https://private-user:fake-password@course.example/private-path?token=secret-query#secret-fragment", "course.example"),
            ("查阅 <https://private-user:fake-password@course.example/private-path?token=secret-query> 与 HTTP://archive.example/secret-path?key=secret-key 阅读",
             "查阅 <course.example> 与 archive.example 阅读"),
            ("https://private-user:fake-password@course.example/" + String(repeating: "private-path", count: 40) + "?token=secret-query", "course.example")
        ]
        for (title, expected) in cases {
            let snapshot = FocusWhitelistSnapshot(apps: [], pages: [page("https://course.example/lesson?video=local-only", title: title)])
            #expect(snapshot.candidates.first?.name == expected)
            let json = String(decoding: try JSONEncoder().encode(snapshot.candidates), as: UTF8.self)
            for secret in ["private-user", "fake-password", "private-path", "secret-query", "secret-fragment", "secret-path", "secret-key", "local-only"] {
                #expect(!json.contains(secret))
            }
            #expect(snapshot.items.first?.pageRule?.title == title)
            #expect(snapshot.items.first?.pageRule?.matches("https://course.example/lesson?video=local-only") == true)
        }
    }

    @Test func preservesNormalTitlesAndCleansURLsBeforeApplyingTitleLimit() {
        let prefix = String(repeating: "课", count: 225)
        let snapshot = FocusWhitelistSnapshot(apps: [], pages: [
            page("https://course.example/normal", title: "  数据库规范化 · 第三范式  "),
            page("https://course.example/long", title: prefix + " https://private-user:fake-password@course.example/private-path?token=secret-query"),
            page("https://course.example/empty", title: " \n ")
        ])
        #expect(snapshot.candidates.map(\.name) == ["数据库规范化 · 第三范式", String((prefix + " course.example").prefix(240)), "course.example"])
        #expect(snapshot.candidates.allSatisfy { $0.name.count <= 240 })
    }

    @Test func confirmationOnlyAddsSelectedKnownTargetsAndKeepsManualChoices() throws {
        let snapshot = FocusWhitelistSnapshot(apps: [.init(name: "Xcode", bundleID: "com.apple.dt.Xcode")],
                                               pages: [page("https://example.test/lesson"), page("https://other.test/lesson")])
        let original = FocusGuardPlan(goal: "写作业", appIDs: ["manual.app"],
                                     pages: [.init(kind: .site, value: "example.test", title: "手选网站")], allowAIClosing: false)
        let pageID = try #require(snapshot.items.first(where: { $0.pageRule?.value.contains("example.test") == true })?.id)
        let result = snapshot.adding([snapshot.items[0].id, pageID, "https://invented.test", "invented.app"], to: original)
        #expect(result.appIDs == ["manual.app", "com.apple.dt.Xcode"])
        #expect(result.pages == original.pages)
        #expect(!result.allowAIClosing)
        #expect(result.goal == original.goal)
        #expect(snapshot.adding([], to: original).appIDs == original.appIDs)
    }
}
