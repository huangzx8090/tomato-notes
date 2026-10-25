import Foundation
import Testing
import TomatoCore
@testable import TomatoNotes

@Suite(.serialized)
struct HistoryActivityStateTests {
    @Test @MainActor func carriedTodoIsEditableRecordsOneActivityAndRestoresItsScheduleAfterDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let today = LocalTime.dayKey(now)
        let previous = try #require(Calendar.current.date(byAdding: .day, value: -2, to: now))
        var fixture = AppData()
        fixture.settings.notificationsEnabled = false
        fixture.settings.activityRecording.enabled = true
        fixture.settings.activityRecording.chromeEnabled = false
        var todo = TodoItem(text: "待结转事项", localDay: LocalTime.dayKey(previous))
        todo.scheduledDays.append(today)
        fixture.todos = [todo]
        var engine = TimerEngine(data: fixture)
        engine.start(at: now.addingTimeInterval(-5))
        _ = engine.advance(seconds: 5, endingAt: now, app: nil, recordingEnabled: false)
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        try repository.save(engine.data)
        let state = AppState(repository: repository, keyReader: { _ in nil })
        defer { state.prepareForQuit() }
        state.deviceLocked = false
        state.startOrPause()
        state.updateTodo(todo.id, text: "结转后编辑完成")
        #expect(state.toggleTodo(todo.id))
        #expect(state.data.todos[0].completionDay == today)
        #expect(state.data.focusActivities.filter { $0.sourceID == todo.id }.count == 1)
        #expect(!state.toggleTodo(todo.id))
        #expect(state.data.focusActivities.filter { $0.sourceID == todo.id }.isEmpty)
        #expect(state.toggleTodo(todo.id))
        #expect(state.data.focusActivities.filter { $0.sourceID == todo.id }.count == 1)
        let revision = state.historySearchRevision
        state.tick()
        #expect(state.historySearchRevision == revision)
        state.deleteTodo(todo.id)
        state.undoTodoDeletion()
        let restored = try #require(state.data.todos.first)
        #expect(restored.id == todo.id && restored.localDay == todo.localDay)
        #expect(restored.scheduledDays == todo.scheduledDays)
        #expect(restored.text == "结转后编辑完成" && restored.isCompleted)
        #expect(HistorySearchIndex(data: state.data).search(query: "结转后编辑").count == 1)
        #expect(try repository.load().todos[0].scheduledDays == todo.scheduledDays)
    }

    @Test @MainActor func deletingActivityInvalidatesSearchAfterRemovingDependentSummary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        var engine = TimerEngine(data: AppData())
        engine.start(at: now.addingTimeInterval(-120))
        _ = engine.advance(seconds: 120, endingAt: now, app: nil, recordingEnabled: false)
        let sessionID = try #require(engine.data.timer.sessionID)
        engine.endEarly(at: now)
        var fixture = engine.data
        let activity = FocusActivity(sessionID: sessionID, kind: .noteEdited, title: "合成便签变更",
                                     startedAt: now, endedAt: now, localDay: LocalTime.dayKey(now))
        fixture.focusActivities = [activity]
        var record = WorkRecord(localDay: LocalTime.dayKey(now), sessionID: sessionID)
        record.summary = .init(content: .init(activities: [], outcomes: ["唯一模拟成果"], nextSteps: [], uncertainties: []),
                               model: "mock", contextDigest: "synthetic", imageIDs: [])
        fixture.workRecords = [record]
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        try repository.save(fixture)
        let state = AppState(repository: repository, keyReader: { _ in nil })
        defer { state.prepareForQuit() }
        #expect(HistorySearchIndex(data: state.data).search(query: "唯一模拟成果").count == 1)
        let revision = state.historySearchRevision
        state.removeFocusActivity(activity.id)
        #expect(state.historySearchRevision > revision)
        #expect(HistorySearchIndex(data: state.data).search(query: "唯一模拟成果").isEmpty)
        #expect(state.workRecord(for: .session(sessionID))?.summary == nil)
    }
}
