import Foundation

public struct ReviewSettings: Codable, Sendable, Equatable {
    public var scheduleEnabled = false
    public var autoSummarizeSessions = false
    public var hour = 21
    public var minute = 30
    public init() {}
    public var timeLabel: String { String(format: "%02d:%02d", hour, minute) }

    private enum CodingKeys: String, CodingKey { case scheduleEnabled, autoSummarizeSessions, hour, minute }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scheduleEnabled = try values.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? false
        autoSummarizeSessions = try values.decodeIfPresent(Bool.self, forKey: .autoSummarizeSessions) ?? false
        hour = try values.decodeIfPresent(Int.self, forKey: .hour) ?? 21
        minute = try values.decodeIfPresent(Int.self, forKey: .minute) ?? 30
    }
}

public struct WorkImage: Codable, Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var name: String
    public var createdAt = Date()
    public var fileName: String { "\(id.uuidString).jpg" }
    public init(name: String) { self.name = name }
}

public struct WorkSummary: Codable, Sendable, Equatable {
    public var activities: [String]
    public var outcomes: [String]
    public var nextSteps: [String]
    public var uncertainties: [String]

    public init(activities: [String], outcomes: [String], nextSteps: [String], uncertainties: [String]) {
        self.activities = activities
        self.outcomes = outcomes
        self.nextSteps = nextSteps
        self.uncertainties = uncertainties
    }

    public var markdown: String {
        [("做了什么", activities), ("取得的成果", outcomes), ("待继续", nextSteps), ("待确认", uncertainties)]
            .filter { !$0.1.isEmpty }
            .map { title, lines in "## \(title)\n" + lines.map { "- \($0)" }.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}

public struct AISummary: Codable, Sendable {
    public var content: WorkSummary
    public var model: String
    public var generatedAt: Date
    public var contextDigest: String
    public var imageIDs: [UUID]
    public init(content: WorkSummary, model: String, generatedAt: Date = Date(), contextDigest: String, imageIDs: [UUID]) {
        self.content = content
        self.model = model
        self.generatedAt = generatedAt
        self.contextDigest = contextDigest
        self.imageIDs = imageIDs
    }
}

public struct WorkRecord: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var localDay: String
    public var sessionID: UUID?
    public var userText = ""
    public var images: [WorkImage] = []
    public var summary: AISummary?
    public var autoReviewAttemptedAt: Date?
    public var activityTopic: ActivityTopic?
    public var titleOverride: String?
    public var topicAttemptCount: Int?
    public var topicAttemptDigest: String?
    public var topicAttemptFocusSeconds: Double?
    public var finalTopicAttempted: Bool?
    public var automaticRecordingUsed: Bool?
    public var excludedActivityKeys: [String]?
    public var updatedAt = Date()

    public init(localDay: String, sessionID: UUID? = nil) {
        self.localDay = localDay
        self.sessionID = sessionID
    }
}

public enum WorkScope: Hashable, Sendable {
    case session(UUID)
    case day(String)
    public var key: String {
        switch self {
        case .session(let id): "session-\(id)"
        case .day(let day): "day-\(day)"
        }
    }
}

public enum ReviewSchedule {
    public static func dueDay(at now: Date, settings: ReviewSettings, lastAttemptDay: String?,
                              calendar: Calendar = .current) -> String? {
        guard settings.scheduleEnabled, (0...23).contains(settings.hour), (0...59).contains(settings.minute),
              let target = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: now),
              now >= target else { return nil }
        let day = LocalTime.dayKey(now, calendar: calendar)
        return lastAttemptDay == day ? nil : day
    }
}
