import Combine
import Foundation
import TomatoCore
import TomatoSystem

@MainActor
final class ReminderTasksController: ObservableObject {
    @Published private(set) var lists: [ReminderList] = []
    @Published private(set) var availableItems: [ReminderItem] = []
    @Published private(set) var plannedItems: [UUID: ReminderItem] = [:]
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    private weak var state: AppState?
    private let store: any ReminderStore
    private var generation = 0

    init(state: AppState, store: any ReminderStore) {
        self.state = state
        self.store = store
        store.onChange = { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    var enabled: Bool { state?.taskWorkflow?.remindersEnabled == true }
    var selectedListIDs: Set<String> { Set(state?.taskWorkflow?.selectedListIDs ?? []) }
    var hasAccess: Bool { store.hasFullAccess }

    func connect() async {
        guard let state, state.canWrite, state.taskWorkflow != nil else { return }
        do {
            guard try await store.requestAccess() else { message = ReminderStoreError.noAccess.localizedDescription; return }
            guard state.updateTaskWorkflow({ $0.remindersEnabled = true }) else { return }
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func disconnect() {
        guard let state, state.updateTaskWorkflow({ $0.remindersEnabled = false }) else { return }
        generation += 1
        lists = []; availableItems = []; plannedItems = [:]; loading = false
        message = "已停止读取提醒事项，今日安排及专注关联仍保存在本机。"
    }

    func setList(_ id: String, selected: Bool) {
        guard enabled, hasAccess, lists.contains(where: { $0.id == id }), let state else { return }
        guard state.updateTaskWorkflow({ workflow in
            workflow.selectedListIDs.removeAll { $0 == id }
            if selected { workflow.selectedListIDs.append(id) }
        }) else { return }
        // 更改清单后立即撤销旧结果，避免异步读取完成前操作不再授权的清单。
        generation += 1
        availableItems = []; plannedItems = [:]
        Task { await refresh() }
    }

    func refresh() async {
        guard let state, let workflow = state.taskWorkflow, workflow.remindersEnabled else { return }
        generation += 1
        let request = generation
        guard store.hasFullAccess else {
            lists = []; availableItems = []; plannedItems = [:]; loading = false
            message = ReminderStoreError.noAccess.localizedDescription
            return
        }
        loading = true
        do {
            let newLists = try store.lists()
            let selected = Set(workflow.selectedListIDs)
            let items = try await store.incompleteItems(in: selected)
            guard request == generation, enabled, selectedListIDs == selected, store.hasFullAccess else { return }
            var planned: [UUID: ReminderItem] = [:]
            var missing = false
            for plan in workflow.plannedReminders where selected.contains(plan.listID) {
                do { planned[plan.id] = try store.resolve(plan, allowedListIDs: selected) }
                catch { missing = true }
            }
            lists = newLists
            availableItems = items
            plannedItems = planned
            message = missing ? "部分已安排的提醒暂时无法定位，记录仍保留；请检查清单或重新选择。" : nil
            loading = false
        } catch {
            guard request == generation else { return }
            availableItems = []; plannedItems = [:]; loading = false
            message = error.localizedDescription
        }
    }

    func schedule(_ item: ReminderItem) {
        guard enabled, hasAccess, selectedListIDs.contains(item.listID), !item.isCompleted,
              availableItems.contains(item), let state else { return }
        let matches = plannedItems.filter { $0.value.listID == item.listID && $0.value.id == item.id }.map(\.key)
        guard matches.count <= 1 else { message = ReminderStoreError.ambiguous.localizedDescription; return }
        var scheduledID: UUID?
        guard state.updateTaskWorkflow({ workflow in
            if let id = matches.first, let index = workflow.plannedReminders.firstIndex(where: { $0.id == id }) {
                if !workflow.plannedReminders[index].scheduledDays.contains(state.todayKey) {
                    workflow.plannedReminders[index].scheduledDays.append(state.todayKey)
                }
                scheduledID = id
            } else {
                scheduledID = workflow.scheduleReminder(listID: item.listID, reminderID: item.id,
                                                        externalID: item.isRecurring ? nil : item.externalID, day: state.todayKey)
            }
        }) else { return }
        if let scheduledID { plannedItems[scheduledID] = item }
    }

    func unschedule(_ id: UUID) {
        guard let state else { return }
        _ = state.updateTaskWorkflow { $0.unscheduleReminder(id: id, day: state.todayKey) }
    }

    private func plan(_ id: UUID) throws -> PlannedReminder {
        guard enabled, hasAccess, let state, state.canWrite,
              let plan = state.taskWorkflow?.plannedReminders.first(where: { $0.id == id }),
              selectedListIDs.contains(plan.listID) else { throw ReminderStoreError.noAccess }
        return plan
    }

    func setCompleted(_ id: UUID, expected: Bool) async {
        do {
            let plan = try plan(id)
            let current = try store.resolve(plan, allowedListIDs: selectedListIDs)
            guard current.isCompleted == expected else { throw ReminderStoreError.changed }
            try store.setCompleted(!expected, expected: expected, plan: plan, allowedListIDs: selectedListIDs)
            await refresh()
        } catch { message = error.localizedDescription; await refreshAfterFailure() }
    }

    func details(for item: ReminderItem) throws -> (PlannedReminder, ReminderDetails) {
        guard enabled, hasAccess, selectedListIDs.contains(item.listID), let state, state.canWrite else { throw ReminderStoreError.noAccess }
        let plan = state.taskWorkflow?.plannedReminders.first(where: { plannedItems[$0.id]?.id == item.id && $0.listID == item.listID })
            ?? PlannedReminder(listID: item.listID, reminderID: item.id, externalID: nil, scheduledDays: [])
        return (plan, try store.details(plan: plan, allowedListIDs: selectedListIDs))
    }

    func updateDetails(_ edits: ReminderDetailEdits, plan: PlannedReminder, expected: ReminderDetails) throws {
        guard enabled, hasAccess, selectedListIDs.contains(plan.listID), state?.canWrite == true else { throw ReminderStoreError.noAccess }
        try store.updateDetails(edits, plan: plan, allowedListIDs: selectedListIDs, expected: expected)
        Task { await refresh() }
    }

    func noteSnapshot(_ id: UUID) throws -> ReminderNoteSnapshot {
        let plan = try plan(id)
        return try store.noteSnapshot(plan: plan, allowedListIDs: selectedListIDs)
    }

    func appendProgress(_ text: String, id: UUID, expected: ReminderNoteSnapshot, date: Date) throws {
        let plan = try plan(id)
        try store.appendProgress(text, plan: plan, allowedListIDs: selectedListIDs, expected: expected, date: date)
        Task { await refresh() }
    }

    private func refreshAfterFailure() async {
        let error = message
        await refresh()
        message = error
    }
}
