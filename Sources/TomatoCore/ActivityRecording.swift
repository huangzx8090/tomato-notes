import CryptoKit
import Foundation

public struct ActivityRecordingSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var chromeEnabled = true
    public var notesEnabled = true
    public var appUsageEnabled = true
    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, chromeEnabled, notesEnabled, appUsageEnabled }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        chromeEnabled = try values.decodeIfPresent(Bool.self, forKey: .chromeEnabled) ?? true
        notesEnabled = try values.decodeIfPresent(Bool.self, forKey: .notesEnabled) ?? true
        appUsageEnabled = try values.decodeIfPresent(Bool.self, forKey: .appUsageEnabled) ?? true
    }
}

/// 只持久化经清理的标题和网站；完整 URL、窗口 ID 和标签 ID 不进入资料库。
public struct ActivityPage: Equatable, Sendable {
    public let title: String
    public let site: String

    public init?(title: String, url: String, isPrivate: Bool) {
        guard !isPrivate, let components = URLComponents(string: url),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        self.site = host
        self.title = ActivityPrivacy.clean(title, limit: 300)
        guard !self.title.isEmpty else { return nil }
    }
}

public enum ActivityPrivacy {
    public static func clean(_ text: String, limit: Int) -> String {
        var value = text
        // 有的网页直接把完整网址作为标题，避免借标题保存查询参数或路径。
        if let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>]+", options: [.caseInsensitive]) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: value) else { continue }
                let host = URLComponents(string: String(value[range]))?.host ?? "[网址]"
                value.replaceSubrange(range, with: host)
            }
        }
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

public struct FocusActivity: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case chromePage, noteEdited, todoCompleted }
    public var id = UUID()
    public var sessionID: UUID
    public var kind: Kind
    public var title: String
    public var site: String?
    public var detail: String?
    public var sourceID: UUID?
    public var startedAt: Date
    public var endedAt: Date
    public var localDay: String
    public var seconds: Double
    public var focusIntervalID: UUID?
    public var recordingBlockID: UUID?

    public init(sessionID: UUID, kind: Kind, title: String, site: String? = nil, detail: String? = nil,
                sourceID: UUID? = nil, startedAt: Date, endedAt: Date, localDay: String, seconds: Double = 0) {
        self.sessionID = sessionID; self.kind = kind; self.title = title; self.site = site
        self.detail = detail; self.sourceID = sourceID; self.startedAt = startedAt; self.endedAt = endedAt
        self.localDay = localDay; self.seconds = seconds
    }

    public var label: String {
        switch kind {
        case .chromePage: "浏览：\(title)"
        case .noteEdited: "便签变更：\(title)"
        case .todoCompleted: "勾选完成：\(title)"
        }
    }

    public var sourceKey: String {
        kind == .chromePage ? "chrome|\(site ?? "")|\(title)" : "\(kind.rawValue)|\(sourceID?.uuidString ?? "")"
    }
}

public struct ActivityTopic: Codable, Sendable {
    public var groupID: UUID
    public var title: String
    public var confidence: Double
    public var evidenceIDs: [UUID]
    public var model: String
    public var generatedAt: Date
    public init(groupID: UUID = UUID(), title: String, confidence: Double, evidenceIDs: [UUID], model: String, generatedAt: Date = Date()) {
        self.groupID = groupID; self.title = title; self.confidence = confidence
        self.evidenceIDs = evidenceIDs; self.model = model; self.generatedAt = generatedAt
    }
}

public enum ActivityRecorder {
    public static func isRecording(_ data: AppData) -> Bool {
        data.settings.activityRecording.enabled && data.timer.stage == .focus && data.timer.phase == .running && data.timer.sessionID != nil
    }

    public static func activities(sessionID: UUID, in data: AppData, day: String? = nil) -> [FocusActivity] {
        data.focusActivities.filter { $0.sessionID == sessionID && (day == nil || $0.localDay == day) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public static func appendPage(_ page: ActivityPage, sessionID: UUID, start: Date, end: Date, to data: inout AppData) {
        guard isRecording(data), data.settings.activityRecording.chromeEnabled, data.timer.sessionID == sessionID,
              end > start, end.timeIntervalSince(start) <= 15 else { return }
        let key = "chrome|\(page.site)|\(page.title)"
        guard !isExcluded(key, sessionID: sessionID, in: data) else { return }
        // 只累计两次相同前台采样间、且已经被计时引擎确认的专注分段；不补记暂停或休息。
        for interval in data.intervals.filter({ $0.sessionID == sessionID && $0.endedAt > start && $0.startedAt < end }) {
            let lower = max(start, interval.startedAt), upper = min(end, interval.endedAt)
            let seconds = upper.timeIntervalSince(lower)
            guard seconds > 0 else { continue }
            if let index = data.focusActivities.indices.last,
               data.focusActivities[index].sessionID == sessionID, data.focusActivities[index].kind == .chromePage,
               data.focusActivities[index].title == page.title, data.focusActivities[index].site == page.site,
               data.focusActivities[index].localDay == interval.localDay,
               abs(data.focusActivities[index].endedAt.timeIntervalSince(lower)) < 0.1 {
                data.focusActivities[index].endedAt = upper
                data.focusActivities[index].seconds += seconds
            } else {
                data.focusActivities.append(FocusActivity(sessionID: sessionID, kind: .chromePage, title: page.title,
                    site: page.site, startedAt: lower, endedAt: upper, localDay: interval.localDay, seconds: seconds))
            }
        }
    }

    public static func recordNote(_ note: StickyNote, previousText: String, at now: Date, blockID: UUID? = nil, in data: inout AppData) {
        guard isRecording(data), data.settings.activityRecording.notesEnabled, let sessionID = data.timer.sessionID else { return }
        guard !isExcluded("noteEdited|\(note.id.uuidString)", sessionID: sessionID, in: data) else { return }
        let previous = previousText.components(separatedBy: .newlines)
        let current = note.text.components(separatedBy: .newlines)
        let inserted = current.difference(from: previous).compactMap { change -> String? in
            if case .insert(_, let line, _) = change { return line }; return nil
        }.joined(separator: "\n")
        let detail = ActivityPrivacy.clean(inserted, limit: 1200)
        let title = ActivityPrivacy.clean(detail.components(separatedBy: .newlines).first ?? "", limit: 60)
        let intervalID = data.intervals.last(where: { $0.sessionID == sessionID })?.id
        let day = LocalTime.dayKey(now)
        let existing = data.focusActivities.lastIndex(where: { $0.sessionID == sessionID && $0.kind == .noteEdited && $0.sourceID == note.id && $0.localDay == day && $0.focusIntervalID == intervalID && $0.recordingBlockID == blockID })
        guard note.text != previousText || existing != nil else { return }
        if let index = existing {
            data.focusActivities[index].title = title.isEmpty ? "便签文字调整" : title
            data.focusActivities[index].detail = detail.isEmpty ? "调整了便签文字，未记录新增内容。" : detail
            data.focusActivities[index].endedAt = now
        } else {
            var activity = FocusActivity(sessionID: sessionID, kind: .noteEdited,
                title: title.isEmpty ? "便签文字调整" : title, detail: detail.isEmpty ? "调整了便签文字，未记录新增内容。" : detail,
                sourceID: note.id, startedAt: now, endedAt: now, localDay: day)
            activity.focusIntervalID = intervalID
            activity.recordingBlockID = blockID
            data.focusActivities.append(activity)
        }
    }

    public static func recordTodo(_ todo: TodoItem, at now: Date, in data: inout AppData) {
        guard isRecording(data), data.settings.activityRecording.notesEnabled, let sessionID = data.timer.sessionID else { return }
        guard !isExcluded("todoCompleted|\(todo.id.uuidString)", sessionID: sessionID, in: data) else { return }
        data.focusActivities.removeAll { $0.sessionID == sessionID && $0.kind == .todoCompleted && $0.sourceID == todo.id }
        guard todo.isCompleted else { return }
        data.focusActivities.append(FocusActivity(sessionID: sessionID, kind: .todoCompleted,
            title: ActivityPrivacy.clean(todo.text, limit: 300), sourceID: todo.id, startedAt: now, endedAt: now, localDay: LocalTime.dayKey(now)))
    }

    public static func displayTitle(session: FocusSession, in data: AppData) -> String {
        let record = ReviewContextBuilder.record(for: .session(session.id), in: data)
        return record?.titleOverride ?? session.goal.flatMap { $0.isEmpty ? nil : $0 } ?? record?.activityTopic?.title ?? "一段专心的时间"
    }

    private static func isExcluded(_ key: String, sessionID: UUID, in data: AppData) -> Bool {
        ReviewContextBuilder.record(for: .session(sessionID), in: data)?.excludedActivityKeys?.contains(key) == true
    }
}

public struct ActivityTopicContext: Sendable {
    public let text: String
    public let digest: String
    public let evidenceIDs: Set<UUID>
    public let candidateIDs: Set<UUID>

    public static func build(sessionID: UUID, from data: AppData) -> ActivityTopicContext {
        let settings = data.settings.activityRecording
        let evidence = ActivityRecorder.activities(sessionID: sessionID, in: data).filter {
            $0.kind == .chromePage ? (settings.chromeEnabled && $0.seconds >= 15) : settings.notesEnabled
        }
        let limited = Array(evidence.suffix(60))
        var candidates: [[String: String]] = []
        var seen: Set<UUID> = []
        for record in data.workRecords.reversed() where record.sessionID != sessionID {
            guard let topic = record.activityTopic, !seen.contains(topic.groupID) else { continue }
            seen.insert(topic.groupID)
            candidates.append(["id": topic.groupID.uuidString, "名称": record.titleOverride ?? topic.title,
                "用户纠正": record.titleOverride == nil ? "否" : "是"])
            if candidates.count >= 15 { break }
        }
        let current = ReviewContextBuilder.record(for: .session(sessionID), in: data)?.activityTopic
        if let current, !seen.contains(current.groupID) {
            candidates.append(["id": current.groupID.uuidString, "名称": current.title, "用户纠正": "否"])
            seen.insert(current.groupID)
        }
        let facts: [String: Any] = [
            "用户设定的目标（计划，不代表实际活动）": data.sessions.first { $0.id == sessionID }?.goal ?? "",
            "本轮已观察到的材料": limited.map { item -> [String: Any] in
                ["id": item.id.uuidString, "类型": item.kind.rawValue, "标题": item.title,
                 "网站": item.site ?? "", "变更文字": item.detail ?? "", "前台秒数": Int(item.seconds)]
            },
            "已有主题（仅供归类命名，不能当作本轮证据）": candidates,
            "前台App（只说明工具，不是主题依据）": settings.appUsageEnabled && data.settings.recordingEnabled
                ? (SessionProgress.build(sessionID: sessionID, from: data)?.apps.map { ["App": $0.name, "秒数": Int($0.seconds)] } ?? []) : []
        ]
        let bytes = (try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])) ?? Data()
        // 时长增长不算新材料；只在出现新页面或便签变化时重新判断。
        let semantic = limited.map { "\($0.id)|\($0.title)|\($0.detail ?? "")" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(semantic.utf8)).map { String(format: "%02x", $0) }.joined()
        return ActivityTopicContext(text: String(decoding: bytes, as: UTF8.self), digest: digest,
                                    evidenceIDs: Set(limited.map(\.id)), candidateIDs: seen)
    }
}

public enum ActivityTopicPolicy {
    public static func shouldIdentify(sessionID: UUID, in data: AppData, final: Bool = false) -> Bool {
        guard data.settings.activityRecording.enabled,
              let progress = SessionProgress.build(sessionID: sessionID, from: data),
              progress.focusSeconds >= (final ? 60 : 120) else { return false }
        let record = ReviewContextBuilder.record(for: .session(sessionID), in: data)
        guard record?.titleOverride == nil, (record?.topicAttemptCount ?? 0) < (final ? 5 : 4) else { return false }
        let context = ActivityTopicContext.build(sessionID: sessionID, from: data)
        guard !context.evidenceIDs.isEmpty, record?.topicAttemptDigest != context.digest else { return false }
        let materials = data.focusActivities.filter { context.evidenceIDs.contains($0.id) }
        guard materials.contains(where: { $0.kind != .chromePage }) || materials.reduce(0, { $0 + $1.seconds }) >= 45 else { return false }
        if final { return progress.session.endedAt != nil && record?.finalTopicAttempted != true }
        guard data.timer.sessionID == sessionID, ActivityRecorder.isRecording(data) else { return false }
        return record?.topicAttemptFocusSeconds == nil || progress.focusSeconds - (record?.topicAttemptFocusSeconds ?? 0) >= 300
    }
}

public struct ActivityTopicGroup: Identifiable {
    public let id: String
    public let title: String
    public var seconds: Double
    public var sessions: [FocusSession]
    public static func build(day: String, sessions: [FocusSession], from data: AppData) -> [ActivityTopicGroup] {
        var groups: [ActivityTopicGroup] = []
        for session in sessions {
            let record = ReviewContextBuilder.record(for: .session(session.id), in: data)
            let title = ActivityRecorder.displayTitle(session: session, in: data)
            let id = record?.activityTopic?.groupID.uuidString ?? "session-\(session.id)"
            let key = id + "|" + title
            let seconds = SessionProgress.build(sessionID: session.id, from: data, day: day)?.focusSeconds ?? 0
            if let index = groups.firstIndex(where: { $0.id == key }) {
                groups[index].seconds += seconds; groups[index].sessions.append(session)
            } else { groups.append(ActivityTopicGroup(id: key, title: title, seconds: seconds, sessions: [session])) }
        }
        return groups
    }
}
