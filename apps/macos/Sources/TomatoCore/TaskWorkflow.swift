import Foundation

public struct PlannedReminder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var listID: String
    public var reminderID: String
    public var externalID: String?
    public var scheduledDays: [String]

    public init(id: UUID = UUID(), listID: String, reminderID: String, externalID: String?, scheduledDays: [String]) {
        self.id = id
        self.listID = listID
        self.reminderID = reminderID
        self.externalID = externalID
        self.scheduledDays = scheduledDays
    }
}

public struct TaskReference: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case local, reminder }
    public var source: Source
    public var id: UUID
    public init(source: Source, id: UUID) { self.source = source; self.id = id }
}

public struct TaskSessionLink: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var task: TaskReference
    public init(sessionID: UUID, task: TaskReference) { self.sessionID = sessionID; self.task = task }
}

public struct LocalTaskProgress: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var todoID: UUID
    public var sessionID: UUID
    public var text: String
    public var createdAt: Date
    public init(id: UUID = UUID(), todoID: UUID, sessionID: UUID, text: String, createdAt: Date = Date()) {
        self.id = id; self.todoID = todoID; self.sessionID = sessionID; self.text = text; self.createdAt = createdAt
    }
}

public struct TaskWorkflow: Codable, Equatable, Sendable {
    public static let storageKey = "macosTaskWorkflow"
    public var version = 1
    public var remindersEnabled = false
    public var selectedListIDs: [String] = []
    public var plannedReminders: [PlannedReminder] = []
    public var sessionLinks: [TaskSessionLink] = []
    public var localProgress: [LocalTaskProgress] = []

    public init() {}

    @discardableResult
    public mutating func scheduleReminder(listID: String, reminderID: String, externalID: String?, day: String) -> UUID {
        if let index = plannedReminders.firstIndex(where: { $0.listID == listID && $0.reminderID == reminderID }) {
            if !plannedReminders[index].scheduledDays.contains(day) { plannedReminders[index].scheduledDays.append(day) }
            return plannedReminders[index].id
        }
        let item = PlannedReminder(listID: listID, reminderID: reminderID, externalID: externalID, scheduledDays: [day])
        plannedReminders.append(item)
        return item.id
    }

    public mutating func unscheduleReminder(id: UUID, day: String) {
        guard let index = plannedReminders.firstIndex(where: { $0.id == id }) else { return }
        // 保留身份和历史专注关联，只移除本次安排。
        plannedReminders[index].scheduledDays.removeAll { $0 == day }
    }

    public mutating func bind(sessionID: UUID, to task: TaskReference) {
        guard !sessionLinks.contains(where: { $0.sessionID == sessionID }) else { return }
        sessionLinks.append(TaskSessionLink(sessionID: sessionID, task: task))
    }

    public func task(for sessionID: UUID) -> TaskReference? {
        sessionLinks.first(where: { $0.sessionID == sessionID })?.task
    }

    public static func load(from data: AppData) throws -> TaskWorkflow {
        guard let value = data.extraFields[storageKey] else { return TaskWorkflow() }
        let result = try JSONDecoder().decode(TaskWorkflow.self, from: JSONEncoder().encode(value))
        guard result.version == 1 else { throw TaskWorkflowError.unsupportedVersion }
        return result
    }

    public func save(into data: inout AppData) throws {
        guard version == 1 else { throw TaskWorkflowError.unsupportedVersion }
        data.extraFields[Self.storageKey] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))
    }
}

public enum TaskWorkflowError: LocalizedError {
    case unsupportedVersion
    public var errorDescription: String? { "待办关联数据版本不受支持，已保留原始资料。" }
}
