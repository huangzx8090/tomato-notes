#if DEBUG
import Foundation
import TomatoCore
import TomatoSystem

// 仅供隔离 QA 包使用，不访问系统提醒事项。
@MainActor
final class SyntheticReminderStore: ReminderStore {
    var hasFullAccess = false
    var onChange: (() -> Void)?
    private var notes: [String: String] = ["sample-1": "这是用于界面验证的模拟备注。"]
    private var detailsByID: [String: ReminderDetails] = [:]
    private var items = [
        ReminderItem(id: "sample-1", externalID: "sample-ext-1", listID: "sample-list", listTitle: "模拟清单",
                     title: "整理课程笔记（模拟）", isCompleted: false, completionDate: nil, dueDate: nil, isRecurring: false, writable: true),
        ReminderItem(id: "sample-2", externalID: "sample-ext-2", listID: "sample-list", listTitle: "模拟清单",
                     title: "复习第一章（模拟）", isCompleted: false, completionDate: nil, dueDate: nil, isRecurring: false, writable: true)
    ]
    func requestAccess() async throws -> Bool { hasFullAccess = true; return true }
    func lists() throws -> [ReminderList] { [.init(id: "sample-list", title: "模拟清单", writable: true)] }
    func incompleteItems(in listIDs: Set<String>) async throws -> [ReminderItem] {
        guard hasFullAccess else { throw ReminderStoreError.noAccess }
        return items.filter { listIDs.contains($0.listID) && !$0.isCompleted }
    }
    func resolve(_ plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderItem {
        guard hasFullAccess, allowedListIDs.contains(plan.listID), let item = items.first(where: { $0.id == plan.reminderID }) else { throw ReminderStoreError.missing }
        return item
    }
    func setCompleted(_ completed: Bool, expected: Bool, plan: PlannedReminder, allowedListIDs: Set<String>) throws {
        let item = try resolve(plan, allowedListIDs: allowedListIDs)
        guard item.isCompleted == expected, let index = items.firstIndex(where: { $0.id == item.id }) else { throw ReminderStoreError.changed }
        items[index] = .init(id: item.id, externalID: item.externalID, listID: item.listID, listTitle: item.listTitle,
                             title: item.title, isCompleted: completed, completionDate: completed ? Date() : nil,
                             dueDate: item.dueDate, isRecurring: item.isRecurring, writable: item.writable)
        onChange?()
    }
    func details(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderDetails {
        let item = try resolve(plan, allowedListIDs: allowedListIDs)
        let saved = detailsByID[item.id]
        return .init(title: item.title, notes: notes[item.id] ?? "", startDate: saved?.startDate, dueDate: item.dueDate,
                     priority: item.priority, location: saved?.location, url: saved?.url, lastModified: saved?.lastModified,
                     completed: item.isCompleted, recurrenceSummary: saved?.recurrenceSummary ?? [], alarmSummary: saved?.alarmSummary ?? [],
                     writable: item.writable, simpleRepeat: saved?.simpleRepeat ?? .init(frequency: .none),
                     canEditTimeAlarm: saved?.canEditTimeAlarm ?? true, simpleTimeAlarm: saved?.simpleTimeAlarm)
    }
    func updateDetails(_ edits: ReminderDetailEdits, plan: PlannedReminder, allowedListIDs: Set<String>, expected: ReminderDetails) throws {
        let old = try details(plan: plan, allowedListIDs: allowedListIDs)
        guard old == expected, let index = items.firstIndex(where: { $0.id == plan.reminderID }) else { throw ReminderStoreError.changed }
        let item = items[index]
        let recurring = edits.simpleRepeat.map { $0.frequency != ReminderRepeatFrequency.none } ?? false
        let alarm: Date?
        switch edits.timeAlarm {
        case .unchanged: alarm = old.simpleTimeAlarm
        case .set(let date): alarm = date
        case .remove: alarm = nil
        }
        let alarms = alarm.map { ["时间提醒 · \($0.formatted(date: .numeric, time: .shortened))"] } ?? []
        items[index] = .init(id: item.id, externalID: item.externalID, listID: item.listID, listTitle: item.listTitle,
                             title: edits.title, isCompleted: item.isCompleted, completionDate: item.completionDate,
                             dueDate: edits.dueDate, isRecurring: recurring, writable: item.writable, priority: edits.priority, hasAlarms: !alarms.isEmpty)
        notes[item.id] = edits.notes
        detailsByID[item.id] = .init(title: edits.title, notes: edits.notes, startDate: edits.startDate, dueDate: edits.dueDate,
                                   priority: edits.priority, location: edits.location, url: edits.url, lastModified: Date(), completed: item.isCompleted,
                                   recurrenceSummary: recurring ? ["模拟重复"] : [], alarmSummary: alarms, writable: item.writable,
                                   simpleRepeat: edits.simpleRepeat, canEditTimeAlarm: true, simpleTimeAlarm: alarm)
        onChange?()
    }
    func noteSnapshot(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderNoteSnapshot {
        let item = try resolve(plan, allowedListIDs: allowedListIDs)
        return .init(title: item.title, notes: notes[item.id] ?? "")
    }
    func appendProgress(_ text: String, plan: PlannedReminder, allowedListIDs: Set<String>, expected: ReminderNoteSnapshot, date: Date) throws {
        let snapshot = try noteSnapshot(plan: plan, allowedListIDs: allowedListIDs)
        guard snapshot == expected else { throw ReminderStoreError.changed }
        notes[plan.reminderID] = snapshot.notes + "\n\n【模拟专注进展】\n" + text
        onChange?()
    }
}
#endif
