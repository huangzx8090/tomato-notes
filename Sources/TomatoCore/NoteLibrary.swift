import Foundation

public struct NoteDayGroup: Identifiable, Sendable {
    public let day: String
    public let notes: [StickyNote]
    public var id: String { day }
}

public enum NoteLibrary {
    public static func notes(on day: String, in notes: [StickyNote], calendar: Calendar = .current) -> [StickyNote] {
        sorted(notes.filter { $0.dayKey(calendar: calendar) == day })
    }

    public static func history(excluding day: String, in notes: [StickyNote], calendar: Calendar = .current) -> [NoteDayGroup] {
        let groups = Dictionary(grouping: notes.filter { $0.dayKey(calendar: calendar) != day }) {
            $0.dayKey(calendar: calendar)
        }
        return groups.keys.sorted(by: >).map { NoteDayGroup(day: $0, notes: sorted(groups[$0] ?? [])) }
    }

    @discardableResult
    public static func continueNote(_ id: UUID, in notes: inout [StickyNote],
                                    at date: Date = Date(), calendar: Calendar = .current) -> UUID? {
        guard let source = notes.first(where: { $0.id == id }) else { return nil }
        let day = LocalTime.dayKey(date, calendar: calendar)
        if source.dayKey(calendar: calendar) == day { return source.id }
        // 重复点“继续使用”只打开已有的今日副本，避免覆盖已经补写的内容。
        if let existing = notes.first(where: { $0.continuedFromNoteID == id && $0.dayKey(calendar: calendar) == day }) {
            return existing.id
        }
        var copy = StickyNote(at: date, calendar: calendar)
        copy.text = source.text
        copy.width = source.width
        copy.height = source.height
        copy.continuedFromNoteID = id
        notes.append(copy)
        return copy.id
    }

    private static func sorted(_ notes: [StickyNote]) -> [StickyNote] {
        notes.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
