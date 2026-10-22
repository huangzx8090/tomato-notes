import Foundation

public enum TimerStage: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    public var label: String {
        switch self {
        case .focus: "专注"
        case .shortBreak: "短休息"
        case .longBreak: "长休息"
        }
    }
}

public enum TimerPhase: String, Codable, Sendable {
    case idle, running, paused, completed
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

public struct Hotkey: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var letter: String
    public var modifier: String

    public init(enabled: Bool = true, letter: String, modifier: String = "controlOption") {
        self.enabled = enabled
        self.letter = letter
        self.modifier = modifier
    }
}

public struct AppSettings: Codable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var longBreakEvery = 4
    public var soundEnabled = true
    public var notificationsEnabled = true
    public var recordingEnabled = true
    public var allowClamshellWithExternalDisplay = true
    public var showDockIcon = false
    public var glassControlsEnabled = true
    public var appearance: AppAppearance = .system
    public var focusGuard = FocusGuardSettings()
    public var review = ReviewSettings()
    public var ai = AISettings()
    public var timerHotkey = Hotkey(letter: "P")
    public var todoHotkey = Hotkey(letter: "T")
    public var noteHotkey = Hotkey(letter: "N")

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
        case soundEnabled, notificationsEnabled, recordingEnabled, allowClamshellWithExternalDisplay
        case showDockIcon, glassControlsEnabled, appearance, focusGuard, review, ai
        case timerHotkey, todoHotkey, noteHotkey
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        shortBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        longBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        longBreakEvery = try values.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? 4
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        recordingEnabled = try values.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? true
        allowClamshellWithExternalDisplay = try values.decodeIfPresent(Bool.self, forKey: .allowClamshellWithExternalDisplay) ?? true
        showDockIcon = try values.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        glassControlsEnabled = try values.decodeIfPresent(Bool.self, forKey: .glassControlsEnabled) ?? true
        appearance = AppAppearance(rawValue: try values.decodeIfPresent(String.self, forKey: .appearance) ?? "") ?? .system
        focusGuard = try values.decodeIfPresent(FocusGuardSettings.self, forKey: .focusGuard) ?? FocusGuardSettings()
        review = try values.decodeIfPresent(ReviewSettings.self, forKey: .review) ?? ReviewSettings()
        ai = try values.decodeIfPresent(AISettings.self, forKey: .ai) ?? AISettings()
        timerHotkey = try values.decodeIfPresent(Hotkey.self, forKey: .timerHotkey) ?? Hotkey(letter: "P")
        todoHotkey = try values.decodeIfPresent(Hotkey.self, forKey: .todoHotkey) ?? Hotkey(letter: "T")
        noteHotkey = try values.decodeIfPresent(Hotkey.self, forKey: .noteHotkey) ?? Hotkey(letter: "N")
    }

    public func duration(for stage: TimerStage) -> Double {
        switch stage {
        case .focus: Double(focusMinutes * 60)
        case .shortBreak: Double(shortBreakMinutes * 60)
        case .longBreak: Double(longBreakMinutes * 60)
        }
    }
}

public struct TimerSnapshot: Codable, Sendable {
    public var stage: TimerStage = .focus
    public var phase: TimerPhase = .idle
    public var nextStage: TimerStage? = nil
    public var targetSeconds: Double = 25 * 60
    public var remainingSeconds: Double = 25 * 60
    public var completedInSet = 0
    public var sessionID: UUID? = nil
    public var pauseReason: String? = nil
    public var updatedAt = Date()

    public init() {}
}

public struct FocusSession: Codable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var endedLocalDay: String?
    public var endTimeZoneID: String?
    public var completed: Bool
    public var endReason: String?
    public var goal: String?

    public init(id: UUID = UUID(), startedAt: Date, goal: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.endedLocalDay = nil
        self.endTimeZoneID = nil
        self.completed = false
        self.endReason = nil
        let trimmed = goal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.goal = trimmed.isEmpty ? nil : String(trimmed.prefix(300))
    }
}

public struct FocusInterval: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var sessionID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var localDay: String
    public var timeZoneID: String
    public var seconds: Double
}

public enum UsageKind: String, Codable, Sendable {
    case app, unattributed, disabled
}

public struct AppIdentity: Equatable, Sendable {
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct AppUsageSegment: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var sessionID: UUID
    public var kind: UsageKind
    public var appName: String?
    public var bundleID: String?
    public var startedAt: Date
    public var endedAt: Date
    public var localDay: String
    public var timeZoneID: String
    public var seconds: Double
}

public struct TodoItem: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var text: String
    public var localDay: String
    public var createdAt = Date()
    public var completedAt: Date? = nil

    public var isCompleted: Bool { completedAt != nil }

    public init(text: String, localDay: String, createdAt: Date = Date()) {
        self.text = text
        self.localDay = localDay
        self.createdAt = createdAt
    }
}

public struct StickyNote: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var text = ""
    public var createdAt = Date()
    public var updatedAt = Date()
    public var x: Double? = nil
    public var y: Double? = nil
    public var width = 320.0
    public var height = 360.0
    public var isOpen = true
    public var localDay: String?
    public var continuedFromNoteID: UUID?

    public var title: String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新便签" : String(trimmed.prefix(24))
    }

    public init(at date: Date = Date(), calendar: Calendar = .current) {
        createdAt = date
        updatedAt = date
        localDay = LocalTime.dayKey(date, calendar: calendar)
    }

    public func dayKey(calendar: Calendar = .current) -> String {
        // 老便签没有日期字段，按创建时间归档；打开和编辑不会改变所属日期。
        localDay ?? LocalTime.dayKey(createdAt, calendar: calendar)
    }
}

public struct AppData: Codable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion = currentSchemaVersion
    public var settings = AppSettings()
    public var timer = TimerSnapshot()
    public var sessions: [FocusSession] = []
    public var intervals: [FocusInterval] = []
    public var usage: [AppUsageSegment] = []
    public var todos: [TodoItem] = []
    public var notes: [StickyNote] = []
    public var workRecords: [WorkRecord] = []
    public var lastReviewAttemptDay: String?
    public var lastReviewError: String?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, settings, timer, sessions, intervals, usage, todos, notes, workRecords, lastReviewAttemptDay, lastReviewError
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        settings = try values.decode(AppSettings.self, forKey: .settings)
        timer = try values.decode(TimerSnapshot.self, forKey: .timer)
        sessions = try values.decode([FocusSession].self, forKey: .sessions)
        intervals = try values.decode([FocusInterval].self, forKey: .intervals)
        usage = try values.decode([AppUsageSegment].self, forKey: .usage)
        todos = try values.decode([TodoItem].self, forKey: .todos)
        notes = try values.decode([StickyNote].self, forKey: .notes)
        workRecords = try values.decodeIfPresent([WorkRecord].self, forKey: .workRecords) ?? []
        lastReviewAttemptDay = try values.decodeIfPresent(String.self, forKey: .lastReviewAttemptDay)
        lastReviewError = try values.decodeIfPresent(String.self, forKey: .lastReviewError)
    }
}
