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
        #expect(futureSetting["keep"] as? Bool == true)
    }
}
