import Foundation

public enum TodoCarryoverUndoResult: Equatable, Sendable {
    case undone
    case missing
    case notScheduledToday
    case completed
}

/// 待办结转的纯规则。日期键使用项目既有的 yyyy-MM-dd 格式，因此可按字符串排序。
public enum TodoCarryover {
    /// 返回尚未完成、最近安排日期早于 today 的任务；未来任务自然不会进入候选。
    public static func candidates(in todos: [TodoItem], today: String) -> [TodoItem] {
        todos
            .filter {
                !$0.isCompleted && $0.localDay < today && $0.effectiveScheduledDay < today
            }
            .sorted(by: stableOrder)
    }

    /// 将现有任务安排到 day。返回 true 表示安排历史发生了变化。
    @discardableResult
    public static func schedule(_ id: UUID, on day: String, in todos: inout [TodoItem]) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return false }
        guard !todos[index].isCompleted,
              todos[index].localDay < day,
              todos[index].effectiveScheduledDay < day,
              !todos[index].isScheduled(on: day) else { return false }

        var scheduledDays = todos[index].scheduledDays
        if scheduledDays.isEmpty {
            scheduledDays = [todos[index].localDay]
        } else if !scheduledDays.contains(todos[index].localDay) {
            scheduledDays.insert(todos[index].localDay, at: 0)
        }
        guard !scheduledDays.contains(day) else { return false }
        scheduledDays.append(day)
        todos[index].scheduledDays = scheduledDays
        return true
    }

    /// 按候选项的稳定顺序安排多项任务，并返回实际发生变化的 ID。
    @discardableResult
    public static func schedule(_ ids: Set<UUID>, on day: String, in todos: inout [TodoItem]) -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let orderedIDs = candidates(in: todos, today: day)
            .map(\.id)
            .filter { ids.contains($0) }
        var changed: [UUID] = []
        for id in orderedIDs where schedule(id, on: day, in: &todos) {
            changed.append(id)
        }
        return changed
    }

    /// 只撤销指定日期上的安排。原始所属日、后续安排及任务当前内容均予以保留。
    public static func undoSchedule(
        _ id: UUID,
        on day: String,
        in todos: inout [TodoItem]
    ) -> TodoCarryoverUndoResult {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return .missing }
        guard !todos[index].isCompleted else { return .completed }
        guard day != todos[index].localDay,
              todos[index].scheduledDays.contains(day) else { return .notScheduledToday }

        todos[index].scheduledDays.removeAll { $0 == day }
        if !todos[index].scheduledDays.contains(todos[index].localDay) {
            todos[index].scheduledDays.insert(todos[index].localDay, at: 0)
        }
        return .undone
    }

    private static func stableOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.effectiveScheduledDay != rhs.effectiveScheduledDay {
            return lhs.effectiveScheduledDay < rhs.effectiveScheduledDay
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
