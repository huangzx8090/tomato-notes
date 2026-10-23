import Foundation
import Testing
@testable import TomatoCore

struct HistoryActivityIntegrationTests {
    private func fixture() throws -> AppData {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-23T09:00:00+08:00"))
        var data = AppData()
        data.settings.activityRecording.enabled = true
        var engine = TimerEngine(data: data)
        engine.start(at: start, goal: "整理网络笔记")
        _ = engine.advance(seconds: 120, endingAt: start.addingTimeInterval(120), app: nil, recordingEnabled: false)
        data = engine.data
        var todo = TodoItem(text: "结转后完成的事项", localDay: "2026-10-21")
        todo.scheduledDays = ["2026-10-21", "2026-10-22", "2026-10-23"]
        todo.completedAt = start.addingTimeInterval(60)
        todo.completedLocalDay = "2026-10-23"
        data.todos = [todo]
        ActivityRecorder.recordTodo(todo, at: start.addingTimeInterval(60), in: &data)
        var record = WorkRecord(localDay: "2026-10-23", sessionID: data.sessions[0].id)
        record.automaticRecordingUsed = true
        record.titleOverride = "网络复习"
        record.activityTopic = .init(title: "网络复习", confidence: 1,
                                     evidenceIDs: data.focusActivities.map(\.id), model: "用户命名")
        data.workRecords = [record]
        engine.replaceData(data)
        engine.endEarly(at: start.addingTimeInterval(120))
        return engine.data
    }

    @Test func oneSchemaPreservesBothActivityAndScheduleHistoryThroughReloadAndMerge() throws {
        let data = try fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        try repository.save(data)
        let restored = try repository.load()
        let merged = try DataMerger.merge(primary: restored, importing: [data])
        #expect(merged.schemaVersion == AppData.currentSchemaVersion)
        #expect(merged.settings.activityRecording.enabled)
        #expect(merged.todos.count == 1)
        #expect(merged.todos[0].localDay == "2026-10-21")
        #expect(merged.todos[0].scheduledDays == data.todos[0].scheduledDays)
        #expect(merged.todos[0].completionDay == "2026-10-23")
        #expect(merged.focusActivities == data.focusActivities)
        #expect(merged.workRecords[0].titleOverride == "网络复习")
        #expect(merged.workRecords[0].activityTopic?.evidenceIDs == data.focusActivities.map(\.id))
        #expect(HistorySearchIndex(data: merged).search(query: "结转后完成").count == 1)
    }

    @Test func carriedTodoContextKeepsHistoricalStatusAndHonorsActivitySourceExclusions() throws {
        var data = try fixture()
        let historical = ReviewContextBuilder.build(for: .day("2026-10-22"), from: data)
        #expect(historical.text.contains("当时未完成，后续于 2026-10-23 完成"))
        data.settings.activityRecording.notesEnabled = false
        var facts = try #require(try JSONSerialization.jsonObject(with: Data(
            ReviewContextBuilder.build(for: .day("2026-10-23"), from: data).text.utf8
        )) as? [String: Any])
        #expect((facts["完成的待办"] as? [String])?.isEmpty == true)
        #expect((facts["当天安排的待办"] as? [[String: String]])?.isEmpty == true)
        data.settings.activityRecording.notesEnabled = true
        data.workRecords[0].excludedActivityKeys = ["todoCompleted|\(data.todos[0].id.uuidString)"]
        facts = try #require(try JSONSerialization.jsonObject(with: Data(
            ReviewContextBuilder.build(for: .day("2026-10-23"), from: data).text.utf8
        )) as? [String: Any])
        #expect((facts["完成的待办"] as? [String])?.isEmpty == true)
        #expect((facts["当天安排的待办"] as? [[String: String]])?.isEmpty == true)
    }

    @Test func midnightCompletionAtAdjacentRoundBoundaryIsCountedOnlyOnce() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-22T23:59:00+08:00"))
        let midnight = start.addingTimeInterval(60)
        var first = FocusSession(startedAt: start)
        first.endedAt = midnight
        first.endedLocalDay = "2026-10-22"
        var second = FocusSession(startedAt: midnight)
        second.endedAt = midnight.addingTimeInterval(60)
        second.endedLocalDay = "2026-10-23"
        var todo = TodoItem(text: "午夜完成", localDay: "2026-10-21")
        todo.scheduledDays += ["2026-10-22", "2026-10-23"]
        todo.completedAt = midnight
        todo.completedLocalDay = "2026-10-23"
        var data = AppData()
        data.sessions = [first, second]
        data.todos = [todo]
        data.intervals = [
            .init(sessionID: first.id, startedAt: start, endedAt: midnight, localDay: "2026-10-22",
                  timeZoneID: "Asia/Shanghai", seconds: 60),
            .init(sessionID: second.id, startedAt: midnight, endedAt: midnight.addingTimeInterval(60),
                  localDay: "2026-10-23", timeZoneID: "Asia/Shanghai", seconds: 60)
        ]
        #expect(SessionProgress.build(sessionID: first.id, from: data)?.completedTodos.isEmpty == true)
        #expect(SessionProgress.build(sessionID: second.id, from: data)?.completedTodos.map(\.id) == [todo.id])
        #expect(DailySummary.build(day: "2026-10-22", from: data).completedTodos.isEmpty)
        #expect(DailySummary.build(day: "2026-10-23", from: data).completedTodos.map(\.id) == [todo.id])
        // 同一轮跨午夜时，保存的完成归属日也不能被前一天分段的结束边界吸收。
        data.intervals[1].sessionID = first.id
        #expect(SessionProgress.build(sessionID: first.id, from: data, day: "2026-10-22")?.completedTodos.isEmpty == true)
        #expect(SessionProgress.build(sessionID: first.id, from: data, day: "2026-10-23")?.completedTodos.map(\.id) == [todo.id])
    }
}
