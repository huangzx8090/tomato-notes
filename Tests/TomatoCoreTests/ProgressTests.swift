import Foundation
import Testing
@testable import TomatoCore

struct ProgressTests {
    private let start = Date(timeIntervalSince1970: 1_792_580_400)

    private func fixture(seconds: Double = 120) -> AppData {
        var data = AppData()
        var session = FocusSession(startedAt: start, goal: "学习二叉树")
        session.endedAt = start.addingTimeInterval(seconds)
        session.endedLocalDay = "2026-10-22"
        session.completed = true
        data.sessions = [session]
        data.intervals = [.init(sessionID: session.id, startedAt: start, endedAt: start.addingTimeInterval(seconds),
                                localDay: "2026-10-22", timeZoneID: "Asia/Shanghai", seconds: seconds)]
        return data
    }

    @Test func progressNeedsNoManualRecordAndDoesNotInventOutcomes() throws {
        let data = fixture()
        let progress = try #require(SessionProgress.build(sessionID: data.sessions[0].id, from: data))
        #expect(progress.title == "学习二叉树")
        #expect(progress.focusSeconds == 120)
        #expect(progress.completedTodos.isEmpty)
        #expect(data.workRecords.isEmpty)
        let facts = try #require(try JSONSerialization.jsonObject(with: Data(ReviewContextBuilder.build(for: .session(progress.session.id), from: data).text.utf8)) as? [String: Any])
        #expect(facts["用户设定的本轮目标（不代表完成）"] as? String == "学习二叉树")
        #expect(facts["此时间段勾选完成的待办"] as? [String] == [])
    }

    @Test func pausedAndOtherRoundTasksAreExcludedFromProgress() throws {
        var data = fixture()
        let id = data.sessions[0].id
        data.intervals[0].endedAt = start.addingTimeInterval(30)
        data.intervals[0].seconds = 30
        data.intervals.append(.init(sessionID: id, startedAt: start.addingTimeInterval(90), endedAt: start.addingTimeInterval(120),
                                    localDay: "2026-10-22", timeZoneID: "Asia/Shanghai", seconds: 30))
        for (text, second) in [("本轮完成", 20.0), ("暂停时做完", 60.0), ("休息时做完", 140.0)] {
            var todo = TodoItem(text: text, localDay: "2026-10-22")
            todo.completedAt = start.addingTimeInterval(second)
            data.todos.append(todo)
        }
        let progress = try #require(SessionProgress.build(sessionID: id, from: data))
        #expect(progress.focusSeconds == 60)
        #expect(progress.completedTodos.map(\.text) == ["本轮完成"])
        let context = ReviewContextBuilder.build(for: .session(id), from: data)
        #expect(!context.text.contains("暂停时做完") && !context.text.contains("休息时做完"))
    }

    @Test func goalsBelongToOneSessionAndSurvivePause() throws {
        var engine = TimerEngine(data: AppData())
        engine.start(at: start, goal: "  复习图论  ")
        let firstID = engine.data.timer.sessionID
        engine.pause(reason: "暂停", at: start.addingTimeInterval(1))
        engine.start(at: start.addingTimeInterval(2), goal: "不能覆盖进行中的目标")
        #expect(engine.data.timer.sessionID == firstID)
        #expect(engine.data.sessions[0].goal == "复习图论")
        engine.endEarly(at: start.addingTimeInterval(3))
        engine.start(at: start.addingTimeInterval(4))
        #expect(engine.data.sessions[1].goal == nil)
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(engine.data))
        #expect(restored.sessions[0].goal == "复习图论" && restored.sessions[1].goal == nil)
    }

    @Test func legacyRecordsDoNotOptIntoAutomaticAI() throws {
        let settings = try JSONDecoder().decode(ReviewSettings.self, from: Data(#"{"scheduleEnabled":true,"hour":20,"minute":10}"#.utf8))
        #expect(settings.scheduleEnabled && !settings.autoSummarizeSessions)
        #expect(settings.hour == 20 && settings.minute == 10)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture().sessions[0])) as? [String: Any])
        json.removeValue(forKey: "goal")
        let session = try JSONDecoder().decode(FocusSession.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(session.goal == nil)
        let record = WorkRecord(localDay: "2026-10-22", sessionID: session.id)
        let restored = try JSONDecoder().decode(WorkRecord.self, from: JSONEncoder().encode(record))
        #expect(restored.autoReviewAttemptedAt == nil)
    }

    @Test func automaticReviewRequiresOptInAndAtLeastAMinuteOfFinishedFocus() {
        var data = fixture(seconds: 59)
        let id = data.sessions[0].id
        #expect(!AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
        data.settings.review.autoSummarizeSessions = true
        #expect(!AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
        data.intervals[0].seconds = 60
        #expect(AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
        data.sessions[0].endedAt = nil
        #expect(!AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
    }

    @Test func automaticAttemptPersistsAndCurrentManualSummaryIsNotRegenerated() throws {
        var data = fixture()
        data.settings.review.autoSummarizeSessions = true
        let id = data.sessions[0].id
        let scope = WorkScope.session(id)
        var record = WorkRecord(localDay: "2026-10-22", sessionID: id)
        record.summary = AISummary(content: .init(activities: [], outcomes: [], nextSteps: [], uncertainties: []),
                                   model: "test", contextDigest: ReviewContextBuilder.build(for: scope, from: data).digest, imageIDs: [])
        data.workRecords = [record]
        #expect(!AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
        data.workRecords[0].userText = "新增依据"
        #expect(AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
        data.workRecords[0].autoReviewAttemptedAt = start
        let reopened = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        #expect(!AutomaticSessionReview.shouldGenerate(sessionID: id, from: reopened))
    }

    @Test func dayContextIncludesGoalsWithoutManualWorkAndHonorsMidnight() throws {
        var data = fixture()
        let id = data.sessions[0].id
        data.intervals.append(.init(sessionID: id, startedAt: start.addingTimeInterval(120), endedAt: start.addingTimeInterval(180),
                                    localDay: "2026-10-23", timeZoneID: "Asia/Shanghai", seconds: 60))
        let nextDay = try #require(SessionProgress.build(sessionID: id, from: data, day: "2026-10-23"))
        #expect(nextDay.focusSeconds == 60)
        let context = ReviewContextBuilder.build(for: .day("2026-10-23"), from: data)
        let facts = try #require(try JSONSerialization.jsonObject(with: Data(context.text.utf8)) as? [String: Any])
        let rounds = try #require(facts["各轮投入与目标"] as? [[String: Any]])
        #expect(rounds.count == 1 && rounds[0]["目标（不代表完成）"] as? String == "学习二叉树")
        #expect(rounds[0]["当日实际专注秒数"] as? Int == 60)
    }

    @Test func dailyContextDoesNotReuseAnOutdatedClaimAfterEvidenceChanges() {
        var data = fixture()
        let id = data.sessions[0].id
        var record = WorkRecord(localDay: "2026-10-22", sessionID: id)
        record.userText = "完成了练习"
        data.workRecords = [record]
        let oldDigest = ReviewContextBuilder.build(for: .session(id), from: data).digest
        data.workRecords[0].summary = AISummary(content: .init(activities: [], outcomes: ["旧总结的错误成果"], nextSteps: [], uncertainties: []),
                                              model: "test", contextDigest: oldDigest, imageIDs: [])
        data.workRecords[0].userText = "更正：只阅读，还未完成练习"
        let context = ReviewContextBuilder.build(for: .day("2026-10-22"), from: data)
        #expect(context.text.contains("只阅读，还未完成练习"))
        #expect(!context.text.contains("旧总结的错误成果"))
    }
}
