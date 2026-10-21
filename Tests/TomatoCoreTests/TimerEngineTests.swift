import Foundation
import Testing
@testable import TomatoCore

struct TimerEngineTests {
    private let start = ISO8601DateFormatter().date(from: "2026-10-21T08:00:00Z")!
    private let appA = AppIdentity(name: "编辑器", bundleID: "test.editor")
    private let appB = AppIdentity(name: "浏览器", bundleID: "test.browser")

    @Test func testDefaultsAndPauseResumeExcludeGap() {
        var engine = TimerEngine(data: AppData())
        expectEqual(engine.data.settings.focusMinutes, 25)
        expectEqual(engine.data.settings.shortBreakMinutes, 5)
        expectEqual(engine.data.settings.longBreakMinutes, 15)
        expectEqual(engine.data.settings.longBreakEvery, 4)
        engine.start(at: start)
        _ = engine.advance(seconds: 10.25, endingAt: start.addingTimeInterval(10.25), app: appA, recordingEnabled: true)
        engine.pause(reason: "手动暂停", at: start.addingTimeInterval(10.25))
        _ = engine.advance(seconds: 100, endingAt: start.addingTimeInterval(110.25), app: appB, recordingEnabled: true)
        expectEqual(engine.data.timer.remainingSeconds, 1489.75, accuracy: 0.0001)
        engine.start(at: start.addingTimeInterval(110.25))
        _ = engine.advance(seconds: 4.75, endingAt: start.addingTimeInterval(115), app: appB, recordingEnabled: true)
        expectEqual(engine.data.intervals.reduce(0) { $0 + $1.seconds }, 15, accuracy: 0.0001)
        expectEqual(engine.data.intervals.count, 2)
        expectEqual(engine.data.usage.reduce(0) { $0 + $1.seconds }, 15, accuracy: 0.0001)
    }

    @Test func testFourRoundsWaitForUserAndSetResetsAfterLongBreak() {
        var engine = TimerEngine(data: AppData())
        var time = start
        for round in 1...4 {
            engine.start(at: time)
            time = time.addingTimeInterval(1500)
            expectTrue(engine.advance(seconds: 1500, endingAt: time, app: appA, recordingEnabled: true))
            expectEqual(engine.data.timer.phase, .completed)
            expectEqual(engine.data.timer.completedInSet, round)
            expectEqual(engine.data.timer.nextStage, round == 4 ? .longBreak : .shortBreak)
            expectFalse(engine.advance(seconds: 1500, endingAt: time, app: appA, recordingEnabled: true))
            expectEqual(engine.data.sessions.count, round)
            engine.start(at: time)
            let rest = round == 4 ? 900.0 : 300.0
            time = time.addingTimeInterval(rest)
            _ = engine.advance(seconds: rest, endingAt: time, app: appA, recordingEnabled: true)
            expectEqual(engine.data.timer.phase, .completed)
            expectEqual(engine.data.timer.nextStage, .focus)
        }
        expectEqual(engine.data.timer.completedInSet, 0)
        expectEqual(engine.data.intervals.reduce(0) { $0 + $1.seconds }, 6000, accuracy: 0.001)
    }

    @Test func testEarlyEndSavesActualTimeWithoutCompleteRound() {
        var engine = TimerEngine(data: AppData())
        engine.start(at: start)
        _ = engine.advance(seconds: 42.8, endingAt: start.addingTimeInterval(42.8), app: appA, recordingEnabled: true)
        engine.pause(reason: "锁屏已暂停", at: start.addingTimeInterval(42.8))
        engine.endEarly(at: start.addingTimeInterval(200))
        engine.endEarly(at: start.addingTimeInterval(201))
        expectEqual(engine.data.timer.phase, .idle)
        expectEqual(engine.data.sessions.count, 1)
        expectFalse(engine.data.sessions[0].completed)
        expectEqual(engine.data.timer.completedInSet, 0)
        expectEqual(engine.data.intervals.reduce(0) { $0 + $1.seconds }, 42.8, accuracy: 0.0001)
    }

    @Test func testAppAccountingHasExactlyOneSourcePerSecond() {
        var data = AppData()
        data.settings.focusMinutes = 1
        var engine = TimerEngine(data: data)
        engine.start(at: start)
        _ = engine.advance(seconds: 20, endingAt: start.addingTimeInterval(20), app: appA, recordingEnabled: true)
        _ = engine.advance(seconds: 10, endingAt: start.addingTimeInterval(30), app: appB, recordingEnabled: true)
        _ = engine.advance(seconds: 15, endingAt: start.addingTimeInterval(45), app: nil, recordingEnabled: true)
        _ = engine.advance(seconds: 15, endingAt: start.addingTimeInterval(60), app: appA, recordingEnabled: false)
        let summary = DailySummary.build(day: LocalTime.dayKey(start), from: engine.data)
        expectEqual(summary.focusSeconds, 60, accuracy: 0.0001)
        expectEqual(summary.apps.reduce(0) { $0 + $1.seconds }, 30, accuracy: 0.0001)
        expectEqual(summary.unattributedSeconds, 15, accuracy: 0.0001)
        expectEqual(summary.disabledSeconds, 15, accuracy: 0.0001)
        expectEqual(summary.completedSessions, 1)
    }

    @Test func testCrossMidnightAndTimeZoneChangePreserveHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let midnightStart = ISO8601DateFormatter().date(from: "2026-10-21T15:59:30Z")!
        var data = AppData()
        data.settings.focusMinutes = 1
        var engine = TimerEngine(data: data)
        engine.start(at: midnightStart)
        _ = engine.advance(seconds: 60, endingAt: midnightStart.addingTimeInterval(60),
                           app: appA, recordingEnabled: true, calendar: calendar)
        expectEqual(engine.data.intervals.count, 2)
        expectEqual(engine.data.intervals[0].seconds, 30, accuracy: 0.0001)
        expectEqual(engine.data.intervals[1].seconds, 30, accuracy: 0.0001)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = DailySummary.build(day: "2026-10-21", from: engine.data, calendar: calendar)
        let today = DailySummary.build(day: "2026-10-22", from: engine.data, calendar: calendar)
        expectEqual(yesterday.completedSessions, 0)
        expectEqual(today.completedSessions, 1)
        expectEqual(yesterday.focusSeconds + today.focusSeconds, 60, accuracy: 0.0001)
        expectEqual(engine.data.usage.map(\.localDay), ["2026-10-21", "2026-10-22"])
    }

    @Test func testCalendarBoundaryHandlesTwentyThreeHourDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = ISO8601DateFormatter().date(from: "2026-03-08T04:30:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-03-09T04:30:00Z")!
        let parts = LocalTime.split(start: start, end: end, effectiveSeconds: 86400, calendar: calendar)
        expectEqual(parts.map(\.day), ["2026-03-07", "2026-03-08", "2026-03-09"])
        expectEqual(parts[1].seconds, 23 * 3600, accuracy: 0.0001)
        expectEqual(parts.reduce(0) { $0 + $1.seconds }, 86400, accuracy: 0.0001)
    }

    @Test func testSettingsDoNotResetRunningPhaseAndRecoveryDoesNotCountOfflineTime() {
        var engine = TimerEngine(data: AppData())
        engine.start(at: start)
        _ = engine.advance(seconds: 20, endingAt: start.addingTimeInterval(20), app: appA, recordingEnabled: true)
        var data = engine.data
        data.settings.focusMinutes = 50
        engine.replaceData(data)
        expectEqual(engine.data.timer.targetSeconds, 1500)
        engine.recoverAfterLaunch()
        expectEqual(engine.data.timer.phase, .paused)
        _ = engine.advance(seconds: 3600, endingAt: start.addingTimeInterval(3620), app: appA, recordingEnabled: true)
        expectEqual(engine.data.timer.remainingSeconds, 1480)
        engine.endEarly(at: start.addingTimeInterval(3620))
        engine.start(at: start.addingTimeInterval(3620))
        expectEqual(engine.data.timer.targetSeconds, 3000)
    }

    @Test func testSkippingPendingLongBreakResetsSetWithoutAutoStarting() {
        var data = AppData()
        data.timer.phase = .completed
        data.timer.nextStage = .longBreak
        data.timer.completedInSet = 4
        var engine = TimerEngine(data: data)
        engine.skipBreak(at: start)
        expectEqual(engine.data.timer.phase, .idle)
        expectEqual(engine.data.timer.stage, .focus)
        expectEqual(engine.data.timer.completedInSet, 0)
    }

    @Test func testRepositoryRoundTripAndCorruptionDoesNotOverwriteOriginal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = LocalRepository(fileURL: dir.appendingPathComponent("data.json"))
        var data = AppData()
        data.todos = [TodoItem(text: "今天", localDay: "2026-10-21"), TodoItem(text: "昨天", localDay: "2026-10-20")]
        var note = StickyNote()
        note.text = "中文便签\n第二行"
        note.isOpen = false
        data.notes = [note]
        try repository.save(data)
        let loaded = try repository.load()
        expectEqual(loaded.notes[0].text, note.text)
        expectFalse(loaded.notes[0].isOpen)
        expectEqual(DailySummary.build(day: "2026-10-21", from: loaded).todos.count, 1)
        let broken = Data("broken data".utf8)
        try broken.write(to: repository.fileURL)
        expectThrows(try repository.load())
        expectEqual(try Data(contentsOf: repository.fileURL), broken)
    }

    @Test func testClamshellExternalWorkPolicy() {
        expectFalse(DevicePolicy.shouldPauseForLid(closed: false, externalDisplayActive: false, allowExternalWork: true))
        expectFalse(DevicePolicy.shouldPauseForLid(closed: true, externalDisplayActive: true, allowExternalWork: true))
        expectTrue(DevicePolicy.shouldPauseForLid(closed: true, externalDisplayActive: false, allowExternalWork: true))
        expectTrue(DevicePolicy.shouldPauseForLid(closed: true, externalDisplayActive: true, allowExternalWork: false))
    }

    @Test func testNewSettingsDefaultDoesNotBreakOlderData() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"focusMinutes\":40}".utf8))
        expectEqual(settings.focusMinutes, 40)
        expectTrue(settings.allowClamshellWithExternalDisplay)
        expectFalse(settings.showDockIcon)
        expectEqual(settings.timerHotkey.letter, "P")
    }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs == rhs, sourceLocation: sourceLocation)
}

private func expectEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(lhs - rhs) <= accuracy, sourceLocation: sourceLocation)
}

private func expectTrue(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(condition, sourceLocation: sourceLocation)
}

private func expectFalse(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!condition, sourceLocation: sourceLocation)
}

private func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        _ = try expression()
        Issue.record("Expected an error", sourceLocation: sourceLocation)
    } catch {}
}
