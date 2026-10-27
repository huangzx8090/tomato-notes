import Foundation
import Testing
import TomatoCore
import TomatoSystem
@testable import TomatoNotes

@MainActor
private final class FakeReminderStore: ReminderStore {
    var hasFullAccess = false
    var onChange: (() -> Void)?
    var requests = 0
    var reads = 0
    var writes = 0
    var shouldFail = false
    var notes = "原有备注"
    var item = ReminderItem(id: "reminder-1", externalID: "external-1", listID: "list-1", listTitle: "模拟清单",
                            title: "模拟任务", isCompleted: false, completionDate: nil, dueDate: nil,
                            isRecurring: false, writable: true)
    func requestAccess() async throws -> Bool { requests += 1; hasFullAccess = true; return true }
    func lists() throws -> [ReminderList] {
        guard hasFullAccess else { throw ReminderStoreError.noAccess }
        return [.init(id: "list-1", title: "模拟清单", writable: true)]
    }
    func incompleteItems(in listIDs: Set<String>) async throws -> [ReminderItem] {
        guard hasFullAccess else { throw ReminderStoreError.noAccess }
        guard !listIDs.isEmpty else { return [] }
        reads += 1
        if shouldFail { throw ReminderStoreError.unavailable }
        return listIDs.contains(item.listID) && !item.isCompleted ? [item] : []
    }
    func resolve(_ plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderItem {
        guard hasFullAccess, allowedListIDs.contains(plan.listID), plan.reminderID == item.id else { throw ReminderStoreError.missing }
        return item
    }
    func setCompleted(_ completed: Bool, expected: Bool, plan: PlannedReminder, allowedListIDs: Set<String>) throws {
        let existing = try resolve(plan, allowedListIDs: allowedListIDs)
        guard existing.isCompleted == expected else { throw ReminderStoreError.changed }
        writes += 1
        item = .init(id: existing.id, externalID: existing.externalID, listID: existing.listID, listTitle: existing.listTitle,
                     title: existing.title, isCompleted: completed, completionDate: nil, dueDate: existing.dueDate,
                     isRecurring: existing.isRecurring, writable: existing.writable)
    }
    func details(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderDetails {
        let found = try resolve(plan, allowedListIDs: allowedListIDs)
        return .init(title: found.title, notes: notes, startDate: nil, dueDate: found.dueDate, priority: found.priority,
                     location: nil, url: nil, lastModified: nil, completed: found.isCompleted,
                     recurrenceSummary: [], alarmSummary: [], writable: found.writable)
    }
    func updateDetails(_ edits: ReminderDetailEdits, plan: PlannedReminder, allowedListIDs: Set<String>, expected: ReminderDetails) throws {
        let current = try details(plan: plan, allowedListIDs: allowedListIDs)
        guard current == expected else { throw ReminderStoreError.changed }
        let found = try resolve(plan, allowedListIDs: allowedListIDs)
        item = .init(id: found.id, externalID: found.externalID, listID: found.listID, listTitle: found.listTitle,
                     title: edits.title, isCompleted: found.isCompleted, completionDate: found.completionDate,
                     dueDate: edits.dueDate, isRecurring: found.isRecurring, writable: found.writable, priority: edits.priority)
        notes = edits.notes; writes += 1
    }
    func noteSnapshot(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderNoteSnapshot {
        let found = try resolve(plan, allowedListIDs: allowedListIDs)
        return .init(title: found.title, notes: notes)
    }
    func appendProgress(_ text: String, plan: PlannedReminder, allowedListIDs: Set<String>, expected: ReminderNoteSnapshot, date: Date) throws {
        let current = try noteSnapshot(plan: plan, allowedListIDs: allowedListIDs)
        guard current == expected else { throw ReminderStoreError.changed }
        writes += 1
        notes += "\n\n" + text
    }
}

@Suite(.serialized)
struct ReminderWorkflowTests {
    @Test @MainActor func optInPlanningAndConflictDoNotChangeUnselectedData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FakeReminderStore()
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        let state = AppState(repository: repository, keyReader: { _ in nil }, reminderStore: store)
        defer { state.prepareForQuit() }
        let controller = state.reminderTasks
        await controller.refresh()
        #expect(store.requests == 0 && store.reads == 0 && store.writes == 0)
        await controller.connect()
        #expect(store.requests == 1 && store.reads == 0 && store.writes == 0)
        controller.schedule(store.item)
        #expect(state.taskWorkflow?.plannedReminders.isEmpty == true)
        controller.setList("list-1", selected: true)
        await controller.refresh()
        controller.schedule(store.item)
        let plan = try #require(state.taskWorkflow?.plannedReminders.first)
        #expect(plan.scheduledDays == [state.todayKey] && store.writes == 0)
        let before = try controller.noteSnapshot(plan.id)
        store.notes = "其他设备已修改的备注"
        #expect(throws: ReminderStoreError.self) { try controller.appendProgress("新进展", id: plan.id, expected: before, date: Date()) }
        #expect(store.notes == "其他设备已修改的备注" && store.writes == 0)
        let current = try controller.noteSnapshot(plan.id)
        try controller.appendProgress("新进展", id: plan.id, expected: current, date: Date())
        #expect(store.notes == "其他设备已修改的备注\n\n新进展" && store.writes == 1)
        controller.unschedule(plan.id)
        #expect(state.taskWorkflow?.plannedReminders.first?.scheduledDays.isEmpty == true && store.writes == 1)
        controller.disconnect()
        #expect(throws: ReminderStoreError.self) { _ = try controller.noteSnapshot(plan.id) }
        #expect(state.taskWorkflow?.plannedReminders.count == 1)
    }

    @Test @MainActor func detailEditsRequireCurrentSnapshotAndSelectedList() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FakeReminderStore()
        let state = AppState(repository: LocalRepository(fileURL: root.appendingPathComponent("data.json")), keyReader: { _ in nil }, reminderStore: store)
        defer { state.prepareForQuit() }
        let controller = state.reminderTasks
        await controller.connect()
        controller.setList("list-1", selected: true)
        await controller.refresh()
        let (plan, original) = try controller.details(for: store.item)
        var edits = ReminderDetailEdits(original)
        edits.title = "修改后的模拟任务"; edits.notes = "新的模拟备注"; edits.priority = 1
        store.notes = "其他设备先更新"
        #expect(throws: ReminderStoreError.self) { try controller.updateDetails(edits, plan: plan, expected: original) }
        #expect(store.writes == 0 && store.notes == "其他设备先更新")
        let (_, fresh) = try controller.details(for: store.item)
        edits = ReminderDetailEdits(fresh)
        edits.title = "修改后的模拟任务"; edits.notes = "新的模拟备注"; edits.priority = 1
        try controller.updateDetails(edits, plan: plan, expected: fresh)
        #expect(store.writes == 1 && store.item.title == "修改后的模拟任务" && store.item.priority == 1)
        controller.setList("list-1", selected: false)
        #expect(throws: ReminderStoreError.self) { try controller.updateDetails(edits, plan: plan, expected: fresh) }
        #expect(store.writes == 1)
    }

    @Test @MainActor func linkedFocusAndLocalProgressUseIdentityAndSurviveReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        let store = FakeReminderStore()
        let state = AppState(repository: repository, keyReader: { _ in nil }, reminderStore: store)
        defer { state.prepareForQuit() }
        state.deviceLocked = false
        state.addTodo("模拟任务")
        let todo = try #require(state.data.todos.first)
        state.selectFocusTask(.init(source: .local, id: todo.id), title: todo.text)
        state.startOrPause()
        let sessionID = try #require(state.data.timer.sessionID)
        #expect(state.taskWorkflow?.task(for: sessionID) == .init(source: .local, id: todo.id))
        #expect(!state.saveLocalTaskProgress(todoID: UUID(), sessionID: sessionID, text: "错项"))
        #expect(state.saveLocalTaskProgress(todoID: todo.id, sessionID: sessionID, text: "已整理一段"))
        let restored = try repository.load()
        #expect(try TaskWorkflow.load(from: restored).localProgress.first?.text == "已整理一段")
        #expect(store.requests == 0 && store.reads == 0 && store.writes == 0)
    }

    #if DEBUG
    @Test @MainActor func syntheticDateChangesDoNotInventRepeats() async throws {
        let store = SyntheticReminderStore()
        _ = try await store.requestAccess()
        let item = try #require(try await store.incompleteItems(in: ["sample-list"]).first)
        let plan = PlannedReminder(listID: item.listID, reminderID: item.id, externalID: item.externalID, scheduledDays: [])
        let original = try store.details(plan: plan, allowedListIDs: ["sample-list"])
        var edits = ReminderDetailEdits(original)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var due = calendar.dateComponents([.year, .month, .day], from: Date())
        due.calendar = calendar
        edits.dueDate = due
        try store.updateDetails(edits, plan: plan, allowedListIDs: ["sample-list"], expected: original)
        let changed = try store.resolve(plan, allowedListIDs: ["sample-list"])
        #expect(changed.dueDate == due && !changed.isRecurring)
        #expect(try store.details(plan: plan, allowedListIDs: ["sample-list"]).notes == original.notes)
    }
    #endif

    @Test @MainActor func changingATaskAfterSelectionDoesNotBindWrongGoal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(repository: LocalRepository(fileURL: root.appendingPathComponent("data.json")), keyReader: { _ in nil }, reminderStore: FakeReminderStore())
        defer { state.prepareForQuit() }
        state.deviceLocked = false
        state.addTodo("模拟旧标题")
        let todo = try #require(state.data.todos.first)
        state.selectFocusTask(.init(source: .local, id: todo.id), title: todo.text)
        state.updateTodo(todo.id, text: "修改后的标题")
        state.startOrPause()
        let id = try #require(state.data.timer.sessionID)
        #expect(state.taskWorkflow?.task(for: id) == nil)
        #expect(state.feedback?.contains("未关联待办") == true)
    }

    @Test @MainActor func failedRefreshPreservesPlanAndRevokesCachedActions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FakeReminderStore()
        let state = AppState(repository: LocalRepository(fileURL: root.appendingPathComponent("data.json")), keyReader: { _ in nil }, reminderStore: store)
        defer { state.prepareForQuit() }
        let controller = state.reminderTasks
        await controller.connect()
        controller.setList("list-1", selected: true)
        await controller.refresh()
        controller.schedule(store.item)
        let id = try #require(state.taskWorkflow?.plannedReminders.first?.id)
        store.shouldFail = true
        await controller.refresh()
        #expect(controller.availableItems.isEmpty && controller.plannedItems.isEmpty)
        #expect(state.taskWorkflow?.plannedReminders.first?.id == id && store.writes == 0)
        store.hasFullAccess = false
        #expect(throws: ReminderStoreError.self) { _ = try controller.noteSnapshot(id) }
    }
}
