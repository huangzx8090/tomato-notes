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
            facts["用户设定的本轮目标（不代表完成）"] = session?.goal ?? ""
            facts["状态"] = session?.endedAt == nil ? "进行中，尚未结束" : (session!.completed ? "完整专注" : "提前结束")
            facts["实际专注秒数"] = Int(intervals.reduce(0) { $0 + $1.seconds }.rounded())
            facts["专注期间前台App"] = appFacts(usage)
            facts["此时间段勾选完成的待办"] = SessionProgress.build(sessionID: id, from: data)?.completedTodos.map(\.text) ?? []
        case .day(let day):
            let summary = DailySummary.build(day: day, from: data)
            facts["范围"] = "\(day) 一整天的工作与成果"
            facts["日期"] = day
            facts["实际专注秒数"] = Int(summary.focusSeconds.rounded())
            facts["完整番茄轮数"] = summary.completedSessions
            facts["完成的待办"] = summary.completedTodos.map(\.text)
            facts["当天安排的待办"] = summary.todos.map { todo -> [String: String] in
                let status: String
                if todo.completionDay == day {
                    status = "当日完成"
                } else if let completionDay = todo.completionDay, completionDay > day {
                    status = "当时未完成，后续于 \(completionDay) 完成"
                } else if todo.effectiveScheduledDay > day {
                    status = "当时未完成，后续结转到 \(todo.effectiveScheduledDay)"
                } else if todo.isCompleted {
                    status = "此前已完成"
                } else {
                    status = "尚未完成"
                }
                return ["文字": todo.text, "状态": status]
            }
            facts["尚未完成的待办"] = summary.todos.filter {
                $0.completionDay.map { $0 > day } ?? true
            }.map(\.text)
            facts["专注期间前台App"] = appFacts(data.usage.filter { $0.localDay == day })
            let dayIDs = Set(data.intervals.filter { $0.localDay == day }.map(\.sessionID))
            facts["各轮投入与目标"] = data.sessions.filter { dayIDs.contains($0.id) }
                .sorted { $0.startedAt < $1.startedAt }.compactMap { session -> [String: Any]? in
                    guard let progress = SessionProgress.build(sessionID: session.id, from: data, day: day) else { return nil }
                    return ["开始时间": ISO8601DateFormatter().string(from: session.startedAt),
                            "目标（不代表完成）": session.goal ?? "",
                            "当日实际专注秒数": Int(progress.focusSeconds.rounded()),
                            "专注期间勾选完成的待办": progress.completedTodos.map(\.text)]
                }
            facts["各轮工作与AI成果"] = data.workRecords.filter { $0.localDay == day && $0.sessionID != nil }
                .sorted { $0.updatedAt < $1.updatedAt }.map { item -> [String: Any] in
                    var entry: [String: Any] = ["用户描述": item.userText, "图片数量": item.images.count]
                    if let session = data.sessions.first(where: { $0.id == item.sessionID }) {
                        entry["开始时间"] = ISO8601DateFormatter().string(from: session.startedAt)
                        entry["实际专注秒数"] = Int(data.intervals.filter { $0.sessionID == session.id && $0.localDay == day }.reduce(0) { $0 + $1.seconds }.rounded())
                    }
                    if let summary = item.summary, let id = item.sessionID,
                       summary.contextDigest == build(for: .session(id), from: data).digest {
                        entry["已有AI总结"] = summary.content.markdown
                    }
                    return entry
                }
        }
        facts["用户补充的工作与成果"] = record?.userText ?? ""
        facts["当前附图名称"] = record?.images.map(\.name) ?? []
        facts["记录边界"] = "目标是计划，App 时长是投入，二者都不能证明任务完成；具体成果仅依据勾选完成的待办、用户描述或图片。材料不足时只记录投入，待确认最多提示一句，不要反复要求用户填写。"
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
