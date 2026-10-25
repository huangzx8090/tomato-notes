import Foundation
import Testing
@testable import TomatoCore

struct TodoCarryoverTests {
    @Test func continuousCarryoverRetainsEveryScheduledDayAndStableID() {
        let originalID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let original = TodoItem(text: "连续事项", localDay: "2026-10-20", createdAt: createdAt, id: originalID)
        var todos = [original]

        #expect(TodoCarryover.schedule(originalID, on: "2026-10-22", in: &todos))
        #expect(TodoCarryover.candidates(in: todos, today: "2026-10-23").map(\.id) == [originalID])
        #expect(TodoCarryover.schedule(originalID, on: "2026-10-23", in: &todos))

        #expect(todos.count == 1)
        #expect(todos[0].id == originalID)
        #expect(todos[0].createdAt == createdAt)
        #expect(todos[0].localDay == "2026-10-20")
        #expect(todos[0].text == "连续事项")
        #expect(todos[0].scheduledDays == ["2026-10-20", "2026-10-22", "2026-10-23"])
        #expect(todos[0].isScheduled(on: "2026-10-20"))
        #expect(todos[0].isScheduled(on: "2026-10-22"))
        #expect(todos[0].isScheduled(on: "2026-10-23"))
        #expect(Set(todos.map(\.id)).count == todos.count)
    }

    @Test func repeatedScheduleIsIdempotentAndDoesNotChangeOtherFields() {
        let id = UUID()
        var todo = TodoItem(text: "原文", localDay: "2026-10-20", createdAt: Date(timeIntervalSince1970: 20), id: id)
        todo.completedLocalDay = nil
        var todos = [todo]

        #expect(TodoCarryover.schedule(id, on: "2026-10-22", in: &todos))
        let firstResult = todos[0]
        #expect(!TodoCarryover.schedule(id, on: "2026-10-22", in: &todos))

        #expect(todos.count == 1)
        #expect(todos[0].id == firstResult.id)
        #expect(todos[0].createdAt == firstResult.createdAt)
        #expect(todos[0].localDay == firstResult.localDay)
        #expect(todos[0].text == firstResult.text)
        #expect(todos[0].completedAt == firstResult.completedAt)
        #expect(todos[0].completedLocalDay == firstResult.completedLocalDay)
        #expect(todos[0].scheduledDays == ["2026-10-20", "2026-10-22"])
    }

    @Test func batchSchedulingCanArrangeEachSelectedTaskWithoutCopies() {
        let first = TodoItem(text: "第一项", localDay: "2026-10-20", id: UUID())
        let second = TodoItem(text: "第二项", localDay: "2026-10-21", id: UUID())
        var todos = [first, second]
        let selected = [first.id, second.id]

        let changed = TodoCarryover.schedule(Set(selected), on: "2026-10-22", in: &todos)

        #expect(changed == selected)
        #expect(todos.count == 2)
        #expect(Set(todos.map(\.id)) == Set(selected))
        #expect(todos.allSatisfy { $0.isScheduled(on: "2026-10-22") })
        #expect(TodoCarryover.schedule(Set(selected), on: "2026-10-22", in: &todos).isEmpty)
    }

    @Test func completedAndFutureTasksAreNotCarryoverCandidates() {
        let past = TodoItem(text: "过去", localDay: "2026-10-20")
        var completed = TodoItem(text: "完成", localDay: "2026-10-19")
        completed.completedAt = Date(timeIntervalSince1970: 30)
        completed.completedLocalDay = "2026-10-20"
        var future = TodoItem(text: "未来", localDay: "2026-10-24")
        future.scheduledDays = ["2026-10-20"]
        var todos = [future, completed, past]

        #expect(TodoCarryover.candidates(in: todos, today: "2026-10-22").map(\.id) == [past.id])
        #expect(!TodoCarryover.schedule(completed.id, on: "2026-10-22", in: &todos))
        #expect(!TodoCarryover.schedule(future.id, on: "2026-10-22", in: &todos))
        #expect(todos.first(where: { $0.id == completed.id })?.isScheduled(on: "2026-10-22") == false)
        #expect(todos.first(where: { $0.id == future.id })?.isScheduled(on: "2026-10-22") == false)
    }

    @Test func undoPreservesEditedTextAndOtherHistoricalDays() {
        let id = UUID()
        var todos = [TodoItem(text: "原始文字", localDay: "2026-10-20", id: id)]
        #expect(TodoCarryover.schedule(id, on: "2026-10-22", in: &todos))
        #expect(TodoCarryover.schedule(id, on: "2026-10-23", in: &todos))
        todos[0].text = "安排后编辑的文字"

        #expect(TodoCarryover.undoSchedule(id, on: "2026-10-22", in: &todos) == .undone)

        #expect(todos[0].text == "安排后编辑的文字")
        #expect(todos[0].scheduledDays == ["2026-10-20", "2026-10-23"])
        #expect(todos[0].isScheduled(on: "2026-10-20"))
        #expect(!todos[0].isScheduled(on: "2026-10-22"))
        #expect(todos[0].isScheduled(on: "2026-10-23"))
    }

    @Test func completedTaskCannotUndoCarryover() {
        let id = UUID()
        var todo = TodoItem(text: "已完成", localDay: "2026-10-20", id: id)
        todo.scheduledDays.append("2026-10-22")
        todo.completedAt = Date(timeIntervalSince1970: 50)
        todo.completedLocalDay = "2026-10-22"
        var todos = [todo]

        #expect(TodoCarryover.undoSchedule(id, on: "2026-10-22", in: &todos) == .completed)
        #expect(todos[0].scheduledDays == ["2026-10-20", "2026-10-22"])
        #expect(todos[0].completedAt == todo.completedAt)
        #expect(todos[0].completedLocalDay == "2026-10-22")
    }

    @Test func undoReportsMissingAndUnscheduledDatesWithoutMutation() {
        let todo = TodoItem(text: "待办", localDay: "2026-10-20", id: UUID())
        var todos = [todo]

        #expect(TodoCarryover.undoSchedule(UUID(), on: "2026-10-22", in: &todos) == .missing)
        #expect(TodoCarryover.undoSchedule(todo.id, on: "2026-10-22", in: &todos) == .notScheduledToday)
        #expect(TodoCarryover.undoSchedule(todo.id, on: "2026-10-20", in: &todos) == .notScheduledToday)
        #expect(todos[0].scheduledDays == ["2026-10-20"])
    }

    @Test func candidatesUseStableDateCreatedAtAndIDOrder() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let olderID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let byIDLaterID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let createdLaterID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let olderDay = TodoItem(text: "更早日期", localDay: "2026-10-18", createdAt: timestamp, id: olderID)
        let sameDayLater = TodoItem(text: "同日后建", localDay: "2026-10-19", createdAt: Date(timeIntervalSince1970: 101), id: createdLaterID)
        let sameDayByID = TodoItem(text: "同日按ID", localDay: "2026-10-19", createdAt: timestamp, id: byIDLaterID)
        let sameDayFirst = TodoItem(text: "同日先建", localDay: "2026-10-19", createdAt: timestamp, id: firstID)

        let ordered = TodoCarryover.candidates(
            in: [sameDayLater, olderDay, sameDayByID, sameDayFirst],
            today: "2026-10-22"
        )

        #expect(ordered.map(\.text) == ["更早日期", "同日先建", "同日按ID", "同日后建"])
    }
}
