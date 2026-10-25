import Foundation

public struct TodoDeletionHistory: Sendable {
    private struct Entry: Sendable {
        let item: TodoItem
        let index: Int
    }

    private var entries: [Entry] = []
    public var lastDeleted: TodoItem? { entries.last?.item }

    public init() {}

    @discardableResult
    public mutating func remove(_ id: UUID, on day: String, from todos: inout [TodoItem]) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id && $0.effectiveScheduledDay == day }) else { return false }
        entries.append(Entry(item: todos.remove(at: index), index: index))
        return true
    }

    @discardableResult
    public mutating func restoreLast(in todos: inout [TodoItem]) -> TodoItem? {
        guard let entry = entries.popLast(), !todos.contains(where: { $0.id == entry.item.id }) else { return nil }
        // 恢复原记录，保留完成时间与所属日期，避免把撤销记成一次新的成果。
        todos.insert(entry.item, at: min(entry.index, todos.count))
        return entry.item
    }

    public mutating func discard() { entries.removeAll() }
}
