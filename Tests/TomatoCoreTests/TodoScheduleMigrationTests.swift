import Foundation
import Testing
@testable import TomatoCore

struct TodoScheduleMigrationTests {
    @Test func oldTodoDecodesWithOnlyItsOriginalScheduledDay() throws {
        var todo = TodoItem(text: "旧格式事项", localDay: "2026-10-21")
        todo.completedAt = ISO8601DateFormatter().date(from: "2026-10-21T08:00:00+08:00")!
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(todo)) as? [String: Any])
        json.removeValue(forKey: "scheduledDays")
        json.removeValue(forKey: "completedLocalDay")

        let restored = try JSONDecoder().decode(TodoItem.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.scheduledDays == ["2026-10-21"])
        #expect(restored.effectiveScheduledDay == "2026-10-21")
        #expect(restored.isScheduled(on: "2026-10-21"))
        #expect(restored.completionDay != nil)
    }

    @Test func carriedTodoRemainsInEveryHistoricalDayButCountsCompletionOnce() throws {
        var todo = TodoItem(text: "复习网络", localDay: "2026-10-21")
        todo.scheduledDays.append(contentsOf: ["2026-10-22", "2026-10-23"])
        todo.completedAt = ISO8601DateFormatter().date(from: "2026-10-23T09:30:00+08:00")!
        todo.completedLocalDay = "2026-10-23"
        var data = AppData()
        data.todos = [todo]

        for day in ["2026-10-21", "2026-10-22", "2026-10-23"] {
            let summary = DailySummary.build(day: day, from: data)
            #expect(summary.todos.map(\.id) == [todo.id])
            #expect(summary.completedTodos.map(\.id) == (day == "2026-10-23" ? [todo.id] : []))
        }
        let facts = try #require(try JSONSerialization.jsonObject(
            with: Data(ReviewContextBuilder.build(for: .day("2026-10-21"), from: data).text.utf8)
        ) as? [String: Any])
        let dayTodos = try #require(facts["当天安排的待办"] as? [[String: String]])
        #expect(dayTodos.first?["状态"] == "当时未完成，后续于 2026-10-23 完成")
        #expect(facts["完成的待办"] as? [String] == [])
    }

    @Test func carriedCompletionBelongsToItsActualDayAndOneFocusRound() throws {
        let firstID = UUID()
        let secondID = UUID()
        let todoID = UUID()
        let firstStart = ISO8601DateFormatter().date(from: "2026-10-21T08:00:00+08:00")!
        let secondStart = ISO8601DateFormatter().date(from: "2026-10-23T08:00:00+08:00")!
        let completedAt = secondStart.addingTimeInterval(30)
        let first = FocusSession(id: firstID, startedAt: firstStart, goal: "第一轮")
        let second = FocusSession(id: secondID, startedAt: secondStart, goal: "第二轮")
        let firstInterval = FocusInterval(sessionID: firstID, startedAt: firstStart,
                                          endedAt: firstStart.addingTimeInterval(60), localDay: "2026-10-21",
                                          timeZoneID: "Asia/Shanghai", seconds: 60)
        let secondInterval = FocusInterval(sessionID: secondID, startedAt: secondStart,
                                           endedAt: secondStart.addingTimeInterval(60), localDay: "2026-10-23",
                                           timeZoneID: "Asia/Shanghai", seconds: 60)
        var todo = TodoItem(text: "跨日结转后完成", localDay: "2026-10-21", id: todoID)
        todo.scheduledDays.append(contentsOf: ["2026-10-22", "2026-10-23"])
        todo.completedAt = completedAt
        todo.completedLocalDay = "2026-10-23"
        var data = AppData()
        data.sessions = [first, second]
        data.intervals = [firstInterval, secondInterval]
        data.todos = [todo]

        #expect(DailySummary.build(day: "2026-10-21", from: data).completedTodos.isEmpty)
        #expect(DailySummary.build(day: "2026-10-22", from: data).completedTodos.isEmpty)
        #expect(DailySummary.build(day: "2026-10-23", from: data).completedTodos.map(\.id) == [todoID])
        #expect(SessionProgress.build(sessionID: firstID, from: data)?.completedTodos.isEmpty == true)
        #expect(SessionProgress.build(sessionID: secondID, from: data)?.completedTodos.map(\.id) == [todoID])
    }

    @Test func mergeKeepsScheduleHistoryAndRejectsConflictingCopies() throws {
        var item = TodoItem(text: "整理笔记", localDay: "2026-10-21")
        item.scheduledDays.append("2026-10-22")
        var primary = AppData()
        primary.todos = [item]
        var sameCopy = AppData()
        sameCopy.todos = [item]
        let merged = try DataMerger.merge(primary: primary, importing: [sameCopy])
        #expect(merged.todos.count == 1)
        #expect(merged.todos[0].scheduledDays == ["2026-10-21", "2026-10-22"])

        var ambiguousCopy = item
        ambiguousCopy.scheduledDays.append("2026-10-23")
        var conflicting = AppData()
        conflicting.todos = [ambiguousCopy]
        #expect(throws: DataMergeError.self) {
            try DataMerger.merge(primary: primary, importing: [conflicting])
        }
    }
}
