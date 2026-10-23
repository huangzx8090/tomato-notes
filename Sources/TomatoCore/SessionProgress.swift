import Foundation

/// 从原始事实即时生成进展，不把计划或 App 时长当成已经完成的成果。
public struct SessionProgress: Sendable {
    public let session: FocusSession
    public let focusSeconds: Double
    public let completedTodos: [TodoItem]
    public let apps: [AppTotal]
    public let recordedTitle: String?

    public var title: String {
        if let recordedTitle { return recordedTitle }
        if let goal = session.goal, !goal.isEmpty { return goal }
        return completedTodos.first?.text ?? "一段专心的时间"
    }

    public static func build(sessionID: UUID, from data: AppData, day: String? = nil) -> SessionProgress? {
        guard let session = data.sessions.first(where: { $0.id == sessionID }) else { return nil }
        let record = ReviewContextBuilder.record(for: .session(sessionID), in: data)
        let intervals = data.intervals.filter { $0.sessionID == sessionID && (day == nil || $0.localDay == day) }
        // 暂停或休息时勾选的任务不能自动归入这一轮。
        let todos = data.todos.filter { todo in
            guard record?.excludedActivityKeys?.contains("todoCompleted|\(todo.id.uuidString)") != true else { return false }
            guard let completed = todo.completedAt else { return false }
            guard day == nil || todo.completionDay == day else { return false }
            // 相邻轮次或午夜分段共用边界时，完成事件只归入随后开始的分段。
            return intervals.contains { completed >= $0.startedAt && completed < $0.endedAt }
        }.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let usage = data.usage.filter { $0.sessionID == sessionID && $0.kind == .app && (day == nil || $0.localDay == day) }
        let groups = Dictionary(grouping: usage, by: { $0.bundleID ?? "unknown" })
        var apps: [AppTotal] = []
        for (id, segments) in groups {
            let seconds = segments.reduce(0.0) { $0 + $1.seconds }
            apps.append(AppTotal(bundleID: id, name: segments.first?.appName ?? "未知 App", seconds: seconds))
        }
        apps.sort {
            if $0.seconds == $1.seconds { return $0.bundleID < $1.bundleID }
            return $0.seconds > $1.seconds
        }
        let recordedTitle = record?.titleOverride ?? session.goal.flatMap { $0.isEmpty ? nil : $0 } ?? record?.activityTopic?.title
        return SessionProgress(session: session, focusSeconds: intervals.reduce(0) { $0 + $1.seconds }, completedTodos: todos, apps: apps, recordedTitle: recordedTitle)
    }
}

public enum AutomaticSessionReview {
    /// 只用于刚结束后排队的轮次；不扫描历史、不自动重试失败的请求。
    public static func shouldGenerate(sessionID: UUID, from data: AppData) -> Bool {
        let record = ReviewContextBuilder.record(for: .session(sessionID), in: data)
        guard data.settings.review.autoSummarizeSessions || (data.settings.activityRecording.enabled && record?.automaticRecordingUsed == true),
              let progress = SessionProgress.build(sessionID: sessionID, from: data),
              progress.session.endedAt != nil, progress.focusSeconds >= 60 else { return false }
        let scope = WorkScope.session(sessionID)
        guard record?.autoReviewAttemptedAt == nil else { return false }
        return record?.summary?.contextDigest != ReviewContextBuilder.build(for: scope, from: data).digest
    }
}
