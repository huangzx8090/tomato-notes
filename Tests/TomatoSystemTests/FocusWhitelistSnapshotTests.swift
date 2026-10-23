import Foundation
import Testing
import TomatoCore
import TomatoSystem

struct FocusWhitelistSnapshotTests {
    private func page(_ url: String, privateWindow: Bool = false) -> GuardPage {
        .init(windowID: "private-window-id", tabID: UUID().uuidString, url: url, title: "课程资料",
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
