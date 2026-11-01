import CryptoKit
import Foundation
import TomatoCore

struct RankingInterval: Codable, Equatable {
    let id: String
    let startedAt: String
    let endedAt: String
    let effectiveSeconds: Double
}
struct RankingRecord: Codable, Equatable {
    let id: String
    var version: Int
    let startedAt: String
    let endedAt: String?
    let completed: Bool
    let intervals: [RankingInterval]
}
struct QueuedRankingRecord: Codable {
    var record: RankingRecord
    var acknowledged: Bool
    var error: String?
}
struct RankingSyncState: Codable {
    // 按账号和授权版本隔离；重新授权时不能把旧队列换版本上传。
    var scopes: [String: [String: QueuedRankingRecord]] = [:]
}

final class RankingSyncStore {
    let url: URL
    private(set) var state: RankingSyncState

    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(RankingSyncState.self, from: Data(contentsOf: url))
        } else { state = RankingSyncState() }
    }
    func set(_ items: [String: QueuedRankingRecord], scope: String) throws {
        var next = state
        // 只保留当前授权队列，避免长期保留已失效的上传快照。
        let prefix = scope.split(separator: ":").first.map(String.init) ?? scope
        next.scopes = next.scopes.filter { !$0.key.hasPrefix(prefix + ":") || $0.key == scope }
        next.scopes[scope] = items
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        state = next
    }
}

enum RankingSync {
    static func scope(userID: String, consentVersion: Int) -> String {
        SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined() + ":\(consentVersion)"
    }

    static func parse(_ text: String) -> Date? {
        // ISO8601DateFormatter 会把服务端微秒截断为毫秒，可能导致授权前区间被误上传。
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? Date(text, strategy: fractional)) ?? (try? Date(text, strategy: .iso8601))
    }
    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
    private static func floorMillis(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000) }
    private static func ceilMillis(_ date: Date) -> Date { Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 * 1000) / 1000) }

    static func snapshot(session: FocusSession, intervals: [FocusInterval], since: Date,
                         now: Date, remoteID: String, version: Int) -> RankingRecord? {
        // 按毫秒向上取授权开始时间，避免格式化时意外回传授权前的时间。
        let lower = ceilMillis(max(since, now.addingTimeInterval(-89 * 86400)))
        let start = ceilMillis(max(session.startedAt, lower))
        let end = session.endedAt.map(floorMillis)
        guard start <= now, end == nil || (end! >= start && end!.timeIntervalSince(start) <= 7 * 86400) else { return nil }
        let parts = intervals.compactMap { interval -> RankingInterval? in
            guard interval.sessionID == session.id else { return nil }
            let a = ceilMillis(max(interval.startedAt, start))
            let b = floorMillis(min(interval.endedAt, end ?? now))
            let seconds = b.timeIntervalSince(a)
            guard seconds > 0, seconds <= 86400 else { return nil }
            return RankingInterval(id: interval.id.uuidString.lowercased(), startedAt: format(a), endedAt: format(b), effectiveSeconds: seconds)
        }.sorted { $0.id < $1.id }
        guard !parts.isEmpty, parts.count <= 1000 else { return nil }
        return RankingRecord(id: remoteID, version: version, startedAt: format(start), endedAt: end.map(format),
                             completed: session.completed && end != nil, intervals: parts)
    }

    static func makeQueue(data: AppData, since: Date, now: Date, scope: String,
                          existing: [String: QueuedRankingRecord]) -> [String: QueuedRankingRecord] {
        var result = existing
        let groups = Dictionary(grouping: data.intervals, by: \.sessionID)
        for session in data.sessions {
            let key = session.id.uuidString.lowercased()
            let old = result[key]
            // 发送结果未知时必须先重试完全相同的快照，不能复用版本发送新内容。
            if let old, !old.acknowledged { continue }
            let id = old?.record.id ?? remoteID(scope: scope, sessionID: key)
            let version = old?.record.version ?? 1
            guard var record = snapshot(session: session, intervals: groups[session.id] ?? [], since: since,
                                        now: now, remoteID: id, version: version) else { continue }
            if let old {
                if record == old.record { continue }
                record.version += 1
            }
            result[key] = QueuedRankingRecord(record: record, acknowledged: false, error: nil)
        }
        return result
    }

    // 同账号、授权和本地会话在不同客户端使用相同 ID，避免重复计算完成次数。
    static func remoteID(scope: String, sessionID: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("tomato-ranking:\(scope):\(sessionID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let value = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return value.uuidString.lowercased()
    }

    static func uploadBody(version: Int, records: [RankingRecord]) throws -> Data {
        struct Batch: Encodable { let consentVersion: Int; let records: [RankingRecord] }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Batch(consentVersion: version, records: records))
    }
}
