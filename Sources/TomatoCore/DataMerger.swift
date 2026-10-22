import Foundation

public enum DataMergeError: LocalizedError {
    case conflict(String, UUID)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .conflict(let name, let id): "\(name)的 ID \(id) 存在不同内容，已停止合并；请核对原始备份。"
        case .invalid(let message): "数据核对失败：\(message)；未写入目标文件。"
        }
    }
}

public enum DataMerger {
    /// 主数据决定当前计时和设置；其他数据只加入记录。遇到相同 ID 的不同版本时拒绝猜测覆盖。
    public static func merge(primary: AppData, importing sources: [AppData]) throws -> AppData {
        var result = primary
        result.sessions = []
        result.intervals = []
        result.usage = []
        result.todos = []
        result.notes = []
        result.workRecords = []
        for source in [primary] + sources {
            guard (1...AppData.currentSchemaVersion).contains(source.schemaVersion) else { throw RepositoryError.unsupportedVersion(source.schemaVersion) }
            result.sessions = try combine(result.sessions, source.sessions, name: "专注轮次")
            result.intervals = try combine(result.intervals, source.intervals, name: "专注分段")
            result.usage = try combine(result.usage, source.usage, name: "App 分段")
            result.todos = try combine(result.todos, source.todos, name: "待办")
            result.notes = try combine(result.notes, source.notes, name: "便签")
            result.workRecords = try combine(result.workRecords, source.workRecords, name: "成果记录")
        }
        result.schemaVersion = AppData.currentSchemaVersion
        let sessionIDs = Set(result.sessions.map(\.id))
        guard result.sessions.allSatisfy({
                  $0.outsideWhitelistSeconds.map { $0.isFinite && $0 >= 0 } ?? true
              }),
              result.intervals.allSatisfy({ sessionIDs.contains($0.sessionID) && $0.seconds.isFinite && $0.seconds >= 0 }),
              result.usage.allSatisfy({ sessionIDs.contains($0.sessionID) && $0.seconds.isFinite && $0.seconds >= 0 }) else {
            throw DataMergeError.invalid("分段关联或时长无效")
        }
        let days = Set(result.intervals.map(\.localDay) + result.usage.map(\.localDay))
        for day in days {
            let focus = result.intervals.filter { $0.localDay == day }.reduce(0) { $0 + $1.seconds }
            let usage = result.usage.filter { $0.localDay == day }.reduce(0) { $0 + $1.seconds }
            guard abs(focus - usage) < 0.01 else { throw DataMergeError.invalid("\(day) 的专注与 App 时长不一致") }
        }

        let activeID = (result.timer.phase == .running || result.timer.phase == .paused) ? result.timer.sessionID : nil
        for index in result.sessions.indices where result.sessions[index].endedAt == nil && result.sessions[index].id != activeID {
            let id = result.sessions[index].id
            let lastInterval = result.intervals.filter { $0.sessionID == id }.max { $0.endedAt < $1.endedAt }
            let end = lastInterval?.endedAt ?? result.sessions[index].startedAt
            result.sessions[index].endedAt = end
            result.sessions[index].endedLocalDay = lastInterval?.localDay ?? LocalTime.dayKey(end)
            result.sessions[index].endTimeZoneID = lastInterval?.timeZoneID ?? TimeZone.current.identifier
            result.sessions[index].endReason = "数据合并时保留实际记录并结束"
            result.sessions[index].whitelistedBundleIDs = nil
        }
        var engine = TimerEngine(data: result)
        engine.recoverAfterLaunch()
        result = engine.data
        result.sessions.sort { $0.startedAt < $1.startedAt }
        result.intervals.sort { $0.startedAt < $1.startedAt }
        result.usage.sort { $0.startedAt < $1.startedAt }
        result.todos.sort { $0.createdAt < $1.createdAt }
        result.notes.sort { $0.createdAt < $1.createdAt }
        return result
    }

    private static func combine<T: Codable & Identifiable>(_ first: [T], _ second: [T], name: String) throws -> [T] where T.ID == UUID {
        var result: [T] = []
        var byID: [UUID: Data] = [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for item in first + second {
            let bytes = try encoder.encode(item)
            if let existing = byID[item.id] {
                guard existing == bytes else { throw DataMergeError.conflict(name, item.id) }
            } else {
                byID[item.id] = bytes
                result.append(item)
            }
        }
        return result
    }
}
