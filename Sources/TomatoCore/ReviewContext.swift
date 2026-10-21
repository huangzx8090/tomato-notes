import CryptoKit
import Foundation

public struct ReviewContext: Sendable {
    public let text: String
    public let images: [WorkImage]
    public var digest: String {
        let value = text + images.map { $0.id.uuidString }.joined(separator: ",")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ReviewContextBuilder {
    public static func record(for scope: WorkScope, in data: AppData) -> WorkRecord? {
        switch scope {
        case .session(let id): data.workRecords.first { $0.sessionID == id }
        case .day(let day): data.workRecords.first { $0.sessionID == nil && $0.localDay == day }
        }
    }

    public static func build(for scope: WorkScope, from data: AppData) -> ReviewContext {
        let record = record(for: scope, in: data)
        var facts: [String: Any] = [:]
        switch scope {
        case .session(let id):
            let session = data.sessions.first { $0.id == id }
            let intervals = data.intervals.filter { $0.sessionID == id }
            let usage = data.usage.filter { $0.sessionID == id }
            facts["范围"] = "一轮番茄钟的工作与成果"
            facts["开始时间"] = session.map { ISO8601DateFormatter().string(from: $0.startedAt) }
            facts["状态"] = session?.endedAt == nil ? "进行中，尚未结束" : (session!.completed ? "完整专注" : "提前结束")
            facts["实际专注秒数"] = Int(intervals.reduce(0) { $0 + $1.seconds }.rounded())
            facts["专注期间前台App"] = appFacts(usage)
            if let session {
                facts["此时间段勾选完成的待办"] = data.todos.filter {
                    guard let completed = $0.completedAt else { return false }
                    return completed >= session.startedAt && completed <= (session.endedAt ?? Date())
                }.map(\.text)
            }
        case .day(let day):
            let summary = DailySummary.build(day: day, from: data)
            facts["范围"] = "\(day) 一整天的工作与成果"
            facts["日期"] = day
            facts["实际专注秒数"] = Int(summary.focusSeconds.rounded())
            facts["完整番茄轮数"] = summary.completedSessions
            facts["完成的待办"] = summary.completedTodos.map(\.text)
            facts["尚未完成的待办"] = summary.todos.filter { !$0.isCompleted }.map(\.text)
            facts["专注期间前台App"] = appFacts(data.usage.filter { $0.localDay == day })
            facts["各轮工作与AI成果"] = data.workRecords.filter { $0.localDay == day && $0.sessionID != nil }
                .sorted { $0.updatedAt < $1.updatedAt }.map { item -> [String: Any] in
                    var entry: [String: Any] = ["用户描述": item.userText, "图片数量": item.images.count]
                    if let session = data.sessions.first(where: { $0.id == item.sessionID }) {
                        entry["开始时间"] = ISO8601DateFormatter().string(from: session.startedAt)
                        entry["实际专注秒数"] = Int(data.intervals.filter { $0.sessionID == session.id && $0.localDay == day }.reduce(0) { $0 + $1.seconds }.rounded())
                    }
                    if let summary = item.summary { entry["已有AI总结"] = summary.content.markdown }
                    return entry
                }
        }
        facts["用户补充的工作与成果"] = record?.userText ?? ""
        facts["当前附图名称"] = record?.images.map(\.name) ?? []
        facts["记录边界"] = "App 时长仅覆盖专注期间，不能证明完成了什么；无文字或图片依据的成果必须标为待确认。"
        let bytes = (try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys, .prettyPrinted])) ?? Data()
        var text = String(data: bytes, encoding: .utf8) ?? "{}"
        if text.count > 40_000 { text = String(text.prefix(40_000)) + "\n记录过长，后续已截断；不得猜测未显示内容。" }
        return ReviewContext(text: text, images: record?.images ?? [])
    }

    private static func appFacts(_ usage: [AppUsageSegment]) -> [[String: Any]] {
        let groups = Dictionary(grouping: usage, by: { $0.kind == .app ? ($0.appName ?? "未知App") : ($0.kind == .disabled ? "未记录" : "未归属") })
        return groups.map { name, segments in ["App": name, "秒数": Int(segments.reduce(0) { $0 + $1.seconds }.rounded())] }
            .sorted { ($0["App"] as? String ?? "") < ($1["App"] as? String ?? "") }
    }
}
