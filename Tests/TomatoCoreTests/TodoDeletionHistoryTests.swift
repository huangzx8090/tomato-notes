import Foundation
import Testing
@testable import TomatoCore

struct TodoDeletionHistoryTests {
    @Test func deletionOnlyAllowsTheRequestedDayAndDoesNotTouchOtherItems() {
        let yesterday = TodoItem(text: "昨日记录", localDay: "2026-10-21")
        let today = TodoItem(text: "今天的待办", localDay: "2026-10-22")
        var todos = [yesterday, today]
        var history = TodoDeletionHistory()
        let removedYesterday = history.remove(yesterday.id, on: "2026-10-22", from: &todos)
        let removedMissing = history.remove(UUID(), on: "2026-10-22", from: &todos)
        #expect(!removedYesterday && !removedMissing)
        #expect(history.lastDeleted == nil)
        let removedToday = history.remove(today.id, on: "2026-10-22", from: &todos)
        #expect(removedToday)
        #expect(todos.map(\.id) == [yesterday.id])
        #expect(history.lastDeleted?.id == today.id)
    }

    @Test func undoPreservesCompletedRecordAndOriginalOrderAfterAddingAnotherTodo() throws {
        let before = TodoItem(text: "第一项", localDay: "2026-10-22")
        var completed = TodoItem(text: "完成的成果", localDay: "2026-10-22", createdAt: Date(timeIntervalSince1970: 100))
        completed.completedAt = Date(timeIntervalSince1970: 200)
        let after = TodoItem(text: "第三项", localDay: "2026-10-22")
        let added = TodoItem(text: "新加的待办", localDay: "2026-10-23")
        var todos = [before, completed, after]
        var history = TodoDeletionHistory()
        history.remove(completed.id, on: "2026-10-22", from: &todos)
        todos.append(added)
        let restoredItem = history.restoreLast(in: &todos)
        let restored = try #require(restoredItem)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(restored) == encoder.encode(completed))
        #expect(todos.map(\.id) == [before.id, completed.id, after.id, added.id])
        #expect(history.lastDeleted == nil)
    }

    @Test func consecutiveDeletesCanBeUndoneInReverseOrderAndDismissalForgetsTheHistory() {
        let first = TodoItem(text: "第一项", localDay: "2026-10-22")
        let second = TodoItem(text: "第二项", localDay: "2026-10-22")
        var todos = [first, second]
        var history = TodoDeletionHistory()
        history.remove(first.id, on: "2026-10-22", from: &todos)
        history.remove(second.id, on: "2026-10-22", from: &todos)
        let restoredSecond = history.restoreLast(in: &todos)
        #expect(restoredSecond?.id == second.id)
        #expect(history.lastDeleted?.id == first.id)
        let restoredFirst = history.restoreLast(in: &todos)
        #expect(restoredFirst?.id == first.id)
        #expect(todos.map(\.id) == [first.id, second.id])
        history.remove(first.id, on: "2026-10-22", from: &todos)
        history.discard()
        let discarded = history.restoreLast(in: &todos)
        #expect(discarded == nil)
        #expect(todos.map(\.id) == [second.id])
    }

    @Test func undoDoesNotDuplicateOrOverwriteAnItemThatAlreadyExists() {
        let item = TodoItem(text: "原始内容", localDay: "2026-10-22")
        var todos = [item]
        var history = TodoDeletionHistory()
        history.remove(item.id, on: "2026-10-22", from: &todos)
        var reimported = item
        reimported.text = "已从备份恢复并修改"
        todos.append(reimported)
        let restored = history.restoreLast(in: &todos)
        #expect(restored == nil)
        #expect(todos.count == 1 && todos[0].text == reimported.text)
        #expect(history.lastDeleted == nil)
    }
}
