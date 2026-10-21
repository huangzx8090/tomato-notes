import Foundation

public struct AppTotal: Identifiable {
    public let bundleID: String
    public let name: String
    public let seconds: Double
    public var id: String { bundleID }
}

public struct DailySummary {
    public let day: String
    public let focusSeconds: Double
    public let completedSessions: Int
    public let earlySessions: Int
    public let todos: [TodoItem]
    public let apps: [AppTotal]
    public let unattributedSeconds: Double
    public let disabledSeconds: Double
    public let sessions: [FocusSession]

    public var completedTodos: [TodoItem] { todos.filter(\.isCompleted) }

    public var sentence: String {
        guard focusSeconds > 0 || !todos.isEmpty else { return "今天的记录会从第一轮专注开始。" }
        let duration = focusSeconds > 0 && focusSeconds < 60 ? "\(Int(focusSeconds.rounded())) 秒" : "\(Int(focusSeconds / 60)) 分钟"
        return "累计专注 \(duration)，完成 \(completedTodos.count) 项待办。"
    }

    public static func build(day: String, from data: AppData, calendar: Calendar = .current) -> DailySummary {
        let focus = data.intervals.filter { $0.localDay == day }.reduce(0) { $0 + $1.seconds }
        let completed = data.sessions.filter { session in
            guard session.completed, let end = session.endedAt else { return false }
            return (session.endedLocalDay ?? LocalTime.dayKey(end, calendar: calendar)) == day
        }.count
        let early = data.sessions.filter { session in
            guard !session.completed, let end = session.endedAt else { return false }
            return (session.endedLocalDay ?? LocalTime.dayKey(end, calendar: calendar)) == day
        }.count
        let usage = data.usage.filter { $0.localDay == day }
        var totals: [String: (String, Double)] = [:]
        for segment in usage where segment.kind == .app {
            let id = segment.bundleID ?? "unknown"
            let previous = totals[id]
            totals[id] = (segment.appName ?? previous?.0 ?? "未知 App", (previous?.1 ?? 0) + segment.seconds)
        }
        let apps = totals.map { AppTotal(bundleID: $0.key, name: $0.value.0, seconds: $0.value.1) }
            .sorted { $0.seconds > $1.seconds }
        let timeline = data.sessions.filter { session in
            session.endedLocalDay == day || data.intervals.contains { $0.sessionID == session.id && $0.localDay == day }
        }.sorted { $0.startedAt > $1.startedAt }
        return DailySummary(
            day: day, focusSeconds: focus, completedSessions: completed, earlySessions: early,
            todos: data.todos.filter { $0.localDay == day }.sorted { $0.createdAt < $1.createdAt },
            apps: apps,
            unattributedSeconds: usage.filter { $0.kind == .unattributed }.reduce(0) { $0 + $1.seconds },
            disabledSeconds: usage.filter { $0.kind == .disabled }.reduce(0) { $0 + $1.seconds },
            sessions: timeline
        )
    }
}
