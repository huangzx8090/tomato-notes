import Foundation

public struct FocusHeatmapDay: Identifiable, Sendable, Equatable {
    public let day: String
    public let date: Date
    public let seconds: Double
    public let isToday: Bool
    public let isFuture: Bool

    public var id: String { day }

    public var intensity: Int {
        guard seconds > 0 else { return 0 }
        if seconds < 1_800 { return 1 }
        if seconds < 3_600 { return 2 }
        if seconds < 7_200 { return 3 }
        return 4
    }

    public init(day: String, date: Date, seconds: Double, isToday: Bool, isFuture: Bool) {
        self.day = day
        self.date = date
        self.seconds = seconds
        self.isToday = isToday
        self.isFuture = isFuture
    }
}

public struct FocusHeatmapWeek: Identifiable, Sendable {
    public let days: [FocusHeatmapDay]

    /// 以周一的日期作为稳定标识，同一周在不同分页中保持相同 ID。
    public var id: String { days.first?.day ?? "" }

    public init(days: [FocusHeatmapDay]) {
        self.days = days
    }
}

public struct FocusHeatmapRange: Sendable {
    public let weeks: [FocusHeatmapWeek]
    public let startDay: String
    public let endDay: String
    public let totalSeconds: Double
    public let activeDays: Int

    private init(weeks: [FocusHeatmapWeek], startDay: String, endDay: String,
                 totalSeconds: Double, activeDays: Int) {
        self.weeks = weeks
        self.startDay = startDay
        self.endDay = endDay
        self.totalSeconds = totalSeconds
        self.activeDays = activeDays
    }

    /// `pageOffset == 0` 是包含本周的最近一页，正数逐页向过去移动。
    /// 页面之间以完整自然周相接；周日后的下一个日期总是下一页的周一。
    public static func build(intervals: [FocusInterval], weekCount: Int, pageOffset: Int = 0,
                             today: Date = Date(), calendar: Calendar = .current) -> FocusHeatmapRange {
        let count = max(1, weekCount)
        let offset = max(0, pageOffset)
        let dayStart = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: dayStart) // Gregorian: 周日为 1，周一为 2。
        let daysSinceMonday = (weekday + 5) % 7
        let weeksBeforeStart = offset * count + count - 1
        let daysBeforeStart = daysSinceMonday + weeksBeforeStart * 7
        let rangeStart = calendar.date(byAdding: .day, value: -daysBeforeStart, to: dayStart) ?? dayStart
        let todayKey = LocalTime.dayKey(dayStart, calendar: calendar)

        // 与 DailySummary 使用相同的数据源和归属字段；绝不从轮数或活动记录推算时长。
        var secondsByDay: [String: Double] = [:]
        for interval in intervals {
            secondsByDay[interval.localDay, default: 0] += interval.seconds
        }

        var weeks: [FocusHeatmapWeek] = []
        weeks.reserveCapacity(count)
        var totalSeconds = 0.0
        var activeDays = 0

        for weekIndex in 0..<count {
            var days: [FocusHeatmapDay] = []
            days.reserveCapacity(7)
            for weekdayIndex in 0..<7 {
                let dayOffset = weekIndex * 7 + weekdayIndex
                let date = calendar.date(byAdding: .day, value: dayOffset, to: rangeStart) ?? rangeStart
                let key = LocalTime.dayKey(date, calendar: calendar)
                let isFuture = date > dayStart
                let seconds = isFuture ? 0 : (secondsByDay[key] ?? 0)
                let day = FocusHeatmapDay(day: key, date: date, seconds: seconds,
                                          isToday: key == todayKey, isFuture: isFuture)
                days.append(day)
                totalSeconds += seconds
                if seconds > 0 { activeDays += 1 }
            }
            weeks.append(FocusHeatmapWeek(days: days))
        }

        let startDay = weeks.first?.days.first?.day ?? todayKey
        let endDay = weeks.last?.days.last?.day ?? todayKey
        return FocusHeatmapRange(weeks: weeks, startDay: startDay, endDay: endDay,
                                 totalSeconds: totalSeconds, activeDays: activeDays)
    }
}
