import Foundation
import Testing
@testable import TomatoCore

@Suite("WindowsCompatibilityTests")
struct WindowsCompatibilityTests {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Compatibility/data-contract-v4.json")
    }

    @Test func readsSharedFixtureWithoutChangingMeaning() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fixtureURL))
        #expect(data.schemaVersion == 4)
        #expect(data.timer.updatedAt == Date(timeIntervalSinceReferenceDate: 0))
        #expect(data.sessions.first?.goal == "跨端资料兼容")
        #expect(data.todos.first?.completionDay == "2001-01-01")
        #expect(data.notes.first?.text.contains("👍") == true)
        #expect(data.workRecords.first?.images.first?.fileName == "A51C4E5B-0AA4-467D-A615-36B6D5327E68.jpg")
    }

    @Test func macOSRoundTripPreservesWindowsAndFutureFields() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fixtureURL))
        let encoded = try JSONEncoder().encode(data)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let settings = try #require(object["settings"] as? [String: Any])
        let guardSettings = try #require(settings["focusGuard"] as? [String: Any])
        let futureSetting = try #require(settings["futureSettingFromEitherPlatform"] as? [String: Any])
        #expect(object["futureRootField"] as? String == "must-survive-roundtrip")
        #expect(guardSettings["macOSOnlyRule"] as? String == "preserve-me")
        #expect(guardSettings["aiRelevance"] as? Bool == true)
        #expect(futureSetting["keep"] as? Bool == true)
    }

    @Test func aiRelevanceFieldRoundTripsAndDefaultsOff() throws {
        // Windows 写下的 aiRelevance 现在是已知字段：往返后值不变，不再依赖 extraFields 保留。
        let withField = """
        {"aiRelevance": true, "unknownAfter": "keep"}
        """
        let opened = try JSONDecoder().decode(FocusGuardSettings.self, from: Data(withField.utf8))
        #expect(opened.aiRelevance == true)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(opened)) as? [String: Any]
        #expect(saved?["aiRelevance"] as? Bool == true)
        // 旧资料没写这个字段时按关闭处理，老资料打开不会意外开始 AI 判定。
        #expect(try JSONDecoder().decode(FocusGuardSettings.self, from: Data("{}".utf8)).aiRelevance == false)
        #expect(FocusGuardSettings().aiRelevance == false)
    }
}
