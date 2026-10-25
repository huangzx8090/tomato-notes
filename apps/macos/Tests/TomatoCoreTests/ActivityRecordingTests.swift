import Foundation
import Testing
@testable import TomatoCore

struct ActivityRecordingTests {
    private let start = Date(timeIntervalSince1970: 1_792_580_400)

    private func fixture(seconds: Double = 120) -> AppData {
        var value = AppData()
        value.settings.activityRecording.enabled = true
        var engine = TimerEngine(data: value)
        engine.start(at: start)
        _ = engine.advance(seconds: seconds, endingAt: start.addingTimeInterval(seconds), app: nil, recordingEnabled: false)
        return engine.data
    }

    private func addPage(to data: inout AppData, title: String = "第三范式课程", seconds: Int = 60) throws {
        let page = try #require(ActivityPage(title: title, url: "https://course.example/lesson?token=secret", isPrivate: false))
        let id = try #require(data.timer.sessionID)
        for second in stride(from: 0, to: seconds, by: 5) {
            ActivityRecorder.appendPage(page, sessionID: id, start: start.addingTimeInterval(Double(second)),
                end: start.addingTimeInterval(Double(second + 5)), to: &data)
        }
    }

    @Test func oldSettingsAndRecordsNeverOptInAndSchemaThreeIsBackedUp() throws {
        let oldSettings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!oldSettings.activityRecording.enabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        var old = AppData()
        old.schemaVersion = 3
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "focusActivities")
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bytes.write(to: repository.fileURL)
        let loaded = try repository.load()
        #expect(loaded.schemaVersion == 4 && loaded.focusActivities.isEmpty)
        let backup = try #require(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups/schema-v3"), includingPropertiesForKeys: nil).first)
        #expect(try Data(contentsOf: backup) == bytes)
        #expect(try Data(contentsOf: repository.fileURL) == bytes)
    }

    @Test func pageMetadataDropsPathsQueriesAndRejectsPrivateOrInternalPages() throws {
        let page = try #require(ActivityPage(title: "课程 https://course.example/private/path?token=secret", url: "https://course.example/private/path?token=secret#fragment", isPrivate: false))
        #expect(page.site == "course.example")
        #expect(page.title == "课程 course.example")
        #expect(ActivityPage(title: "无痕", url: "https://course.example", isPrivate: true) == nil)
        #expect(ActivityPage(title: "设置", url: "chrome://settings", isPrivate: false) == nil)
        #expect(ActivityPage(title: "文件", url: "file:///private/course.pdf", isPrivate: false) == nil)
        #expect(ActivityPage(title: "空地址", url: "invalid", isPrivate: false) == nil)
    }

    @Test func contiguousPageSamplesMergeAndNeverExtendOutsideConfirmedFocus() throws {
        var data = fixture()
        try addPage(to: &data)
        #expect(data.focusActivities.count == 1)
        #expect(data.focusActivities[0].seconds == 60)
        let page = try #require(ActivityPage(title: "新资料", url: "https://course.example", isPrivate: false))
        let id = try #require(data.timer.sessionID)
        ActivityRecorder.appendPage(page, sessionID: id, start: start.addingTimeInterval(115), end: start.addingTimeInterval(125), to: &data)
        #expect(data.focusActivities.last?.seconds == 5)
        let raw = String(decoding: try JSONEncoder().encode(data.focusActivities), as: UTF8.self)
        #expect(!raw.contains("secret") && !raw.contains("token") && !raw.contains("lesson"))
        data.timer.phase = .paused
        let count = data.focusActivities.count
        ActivityRecorder.appendPage(page, sessionID: id, start: start, end: start.addingTimeInterval(5), to: &data)
        #expect(data.focusActivities.count == count)
        data.timer.phase = .running
        data.settings.activityRecording.chromeEnabled = false
        ActivityRecorder.appendPage(page, sessionID: id, start: start, end: start.addingTimeInterval(5), to: &data)
        #expect(data.focusActivities.count == count)
    }

    @Test func samplesAcrossPausesAndMidnightKeepTheirOwnDays() throws {
        var data = fixture()
        let id = try #require(data.timer.sessionID)
        data.intervals[0].endedAt = start.addingTimeInterval(20)
        data.intervals[0].seconds = 20
        data.intervals[0].localDay = "2026-10-22"
        data.intervals.append(.init(sessionID: id, startedAt: start.addingTimeInterval(25), endedAt: start.addingTimeInterval(40), localDay: "2026-10-23", timeZoneID: "Asia/Shanghai", seconds: 15))
        let page = try #require(ActivityPage(title: "跨日课程", url: "https://course.example", isPrivate: false))
        ActivityRecorder.appendPage(page, sessionID: id, start: start.addingTimeInterval(15), end: start.addingTimeInterval(30), to: &data)
        #expect(data.focusActivities.map(\.seconds) == [5, 5])
        #expect(data.focusActivities.map(\.localDay) == ["2026-10-22", "2026-10-23"])
        ActivityRecorder.appendPage(page, sessionID: id, start: start, end: start.addingTimeInterval(60), to: &data)
        #expect(data.focusActivities.count == 2)
    }

    @Test func notesCaptureOnlyChangedLinesAndCoalesceTypingWithoutReadingOldText() throws {
        var data = fixture()
        var note = StickyNote(at: start)
        note.text = "历史个人文字\n本轮新增一句"
        ActivityRecorder.recordNote(note, previousText: "历史个人文字", at: start.addingTimeInterval(10), in: &data)
        #expect(data.focusActivities[0].detail == "本轮新增一句")
        #expect(!String(decoding: try JSONEncoder().encode(data.focusActivities), as: UTF8.self).contains("历史个人文字"))
        note.text += "并改好了"
        ActivityRecorder.recordNote(note, previousText: "历史个人文字", at: start.addingTimeInterval(11), in: &data)
        #expect(data.focusActivities.count == 1)
        #expect(data.focusActivities[0].detail == "本轮新增一句并改好了")
        data.timer.phase = .paused
        note.text = "暂停新增文字"
        ActivityRecorder.recordNote(note, previousText: "", at: start.addingTimeInterval(12), in: &data)
        #expect(data.focusActivities[0].detail == "本轮新增一句并改好了")
    }

    @Test func shortVisitsCannotTriggerAThemeAndFailedInputsAreNotRepeated() throws {
        var data = fixture()
        let id = try #require(data.timer.sessionID)
        try addPage(to: &data, seconds: 20)
        #expect(!ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data))
        ActivityRecorder.appendPage(try #require(ActivityPage(title: "第三范式课程", url: "https://course.example", isPrivate: false)),
            sessionID: id, start: start.addingTimeInterval(20), end: start.addingTimeInterval(30), to: &data)
        try addPage(to: &data, title: "函数依赖", seconds: 30)
        #expect(ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data))
        var record = WorkRecord(localDay: "2026-10-23", sessionID: id)
        record.topicAttemptCount = 1
        record.topicAttemptDigest = ActivityTopicContext.build(sessionID: id, from: data).digest
        record.topicAttemptFocusSeconds = 120
        data.workRecords = [record]
        let reopened = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        #expect(!ActivityTopicPolicy.shouldIdentify(sessionID: id, in: reopened))
        try addPage(to: &data, title: "新材料", seconds: 50)
        #expect(!ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data))
        data.intervals[0].seconds = 420
        #expect(ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data))
        data.workRecords[0].topicAttemptCount = 4
        #expect(!ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data))
        data.sessions[0].endedAt = start.addingTimeInterval(420)
        #expect(ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data, final: true))
        data.workRecords[0].finalTopicAttempted = true
        #expect(!ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data, final: true))
    }

    @Test func topicInputsRespectSourceChoicesAndEvidenceDoesNotIncludeOtherSessions() throws {
        var data = fixture()
        let id = try #require(data.timer.sessionID)
        try addPage(to: &data)
        var note = StickyNote(at: start)
        note.text = "这一轮的笔记"
        ActivityRecorder.recordNote(note, previousText: "", at: start, in: &data)
        data.focusActivities.append(.init(sessionID: UUID(), kind: .noteEdited, title: "别的轮次隐私", startedAt: start, endedAt: start, localDay: "2026-10-23"))
        var context = ActivityTopicContext.build(sessionID: id, from: data)
        #expect(!context.text.contains("别的轮次隐私"))
        #expect(context.evidenceIDs.count == 2)
        data.settings.activityRecording.notesEnabled = false
        context = ActivityTopicContext.build(sessionID: id, from: data)
        #expect(!context.text.contains("这一轮的笔记"))
        #expect(context.evidenceIDs.count == 1)
        let summary = ReviewContextBuilder.build(for: .session(id), from: data)
        #expect(!summary.text.contains("这一轮的笔记"))
        #expect(summary.text.contains("第三范式课程"))
        data.settings.activityRecording.chromeEnabled = false
        #expect(ActivityTopicContext.build(sessionID: id, from: data).evidenceIDs.isEmpty)
    }

    @Test func userTitlesWinAndConsecutiveSessionsGroupOnlyWithAnExplicitTopicMatch() throws {
        var data = fixture()
        let first = data.sessions[0]
        var second = FocusSession(startedAt: start.addingTimeInterval(400))
        second.endedAt = start.addingTimeInterval(500)
        data.sessions.append(second)
        data.intervals[0].localDay = "2026-10-23"
        data.intervals.append(.init(sessionID: second.id, startedAt: second.startedAt, endedAt: second.endedAt!, localDay: "2026-10-23", timeZoneID: "Asia/Shanghai", seconds: 100))
        let group = UUID()
        var record = WorkRecord(localDay: "2026-10-23", sessionID: first.id)
        record.activityTopic = .init(groupID: group, title: "数据库", confidence: 0.9, evidenceIDs: [], model: "test")
        data.workRecords = [record]
        var next = WorkRecord(localDay: "2026-10-23", sessionID: second.id)
        next.activityTopic = .init(groupID: group, title: "数据库", confidence: 0.9, evidenceIDs: [], model: "test")
        data.workRecords.append(next)
        let groups = ActivityTopicGroup.build(day: "2026-10-23", sessions: data.sessions, from: data)
        #expect(groups.count == 1 && groups[0].seconds == 220)
        data.workRecords[0].titleOverride = "软考复习"
        #expect(SessionProgress.build(sessionID: first.id, from: data)?.title == "软考复习")
        #expect(ActivityTopicGroup.build(day: "2026-10-23", sessions: data.sessions, from: data).count == 2)
        #expect(!ActivityTopicPolicy.shouldIdentify(sessionID: first.id, in: data))
        #expect(ActivityTopicContext.build(sessionID: second.id, from: data).text.contains("软考复习"))
    }

    @Test func automaticRecordingEnablesFinalReviewWithoutChangingTheLegacySwitch() throws {
        var data = fixture()
        let id = try #require(data.timer.sessionID)
        var engine = TimerEngine(data: data)
        engine.endEarly(at: start.addingTimeInterval(120))
        data = engine.data
        var record = WorkRecord(localDay: "2026-10-23", sessionID: id)
        record.automaticRecordingUsed = true
        data.workRecords = [record]
        #expect(!data.settings.review.autoSummarizeSessions)
        #expect(AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
        data.settings.activityRecording.enabled = false
        #expect(!AutomaticSessionReview.shouldGenerate(sessionID: id, from: data))
    }

    @Test func activityRecordsSurviveMergeAndBackupRoundTrip() throws {
        var data = fixture()
        try addPage(to: &data)
        let merged = try DataMerger.merge(primary: data, importing: [data])
        #expect(merged.focusActivities == data.focusActivities)
        let roundTrip = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(merged))
        #expect(roundTrip.focusActivities == merged.focusActivities)
        var broken = data
        broken.focusActivities[0].sessionID = UUID()
        #expect(throws: DataMergeError.self) { try DataMerger.merge(primary: broken, importing: []) }
    }

    @Test func resumedNotesKeepEarlierEditsAndClearingTextRemovesTheOldExcerpt() throws {
        var data = fixture()
        var note = StickyNote(at: start)
        note.text = "第一段新增"
        let firstBlock = UUID()
        ActivityRecorder.recordNote(note, previousText: "", at: start, blockID: firstBlock, in: &data)
        note.text += "\n恢复后新增"
        ActivityRecorder.recordNote(note, previousText: "第一段新增", at: start.addingTimeInterval(30), blockID: UUID(), in: &data)
        #expect(data.focusActivities.map(\.detail) == ["第一段新增", "恢复后新增"])
        note.text = ""
        ActivityRecorder.recordNote(note, previousText: "", at: start.addingTimeInterval(31), blockID: firstBlock, in: &data)
        #expect(data.focusActivities[0].detail?.contains("第一段新增") == false)
        #expect(data.focusActivities[0].title == "便签文字调整")
    }

    @Test func daySummariesDoNotReuseAnEntireCrossMidnightRound() throws {
        var data = fixture()
        let id = try #require(data.timer.sessionID)
        data.intervals[0].localDay = "2026-10-22"
        data.intervals.append(.init(sessionID: id, startedAt: start.addingTimeInterval(120), endedAt: start.addingTimeInterval(150), localDay: "2026-10-23", timeZoneID: "Asia/Shanghai", seconds: 30))
        var record = WorkRecord(localDay: "2026-10-23", sessionID: id)
        data.workRecords = [record]
        record.summary = .init(content: .init(activities: ["跨日整轮的内容不能全部算到一天"], outcomes: [], nextSteps: [], uncertainties: []),
            model: "test", contextDigest: ReviewContextBuilder.build(for: .session(id), from: data).digest, imageIDs: [])
        data.workRecords = [record]
        #expect(!ReviewContextBuilder.build(for: .day("2026-10-23"), from: data).text.contains("跨日整轮的内容不能全部算到一天"))
    }
}
