import Foundation
import Testing
@testable import TomatoCore

struct ReviewTests {
    @Test func scheduleUsesLocalTimeRunsOnceAndCatchesUpAfterRestart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let target = ISO8601DateFormatter().date(from: "2026-10-21T13:30:00Z")!
        var settings = ReviewSettings()
        settings.scheduleEnabled = true
        #expect(ReviewSchedule.dueDay(at: target.addingTimeInterval(-1), settings: settings, lastAttemptDay: nil, calendar: calendar) == nil)
        #expect(ReviewSchedule.dueDay(at: target, settings: settings, lastAttemptDay: nil, calendar: calendar) == "2026-10-21")
        #expect(ReviewSchedule.dueDay(at: target.addingTimeInterval(3600), settings: settings, lastAttemptDay: "2026-10-21", calendar: calendar) == nil)
        #expect(ReviewSchedule.dueDay(at: target.addingTimeInterval(3600), settings: settings, lastAttemptDay: nil, calendar: calendar) == "2026-10-21")
        #expect(ReviewSchedule.dueDay(at: target.addingTimeInterval(86400), settings: settings, lastAttemptDay: "2026-10-21", calendar: calendar) == "2026-10-22")
        settings.hour = 25
        #expect(ReviewSchedule.dueDay(at: target, settings: settings, lastAttemptDay: nil, calendar: calendar) == nil)
    }

    @Test func sessionContextIncludesOnlyItsOwnImagesAndWork() throws {
        var data = AppData()
        let session = FocusSession(startedAt: Date())
        let other = FocusSession(startedAt: Date())
        data.sessions = [session, other]
        var first = WorkRecord(localDay: "2026-10-21", sessionID: session.id)
        first.userText = "完成登录页布局"
        first.images = [WorkImage(name: "登录页.png")]
        var second = WorkRecord(localDay: "2026-10-21", sessionID: other.id)
        second.userText = "另一轮私有内容"
        second.images = [WorkImage(name: "另一轮.png")]
        data.workRecords = [first, second]
        let context = ReviewContextBuilder.build(for: .session(session.id), from: data)
        #expect(context.text.contains(first.userText))
        #expect(!context.text.contains(second.userText))
        #expect(context.images == first.images)
        let digest = context.digest
        data.workRecords[0].userText += "，补充验收结果"
        #expect(ReviewContextBuilder.build(for: .session(session.id), from: data).digest != digest)
    }

    @Test func dailyContextKeepsDayBoundariesAndSeparatesPendingFromCompleted() throws {
        var data = AppData()
        var completed = TodoItem(text: "已做完", localDay: "2026-10-21")
        completed.completedAt = Date()
        data.todos = [completed, TodoItem(text: "还没做", localDay: "2026-10-21"), TodoItem(text: "昨天私有内容", localDay: "2026-10-20")]
        var today = WorkRecord(localDay: "2026-10-21", sessionID: UUID())
        today.userText = "今天的工作"
        var yesterday = WorkRecord(localDay: "2026-10-20", sessionID: UUID())
        yesterday.userText = "昨天的成果"
        data.workRecords = [today, yesterday]
        let context = ReviewContextBuilder.build(for: .day("2026-10-21"), from: data)
        let facts = try #require(try JSONSerialization.jsonObject(with: Data(context.text.utf8)) as? [String: Any])
        #expect(facts["完成的待办"] as? [String] == ["已做完"])
        #expect(facts["尚未完成的待办"] as? [String] == ["还没做"])
        #expect(context.text.contains("今天的工作"))
        #expect(!context.text.contains("昨天"))
        #expect(context.images.isEmpty)
    }

    @Test func schemaOneUpgradesWithBackupAndKeepsNewFieldsOnRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        var legacy = AppData()
        legacy.schemaVersion = 1
        legacy.todos = [TodoItem(text: "旧版用户内容", localDay: "2026-10-21")]
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "workRecords")
        let original = try JSONSerialization.data(withJSONObject: json)
        try original.write(to: repository.fileURL)
        var loaded = try repository.load()
        #expect(loaded.schemaVersion == AppData.currentSchemaVersion)
        #expect(loaded.todos[0].text == "旧版用户内容")
        #expect(loaded.workRecords.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups/schema-v1"), includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: #require(backups.first)) == original)
        loaded.workRecords = [WorkRecord(localDay: "2026-10-21")]
        loaded.lastReviewAttemptDay = "2026-10-21"
        try repository.save(loaded)
        let restored = try repository.load()
        #expect(restored.workRecords.count == 1)
        #expect(restored.lastReviewAttemptDay == "2026-10-21")
        #expect(try Data(contentsOf: backups[0]) == original)
    }
}
