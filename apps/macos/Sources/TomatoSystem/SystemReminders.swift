import EventKit
import Foundation
import TomatoCore

public struct ReminderList: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let writable: Bool
    public init(id: String, title: String, writable: Bool) { self.id = id; self.title = title; self.writable = writable }
}

public struct ReminderItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let externalID: String?
    public let listID: String
    public let listTitle: String
    public let title: String
    public let isCompleted: Bool
    public let completionDate: Date?
    public let dueDate: DateComponents?
    public let isRecurring: Bool
    public let priority: Int
    public let hasAlarms: Bool
    public let writable: Bool

    public init(id: String, externalID: String?, listID: String, listTitle: String, title: String,
                isCompleted: Bool, completionDate: Date?, dueDate: DateComponents?, isRecurring: Bool, writable: Bool,
                priority: Int = 0, hasAlarms: Bool = false) {
        self.id = id; self.externalID = externalID; self.listID = listID; self.listTitle = listTitle; self.title = title
        self.isCompleted = isCompleted; self.completionDate = completionDate; self.dueDate = dueDate
        self.isRecurring = isRecurring; self.writable = writable; self.priority = priority; self.hasAlarms = hasAlarms
    }
}

public struct ReminderNoteSnapshot: Equatable, Sendable {
    public let title: String
    public let notes: String
    public init(title: String, notes: String) { self.title = title; self.notes = notes }
}

public enum ReminderRepeatFrequency: String, CaseIterable, Sendable {
    case none, daily, weekly, monthly, yearly
    public var label: String {
        switch self { case .none: "不重复"; case .daily: "按天"; case .weekly: "按周"; case .monthly: "按月"; case .yearly: "按年" }
    }
}

public struct ReminderSimpleRepeat: Equatable, Sendable {
    public var frequency: ReminderRepeatFrequency
    public var interval: Int
    public init(frequency: ReminderRepeatFrequency, interval: Int = 1) { self.frequency = frequency; self.interval = interval }
}

public enum ReminderTimeAlarmChange: Sendable {
    case unchanged, set(Date), remove
}

public struct ReminderDetails: Equatable, Sendable {
    public let title: String
    public let notes: String
    public let startDate: DateComponents?
    public let dueDate: DateComponents?
    public let priority: Int
    public let location: String?
    public let url: String?
    public let lastModified: Date?
    public let completed: Bool
    public let recurrenceSummary: [String]
    public let alarmSummary: [String]
    public let simpleRepeat: ReminderSimpleRepeat?
    public let canEditTimeAlarm: Bool
    public let simpleTimeAlarm: Date?
    public let writable: Bool

    public init(title: String, notes: String, startDate: DateComponents?, dueDate: DateComponents?, priority: Int,
                location: String?, url: String?, lastModified: Date?, completed: Bool,
                recurrenceSummary: [String], alarmSummary: [String], writable: Bool,
                simpleRepeat: ReminderSimpleRepeat? = .init(frequency: .none),
                canEditTimeAlarm: Bool = true, simpleTimeAlarm: Date? = nil) {
        self.title = title; self.notes = notes; self.startDate = startDate; self.dueDate = dueDate
        self.priority = priority; self.location = location; self.url = url; self.lastModified = lastModified
        self.completed = completed; self.recurrenceSummary = recurrenceSummary; self.alarmSummary = alarmSummary
        self.simpleRepeat = simpleRepeat; self.canEditTimeAlarm = canEditTimeAlarm
        self.simpleTimeAlarm = simpleTimeAlarm; self.writable = writable
    }
}

public struct ReminderDetailEdits: Sendable {
    public var title: String
    public var notes: String
    public var startDate: DateComponents?
    public var dueDate: DateComponents?
    public var priority: Int
    public var location: String?
    public var url: String?
    public var simpleRepeat: ReminderSimpleRepeat?
    public var timeAlarm: ReminderTimeAlarmChange
    public init(_ details: ReminderDetails) {
        title = details.title; notes = details.notes; startDate = details.startDate; dueDate = details.dueDate
        priority = details.priority; location = details.location; url = details.url
        simpleRepeat = details.simpleRepeat; timeAlarm = .unchanged
    }
}

public enum ReminderStoreError: LocalizedError {
    case noAccess, unavailable, missing, ambiguous, readOnly, changed, invalidProgress, invalidDetails

    public var errorDescription: String? {
        switch self {
        case .noAccess: "没有提醒事项访问权限，请在系统设置中检查。"
        case .unavailable: "暂时无法读取提醒事项，请稍后重试；本地安排已保留。"
        case .missing: "提醒事项或清单已不可用，请重新检查，不会自动删除本地记录。"
        case .ambiguous: "找到了多个可能的提醒事项，请重新选择，避免误写。"
        case .readOnly: "这个提醒事项清单不允许修改。"
        case .changed: "提醒事项已发生变化，请重新查看后再操作。"
        case .invalidProgress: "请填写不超过 2000 字的进展。"
        case .invalidDetails: "请检查标题、链接、日期或优先级。"
        }
    }
}

@MainActor
public protocol ReminderStore: AnyObject {
    var hasFullAccess: Bool { get }
    var onChange: (() -> Void)? { get set }
    func requestAccess() async throws -> Bool
    func lists() throws -> [ReminderList]
    func incompleteItems(in listIDs: Set<String>) async throws -> [ReminderItem]
    func resolve(_ plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderItem
    func setCompleted(_ completed: Bool, expected: Bool, plan: PlannedReminder, allowedListIDs: Set<String>) throws
    func details(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderDetails
    func updateDetails(_ edits: ReminderDetailEdits, plan: PlannedReminder, allowedListIDs: Set<String>, expected: ReminderDetails) throws
    func noteSnapshot(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderNoteSnapshot
    func appendProgress(_ text: String, plan: PlannedReminder, allowedListIDs: Set<String>,
                        expected: ReminderNoteSnapshot, date: Date) throws
}

@MainActor
public final class EventKitReminderStore: ReminderStore {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    public var onChange: (() -> Void)?

    public init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    public var hasFullAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    public func requestAccess() async throws -> Bool { try await store.requestFullAccessToReminders() }

    public func lists() throws -> [ReminderList] {
        guard hasFullAccess else { throw ReminderStoreError.noAccess }
        return store.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, writable: $0.allowsContentModifications)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func incompleteItems(in listIDs: Set<String>) async throws -> [ReminderItem] {
        guard hasFullAccess else { throw ReminderStoreError.noAccess }
        guard !listIDs.isEmpty else { return [] }
        let calendars = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { throw ReminderStoreError.missing }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let items: [ReminderItem] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else { continuation.resume(throwing: ReminderStoreError.unavailable); return }
                continuation.resume(returning: reminders.compactMap { reminder in
                    guard let calendar = reminder.calendar, listIDs.contains(calendar.calendarIdentifier) else { return nil }
                    return Self.snapshot(reminder)
                })
            }
        }
        return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func resolve(_ plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderItem {
        guard let item = Self.snapshot(try find(plan, allowedListIDs: allowedListIDs)) else { throw ReminderStoreError.missing }
        return item
    }

    public func setCompleted(_ completed: Bool, expected: Bool, plan: PlannedReminder, allowedListIDs: Set<String>) throws {
        let reminder = try find(plan, allowedListIDs: allowedListIDs)
        guard let calendar = reminder.calendar else { throw ReminderStoreError.missing }
        guard calendar.allowsContentModifications else { throw ReminderStoreError.readOnly }
        guard reminder.isCompleted == expected else { throw ReminderStoreError.changed }
        guard reminder.isCompleted != completed else { return }
        reminder.isCompleted = completed
        do { try store.save(reminder, commit: true) }
        catch { reminder.rollback(); throw error }
    }

    public func details(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderDetails {
        try Self.detailSnapshot(try find(plan, allowedListIDs: allowedListIDs))
    }

    public func updateDetails(_ edits: ReminderDetailEdits, plan: PlannedReminder, allowedListIDs: Set<String>, expected: ReminderDetails) throws {
        let reminder = try find(plan, allowedListIDs: allowedListIDs)
        guard let calendar = reminder.calendar else { throw ReminderStoreError.missing }
        guard calendar.allowsContentModifications else { throw ReminderStoreError.readOnly }
        guard try Self.detailSnapshot(reminder) == expected else { throw ReminderStoreError.changed }
        let title = edits.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (edits.title == expected.title || (!title.isEmpty && title.count <= 2000)),
              (edits.notes == expected.notes || edits.notes.utf8.count <= 100_000), (0...9).contains(edits.priority) else { throw ReminderStoreError.invalidDetails }
        if edits.startDate != expected.startDate {
            guard edits.startDate?.calendar?.identifier == .gregorian || edits.startDate == nil else { throw ReminderStoreError.invalidDetails }
        }
        if edits.dueDate != expected.dueDate {
            guard edits.dueDate?.calendar?.identifier == .gregorian || edits.dueDate == nil else { throw ReminderStoreError.invalidDetails }
        }
        var parsedURL = reminder.url
        if edits.url != expected.url {
            if let value = edits.url, !value.isEmpty {
                guard let parsed = URL(string: value), parsed.scheme != nil else { throw ReminderStoreError.invalidDetails }
                parsedURL = parsed
            } else { parsedURL = nil }
        }
        var newRules: [EKRecurrenceRule]?
        if edits.simpleRepeat != expected.simpleRepeat {
            guard expected.simpleRepeat != nil, let repeatSetting = edits.simpleRepeat, (1...99).contains(repeatSetting.interval) else { throw ReminderStoreError.invalidDetails }
            if repeatSetting.frequency != .none {
                guard edits.dueDate != nil else { throw ReminderStoreError.invalidDetails }
                let frequency: EKRecurrenceFrequency
                switch repeatSetting.frequency {
                case .daily: frequency = .daily
                case .weekly: frequency = .weekly
                case .monthly: frequency = .monthly
                case .yearly: frequency = .yearly
                case .none: throw ReminderStoreError.invalidDetails
                }
                newRules = [EKRecurrenceRule(recurrenceWith: frequency, interval: repeatSetting.interval, end: nil)]
            }
        }
        switch edits.timeAlarm {
        case .unchanged: break
        case .set, .remove: guard expected.canEditTimeAlarm else { throw ReminderStoreError.invalidDetails }
        }
        // 所有校验先完成，再只设置用户改动的字段，避免失败时留下半成品。
        if edits.title != expected.title { reminder.title = title }
        if edits.notes != expected.notes { reminder.notes = edits.notes.isEmpty ? nil : edits.notes }
        if edits.priority != expected.priority { reminder.priority = edits.priority }
        if edits.startDate != expected.startDate { reminder.startDateComponents = edits.startDate }
        if edits.dueDate != expected.dueDate { reminder.dueDateComponents = edits.dueDate }
        if edits.location != expected.location { reminder.location = edits.location }
        if edits.url != expected.url { reminder.url = parsedURL }
        if edits.simpleRepeat != expected.simpleRepeat { reminder.recurrenceRules = newRules }
        switch edits.timeAlarm {
        case .unchanged: break
        case .set(let date):
            if let old = reminder.alarms?.first { reminder.removeAlarm(old) }
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        case .remove:
            if let old = reminder.alarms?.first { reminder.removeAlarm(old) }
        }
        if reminder.hasChanges {
            do { try store.save(reminder, commit: true) }
            catch { reminder.rollback(); throw error }
        }
    }

    private static func detailSnapshot(_ reminder: EKReminder) throws -> ReminderDetails {
        guard let calendar = reminder.calendar else { throw ReminderStoreError.missing }
        let repeats = (reminder.recurrenceRules ?? []).map { rule in
            let name: String
            switch rule.frequency {
            case .daily: name = "天"
            case .weekly: name = "周"
            case .monthly: name = "月"
            case .yearly: name = "年"
            @unknown default: name = "周期"
            }
            return "每 \(rule.interval) \(name)重复 · 详细规则见系统提醒事项"
        }
        let alarms = (reminder.alarms ?? []).map { alarm in
            if let location = alarm.structuredLocation { return "位置提醒 · \(location.title ?? "位置")" }
            if let date = alarm.absoluteDate { return "时间提醒 · \(date.formatted(date: .numeric, time: .shortened))" }
            return "相对时间提醒 · 详细设置见系统提醒事项"
        }
        let rules = reminder.recurrenceRules ?? []
        let simple: ReminderSimpleRepeat?
        if rules.isEmpty { simple = .init(frequency: .none) }
        else if rules.count == 1, let rule = rules.first,
                rule.recurrenceEnd == nil, rule.firstDayOfTheWeek == 0, (1...99).contains(rule.interval),
                (rule.daysOfTheWeek ?? []).isEmpty, (rule.daysOfTheMonth ?? []).isEmpty,
                (rule.monthsOfTheYear ?? []).isEmpty, (rule.weeksOfTheYear ?? []).isEmpty,
                (rule.daysOfTheYear ?? []).isEmpty, (rule.setPositions ?? []).isEmpty {
            let frequency: ReminderRepeatFrequency?
            switch rule.frequency {
            case .daily: frequency = .daily
            case .weekly: frequency = .weekly
            case .monthly: frequency = .monthly
            case .yearly: frequency = .yearly
            @unknown default: frequency = nil
            }
            simple = frequency.map { .init(frequency: $0, interval: rule.interval) }
        } else { simple = nil }
        let alarmObjects = reminder.alarms ?? []
        let singleAlarm = alarmObjects.first
        let editableAlarm = alarmObjects.isEmpty || (alarmObjects.count == 1 && singleAlarm?.absoluteDate != nil &&
            singleAlarm?.structuredLocation == nil && singleAlarm?.type == .display)
        return ReminderDetails(title: reminder.title ?? "", notes: reminder.notes ?? "", startDate: reminder.startDateComponents,
                               dueDate: reminder.dueDateComponents, priority: reminder.priority, location: reminder.location,
                               url: reminder.url?.absoluteString, lastModified: reminder.lastModifiedDate, completed: reminder.isCompleted,
                               recurrenceSummary: repeats, alarmSummary: alarms, writable: calendar.allowsContentModifications,
                               simpleRepeat: simple, canEditTimeAlarm: editableAlarm,
                               simpleTimeAlarm: editableAlarm ? singleAlarm?.absoluteDate : nil)
    }

    public func noteSnapshot(plan: PlannedReminder, allowedListIDs: Set<String>) throws -> ReminderNoteSnapshot {
        let reminder = try find(plan, allowedListIDs: allowedListIDs)
        guard let calendar = reminder.calendar else { throw ReminderStoreError.missing }
        guard calendar.allowsContentModifications else { throw ReminderStoreError.readOnly }
        return ReminderNoteSnapshot(title: reminder.title, notes: reminder.notes ?? "")
    }

    public func appendProgress(_ text: String, plan: PlannedReminder, allowedListIDs: Set<String>,
                               expected: ReminderNoteSnapshot, date: Date) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000, trimmed.utf8.count <= 12_000 else { throw ReminderStoreError.invalidProgress }
        let reminder = try find(plan, allowedListIDs: allowedListIDs)
        guard let calendar = reminder.calendar else { throw ReminderStoreError.missing }
        guard calendar.allowsContentModifications else { throw ReminderStoreError.readOnly }
        guard reminder.title == expected.title, (reminder.notes ?? "") == expected.notes else { throw ReminderStoreError.changed }
        let stamp = date.formatted(date: .numeric, time: .shortened)
        let entry = "【专注进展 · \(stamp)】\n\(trimmed)"
        reminder.notes = expected.notes.isEmpty ? entry : expected.notes + "\n\n" + entry
        do { try store.save(reminder, commit: true) }
        catch { reminder.rollback(); throw error }
    }

    private func find(_ plan: PlannedReminder, allowedListIDs: Set<String>) throws -> EKReminder {
        guard hasFullAccess else { throw ReminderStoreError.noAccess }
        guard allowedListIDs.contains(plan.listID) else { throw ReminderStoreError.missing }
        if let reminder = store.calendarItem(withIdentifier: plan.reminderID) as? EKReminder,
           reminder.refresh(), reminder.calendar?.calendarIdentifier == plan.listID { return reminder }
        guard let externalID = plan.externalID, !externalID.isEmpty else { throw ReminderStoreError.missing }
        let matches = store.calendarItems(withExternalIdentifier: externalID).compactMap { $0 as? EKReminder }
            .filter { $0.calendar?.calendarIdentifier == plan.listID }
        guard matches.count <= 1 else { throw ReminderStoreError.ambiguous }
        guard let match = matches.first, match.refresh(), match.calendar?.calendarIdentifier == plan.listID else { throw ReminderStoreError.missing }
        return match
    }

    nonisolated private static func snapshot(_ reminder: EKReminder) -> ReminderItem? {
        guard let calendar = reminder.calendar else { return nil }
        return ReminderItem(id: reminder.calendarItemIdentifier, externalID: reminder.calendarItemExternalIdentifier,
                     listID: calendar.calendarIdentifier, listTitle: calendar.title,
                     title: reminder.title ?? "未命名提醒", isCompleted: reminder.isCompleted,
                     completionDate: reminder.completionDate, dueDate: reminder.dueDateComponents,
                     isRecurring: reminder.hasRecurrenceRules,
                     writable: calendar.allowsContentModifications,
                     priority: reminder.priority, hasAlarms: reminder.hasAlarms)
    }
}
