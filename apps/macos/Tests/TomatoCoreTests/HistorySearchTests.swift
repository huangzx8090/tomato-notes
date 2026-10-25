import Foundation
import Testing
@testable import TomatoCore

struct HistorySearchTests {
    private let dayA = "2026-10-21"
    private let dayB = "2026-10-22"

    @Test func matchesChineseAndEnglishWithoutCaseSensitivityAndRequiresEveryTerm() {
        var data = AppData()
        data.todos = [TodoItem(text: "复习 Swift Concurrency 并整理笔记", localDay: dayA)]
        let index = HistorySearchIndex(data: data)

        #expect(index.search(query: "复习 SWIFT").count == 1)
        #expect(index.search(query: "concurrency 笔记").count == 1)
        #expect(index.search(query: "复习 不存在").isEmpty)
    }

    @Test func appliesKindAndInclusiveDateFilters() {
        var data = AppData()
        data.todos = [
            TodoItem(text: "整理旧待办", localDay: dayA),
            TodoItem(text: "整理新待办", localDay: dayB)
        ]
        var note = StickyNote()
        note.localDay = dayB
        note.text = "整理便签里的内容"
        data.notes = [note]
        let index = HistorySearchIndex(data: data)

        let onlyTodayTodos = index.search(query: "整理", filters: HistorySearchFilters(kinds: [.todo], fromDay: dayB, throughDay: dayB))
        #expect(onlyTodayTodos.count == 1)
        #expect(onlyTodayTodos[0].day == dayB && onlyTodayTodos[0].kind == .todo)

        let todayAllKinds = index.search(query: "整理", filters: HistorySearchFilters(fromDay: dayB, throughDay: dayB))
        #expect(todayAllKinds.count == 2)
        #expect(todayAllKinds.allSatisfy { $0.day == dayB })
    }

    @Test func longTextExcerptKeepsTheMatchedContextInsteadOfTheBeginning() throws {
        var data = AppData()
        let marker = "定位到远处的量子线路优化结果"
        data.todos = [TodoItem(text: String(repeating: "前置文字 ", count: 130) + marker + String(repeating: " 后续文字", count: 130),
                               localDay: dayA)]
        let result = try #require(HistorySearchIndex(data: data).search(query: "量子线路").first)

        #expect(result.excerpt.contains(marker))
        #expect(result.excerpt.count < 250)
        #expect(result.sources == [.userRecord])
    }

    @Test func sameSessionFocusAndOutcomesMergeIntoOneStableResult() throws {
        var data = AppData()
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        data.sessions = [FocusSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_792_598_400),
                                      goal: "调研量子线路")]
        data.intervals = [
            .init(sessionID: sessionID, startedAt: Date(timeIntervalSince1970: 1_792_598_400),
                  endedAt: Date(timeIntervalSince1970: 1_792_598_460), localDay: dayA,
                  timeZoneID: "Asia/Shanghai", seconds: 60)
        ]
        var record = WorkRecord(localDay: dayB, sessionID: sessionID)
        record.userText = "整理实验结论"
        record.summary = AISummary(content: WorkSummary(activities: [], outcomes: ["提出优化方向"], nextSteps: [], uncertainties: []),
                                   model: "test", contextDigest: "", imageIDs: [])
        data.workRecords = [record]

        let index = HistorySearchIndex(data: data)
        let result = try #require(index.search(query: "量子 结论 方向").first)
        #expect(index.search(query: "量子 结论 方向").count == 1)
        #expect(result.id == "session:\(sessionID.uuidString.lowercased())")
        #expect(result.kind == .focus)
        #expect(result.target == .work(.session(sessionID)))
        #expect(result.day == dayA)
        #expect(result.sources == [.userRecord, .aiSummary])
        #expect(result.excerpt.contains("用户记录"))
        #expect(result.excerpt.contains("AI 总结"))

        let focusOnly = index.search(query: "量子", filters: HistorySearchFilters(kinds: [.focus]))
        #expect(focusOnly.count == 1 && focusOnly[0].target == .session(sessionID))
        let outcomeOnly = index.search(query: "结论", filters: HistorySearchFilters(kinds: [.outcome]))
        #expect(outcomeOnly.count == 1 && outcomeOnly[0].target == .work(.session(sessionID)))
        #expect(outcomeOnly[0].day == dayB)
    }

    @Test func stableIDsAndSameDayOrderDoNotDependOnArrayOrder() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var data = AppData()
        var first = TodoItem(text: "共同关键词 第一项", localDay: dayB)
        first.id = firstID
        var second = TodoItem(text: "共同关键词 第二项", localDay: dayB)
        second.id = secondID
        data.todos = [second, first]

        let firstResults = HistorySearchIndex(data: data).search(query: "共同关键词")
        data.todos.reverse()
        let reorderedResults = HistorySearchIndex(data: data).search(query: "共同关键词")
        #expect(firstResults.map(\.id) == reorderedResults.map(\.id))
        #expect(firstResults.map(\.id) == [
            "todo:\(firstID.uuidString.lowercased())",
            "todo:\(secondID.uuidString.lowercased())"
        ])
        #expect(firstResults[0].id == reorderedResults[0].id)
    }

    @Test func emptyOrWhitespaceQueryNeverReturnsTheWholeIndex() {
        var data = AppData()
        data.todos = [TodoItem(text: "任意历史内容", localDay: dayA)]
        let index = HistorySearchIndex(data: data)
        #expect(index.search(query: "").isEmpty)
        #expect(index.search(query: " \n\t ").isEmpty)
    }

    @Test func focusDateUsesEarliestSavedIntervalDayAndNotesUseArchiveDay() throws {
        var data = AppData()
        let sessionID = UUID()
        data.sessions = [FocusSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_792_598_400), goal: "跨日归属目标")]
        data.intervals = [
            .init(sessionID: sessionID, startedAt: Date(timeIntervalSince1970: 1_792_600_000),
                  endedAt: Date(timeIntervalSince1970: 1_792_600_060), localDay: dayB,
                  timeZoneID: "Asia/Shanghai", seconds: 60),
            .init(sessionID: sessionID, startedAt: Date(timeIntervalSince1970: 1_792_599_000),
                  endedAt: Date(timeIntervalSince1970: 1_792_599_060), localDay: dayA,
                  timeZoneID: "Asia/Shanghai", seconds: 60)
        ]
        var note = StickyNote()
        note.localDay = dayA
        note.text = "归档日期便签"
        note.updatedAt = Date(timeIntervalSince1970: 2_000_000_000)
        data.notes = [note]

        let index = HistorySearchIndex(data: data)
        let focus = try #require(index.search(query: "归属目标").first)
        let archivedNote = try #require(index.search(query: "归档日期").first)
        #expect(focus.day == dayA)
        #expect(archivedNote.day == dayA)
    }
}
