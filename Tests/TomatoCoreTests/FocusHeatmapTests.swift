import Foundation
import Testing
@testable import TomatoCore

struct FocusHeatmapTests {
    @Test func aggregatesSavedLocalDaysAndMatchesDailySummaryToSecondPrecision() throws {
        let calendar = makeCalendar(timeZone: "Asia/Shanghai")
        let today = makeDate(2026, 10, 23, calendar: calendar)
        let sessionID = UUID()
        let intervals = [
            makeInterval(sessionID: sessionID, localDay: "2026-10-22", seconds: 1_799.75),
            makeInterval(sessionID: sessionID, localDay: "2026-10-22", seconds: 0.5),
            makeInterval(sessionID: sessionID, localDay: "2026-10-23", seconds: 61.125),
            makeInterval(sessionID: sessionID, localDay: "2026-10-24", seconds: 900)
        ]
        var data = AppData()
        data.intervals = intervals

        let range = FocusHeatmapRange.build(intervals: intervals, weekCount: 13, today: today, calendar: calendar)
        let previousDay = try #require(day("2026-10-22", in: range))
        let currentDay = try #require(day("2026-10-23", in: range))
        let futureDay = try #require(day("2026-10-24", in: range))

        #expect(previousDay.seconds == 1_800.25)
        #expect(currentDay.seconds == DailySummary.build(day: currentDay.day, from: data, calendar: calendar).focusSeconds)
        #expect(futureDay.isFuture && futureDay.seconds == 0)
        #expect(range.totalSeconds == previousDay.seconds + currentDay.seconds)
        #expect(range.activeDays == 2)
    }

    @Test func intensityUsesFixedBoundariesAndKeepsSubMinuteSeconds() {
        let values: [(Double, Int)] = [
            (0, 0), (0.25, 1), (59.99, 1), (1_799.99, 1),
            (1_800, 2), (3_599.99, 2), (3_600, 3), (7_199.99, 3), (7_200, 4)
        ]
        for (seconds, expected) in values {
            let day = FocusHeatmapDay(day: "2026-10-23", date: Date(), seconds: seconds,
                                      isToday: true, isFuture: false)
            #expect(day.intensity == expected)
            #expect(day.seconds == seconds)
        }
    }

    @Test func onlyRecordedFocusIntervalsCountIncludingEarlyEndedRounds() throws {
        let calendar = makeCalendar(timeZone: "Asia/Shanghai")
        let today = makeDate(2026, 10, 23, calendar: calendar)
        let sessionID = UUID()
        let intervals = [
            // 提前结束的轮次仅有实际记录的 73.5 秒。
            makeInterval(sessionID: sessionID, localDay: "2026-10-23", seconds: 73.5),
            // 暂停与休息时段没有 FocusInterval，因此不会计入。
            makeInterval(sessionID: sessionID, localDay: "2026-10-23", seconds: 12.25)
        ]
        let range = FocusHeatmapRange.build(intervals: intervals, weekCount: 1, today: today, calendar: calendar)
        let focusDay = try #require(day("2026-10-23", in: range))
        #expect(focusDay.seconds == 85.75)
        #expect(focusDay.intensity == 1)
    }

    @Test func savedLocalDayDoesNotMoveWhenDisplayCalendarTimeZoneChanges() throws {
        let savedCalendar = makeCalendar(timeZone: "America/Los_Angeles")
        let displayCalendar = makeCalendar(timeZone: "Asia/Shanghai")
        let today = makeDate(2026, 10, 23, calendar: displayCalendar)
        let interval = FocusInterval(sessionID: UUID(),
                                     startedAt: makeDate(2026, 10, 23, 1, calendar: savedCalendar),
                                     endedAt: makeDate(2026, 10, 23, 1, calendar: savedCalendar).addingTimeInterval(120),
                                     localDay: "2026-10-22", timeZoneID: "America/Los_Angeles", seconds: 120)
        let range = FocusHeatmapRange.build(intervals: [interval], weekCount: 13, today: today,
                                            calendar: displayCalendar)
        #expect(try #require(day("2026-10-22", in: range)).seconds == 120)
        #expect(try #require(day("2026-10-23", in: range)).seconds == 0)
    }

    @Test func calendarProgressionIncludesLeapDayYearBoundaryAndDST() throws {
        let utc = makeCalendar(timeZone: "UTC")
        let leapRange = FocusHeatmapRange.build(intervals: [], weekCount: 1,
                                                today: makeDate(2024, 3, 1, calendar: utc), calendar: utc)
        #expect(try #require(day("2024-02-29", in: leapRange)).date != Date.distantPast)

        let yearRange = FocusHeatmapRange.build(intervals: [], weekCount: 1,
                                                today: makeDate(2025, 1, 2, calendar: utc), calendar: utc)
        #expect(yearRange.weeks[0].days.map(\.day) == [
            "2024-12-30", "2024-12-31", "2025-01-01", "2025-01-02", "2025-01-03", "2025-01-04", "2025-01-05"
        ])

        let eastern = makeCalendar(timeZone: "America/New_York")
        let dstRange = FocusHeatmapRange.build(intervals: [], weekCount: 3,
                                               today: makeDate(2025, 3, 17, calendar: eastern), calendar: eastern)
        let march9 = try #require(day("2025-03-09", in: dstRange))
        let march10 = try #require(day("2025-03-10", in: dstRange))
        #expect(eastern.dateComponents([.day], from: march9.date, to: march10.date).day == 1)
        #expect(march10.date.timeIntervalSince(march9.date) == 23 * 60 * 60)
    }

    @Test func futureDaysAreMarkedAndExcludedFromRangeTotals() throws {
        let calendar = makeCalendar(timeZone: "UTC")
        let today = makeDate(2026, 10, 23, calendar: calendar)
        let intervals = [makeInterval(sessionID: UUID(), localDay: "2026-10-24", seconds: 900)]
        let range = FocusHeatmapRange.build(intervals: intervals, weekCount: 1, today: today, calendar: calendar)
        let future = try #require(day("2026-10-24", in: range))
        #expect(future.isFuture)
        #expect(future.seconds == 0)
        #expect(range.totalSeconds == 0)
        #expect(range.activeDays == 0)
    }

    @Test func fiftyThreeWeekPagesAreAdjacentWithoutOverlapOrMissingDates() throws {
        let calendar = makeCalendar(timeZone: "America/New_York")
        let today = makeDate(2026, 10, 23, calendar: calendar)
        let recent = FocusHeatmapRange.build(intervals: [], weekCount: 53, pageOffset: 0,
                                             today: today, calendar: calendar)
        let previous = FocusHeatmapRange.build(intervals: [], weekCount: 53, pageOffset: 1,
                                               today: today, calendar: calendar)
        let older = FocusHeatmapRange.build(intervals: [], weekCount: 53, pageOffset: 2,
                                            today: today, calendar: calendar)
        let recentDays = recent.weeks.flatMap(\.days).map(\.day)
        let previousDays = previous.weeks.flatMap(\.days).map(\.day)
        let olderDays = older.weeks.flatMap(\.days).map(\.day)

        #expect(recentDays.count == 371 && previousDays.count == 371 && olderDays.count == 371)
        #expect(Set(recentDays).count == recentDays.count)
        #expect(Set(previousDays).count == previousDays.count)
        #expect(Set(olderDays).count == olderDays.count)
        #expect(Set(recentDays).isDisjoint(with: previousDays))
        #expect(Set(previousDays).isDisjoint(with: olderDays))
        #expect(addDays(to: previous.endDay, count: 1, calendar: calendar) == recent.startDay)
        #expect(addDays(to: older.endDay, count: 1, calendar: calendar) == previous.startDay)
        #expect(recent.startDay == recent.weeks[0].days[0].day)
        #expect(recent.endDay == recent.weeks[52].days[6].day)
    }

    @Test func rangeTotalsEqualIncludedIntervalSeconds() {
        let calendar = makeCalendar(timeZone: "UTC")
        let today = makeDate(2026, 10, 23, calendar: calendar)
        let intervals = [
            makeInterval(sessionID: UUID(), localDay: "2026-08-01", seconds: 25.125),
            makeInterval(sessionID: UUID(), localDay: "2026-09-01", seconds: 1_800.5),
            makeInterval(sessionID: UUID(), localDay: "2026-10-23", seconds: 7_200.25),
            makeInterval(sessionID: UUID(), localDay: "2026-10-24", seconds: 999)
        ]
        let range = FocusHeatmapRange.build(intervals: intervals, weekCount: 13, today: today, calendar: calendar)
        let expected = intervals.filter { $0.localDay >= range.startDay && $0.localDay <= "2026-10-23" }
            .reduce(0) { $0 + $1.seconds }
        #expect(range.totalSeconds == expected)
    }

    @Test func buildPerformanceForOneYearAndThreeYearsOfSyntheticIntervals() {
        let calendar = makeCalendar(timeZone: "UTC")
        let today = makeDate(2026, 10, 23, calendar: calendar)
        let samples: [(label: String, dayCount: Int)] = [("1 年", 365), ("3 年", 1_095)]

        for sample in samples {
            let intervals = makeSyntheticIntervals(dayCount: sample.dayCount, today: today, calendar: calendar)
            let start = ProcessInfo.processInfo.systemUptime
            let range = FocusHeatmapRange.build(intervals: intervals, weekCount: 53, today: today, calendar: calendar)
            let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            print(String(format: "FocusHeatmap 性能：%@，%d intervals，build %.3f ms，%d 周",
                         sample.label, intervals.count, elapsedMilliseconds, range.weeks.count))
            #expect(range.weeks.count == 53)
            #expect(range.activeDays > 0)
        }
    }

    private func day(_ key: String, in range: FocusHeatmapRange) -> FocusHeatmapDay? {
        range.weeks.lazy.flatMap(\.days).first { $0.day == key }
    }

    private func makeCalendar(timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0,
                          calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeInterval(sessionID: UUID, localDay: String, seconds: Double) -> FocusInterval {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return FocusInterval(sessionID: sessionID, startedAt: start, endedAt: start.addingTimeInterval(seconds),
                             localDay: localDay, timeZoneID: "UTC", seconds: seconds)
    }

    private func makeSyntheticIntervals(dayCount: Int, today: Date, calendar: Calendar) -> [FocusInterval] {
        guard let firstDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: calendar.startOfDay(for: today)) else {
            return []
        }
        var intervals: [FocusInterval] = []
        intervals.reserveCapacity(dayCount * 4)
        for dayOffset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else { continue }
            let localDay = LocalTime.dayKey(date, calendar: calendar)
            for segment in 0..<4 {
                let start = calendar.date(byAdding: .minute, value: segment * 30, to: date) ?? date
                intervals.append(FocusInterval(sessionID: UUID(), startedAt: start,
                                                endedAt: start.addingTimeInterval(600), localDay: localDay,
                                                timeZoneID: calendar.timeZone.identifier, seconds: 600))
            }
        }
        return intervals
    }

    private func addDays(to day: String, count: Int, calendar: Calendar) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        return LocalTime.dayKey(calendar.date(byAdding: .day, value: count, to: date)!, calendar: calendar)
    }
}
