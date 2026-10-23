import Foundation
import Testing
import TomatoCore
import TomatoSystem
@testable import TomatoNotes

private final class RecordingProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct ActivityLifecycleTests {
    private func mockClient(_ provider: AIProviderConfig) -> AIReviewClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        return AIReviewClient(provider: provider, session: URLSession(configuration: configuration))
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let bytes: Data
        if let data = request.httpBody { bytes = data }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            bytes = data
        } else { bytes = Data() }
        return try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private static func response(_ value: [String: Any]) throws -> (Int, Data) {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        return (200, try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": text]]]]))
    }

    @MainActor private func activeState(at root: URL) throws -> (AppState, UUID, UUID) {
        var fixture = AppData()
        fixture.settings.activityRecording.enabled = true
        fixture.settings.activityRecording.chromeEnabled = false
        fixture.settings.notificationsEnabled = false
        let note = StickyNote()
        fixture.notes = [note]
        var engine = TimerEngine(data: fixture)
        let now = Date()
        engine.start(at: now.addingTimeInterval(-120))
        _ = engine.advance(seconds: 120, endingAt: now, app: nil, recordingEnabled: false)
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        try repository.save(engine.data)
        let state = AppState(repository: repository, aiClientFactory: mockClient, keyReader: { _ in "fake-isolated-key" })
        state.deviceLocked = false
        state.startOrPause()
        return (state, try #require(state.timer.sessionID), note.id)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("后台记录流程没有在预期时间内完成")
    }

    private func waitForRequest(_ stream: AsyncStream<Void>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in stream { return } }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw NSError(domain: "ActivityLifecycleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "预期的 AI 请求未发出"])
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    @Test @MainActor func recordsAnOptedInNoteWithoutReadingHistoricalText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var fixture = AppData()
        fixture.settings.activityRecording.enabled = true
        fixture.settings.activityRecording.chromeEnabled = false
        var note = StickyNote()
        note.text = "旧便签，不属于本轮"
        fixture.notes = [note]
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        try repository.save(fixture)
        let state = AppState(repository: repository, keyReader: { _ in nil })
        state.deviceLocked = false
        state.startOrPause()
        state.updateNoteText(note.id, text: note.text + "\n本轮整理函数依赖")
        #expect(state.data.focusActivities.count == 1)
        #expect(state.data.focusActivities[0].detail == "本轮整理函数依赖")
        #expect(state.data.workRecords[0].automaticRecordingUsed == true)
        state.startOrPause()
        state.updateNoteText(note.id, text: "暂停期间的文字")
        #expect(state.data.focusActivities.count == 1)
        #expect(!state.data.focusActivities[0].detail!.contains("暂停"))
    }

    @Test @MainActor func zeroGoalSessionIdentifiesThenSummarizesAndPersistsWithoutConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        RecordingProtocol.handler = { request in
            let messages = try #require(try Self.body(request)["messages"] as? [[String: Any]])
            if let input = messages[1]["content"] as? String {
                let facts = try #require(try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
                let materials = try #require(facts["本轮已观察到的材料"] as? [[String: Any]])
                return try Self.response(["title": "软考 · 函数依赖", "confidence": 0.94,
                    "evidenceIDs": materials.map { $0["id"] as! String }, "matchingTopicID": NSNull()])
            }
            return try Self.response(["activities": ["在便签中整理了函数依赖的笔记"], "outcomes": [], "nextSteps": [], "uncertainties": []])
        }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "整理函数依赖与第三范式")
        state.tick()
        try await waitUntil { state.workRecord(for: .session(sessionID))?.activityTopic != nil }
        #expect(state.data.sessions[0].goal == nil)
        #expect(SessionProgress.build(sessionID: sessionID, from: state.data)?.title == "软考 · 函数依赖")
        #expect(!state.settings.review.autoSummarizeSessions)
        state.endEarlyOrSkip()
        state.tick()
        try await waitUntil { state.workRecord(for: .session(sessionID))?.summary != nil }
        let reopened = try state.repository.load()
        let record = try #require(ReviewContextBuilder.record(for: .session(sessionID), in: reopened))
        #expect(record.summary?.content.activities == ["在便签中整理了函数依赖的笔记"])
        #expect(record.summary?.content.outcomes.isEmpty == true)
        #expect(reopened.focusActivities.count == 1)
        #expect(record.autoReviewAttemptedAt != nil)
        #expect(record.summary?.contextDigest == ReviewContextBuilder.build(for: .session(sessionID), from: reopened).digest)
    }

    @Test @MainActor func failedAILeavesFactsAndDoesNotLoopOnTheSameMaterials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        RecordingProtocol.handler = { _ in (429, Data("not persisted".utf8)) }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "函数依赖笔记")
        state.tick()
        try await waitUntil { state.activityErrors[sessionID] != nil }
        for _ in 0..<10 { state.tick() }
        #expect(state.workRecord(for: .session(sessionID))?.topicAttemptCount == 1)
        state.endEarlyOrSkip()
        state.tick()
        try await waitUntil { state.reviewErrors[WorkScope.session(sessionID).key] != nil }
        for _ in 0..<10 { state.tick() }
        let reopened = try state.repository.load()
        #expect(reopened.focusActivities.count == 1)
        #expect(reopened.workRecords[0].summary == nil)
        #expect(reopened.workRecords[0].autoReviewAttemptedAt != nil)
        #expect(reopened.sessions[0].endedAt != nil)
        #expect(!state.reviewErrors[WorkScope.session(sessionID).key]!.contains("not persisted"))
    }

    @Test @MainActor func deletionSuppressesTheSameSourceAndClearsDerivedResults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "这一轮的笔记")
        let activity = try #require(state.data.focusActivities.first)
        state.renameActivitySession(sessionID, title: "用户自己的归类")
        state.removeFocusActivity(activity.id)
        state.updateNoteText(noteID, text: "这一轮的笔记继续补充")
        #expect(state.data.focusActivities.isEmpty)
        #expect(state.workRecord(for: .session(sessionID))?.titleOverride == "用户自己的归类")
        let reopened = try state.repository.load()
        #expect(reopened.focusActivities.isEmpty)
        #expect(reopened.workRecords[0].excludedActivityKeys?.contains(activity.sourceKey) == true)
    }

    @Test @MainActor func uncertainAILeavesTheTitleUndetermined() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        RecordingProtocol.handler = { _ in try Self.response(["title": "", "confidence": 0.2, "evidenceIDs": [], "matchingTopicID": NSNull()]) }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "零散内容")
        state.tick()
        try await waitUntil { !state.identifyingActivity }
        #expect(state.workRecord(for: .session(sessionID))?.activityTopic == nil)
        #expect(state.data.focusActivities.count == 1)
    }

    @Test @MainActor func aLateThemeCannotOverwriteAUserCorrection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (stream, signal) = AsyncStream<Void>.makeStream()
        RecordingProtocol.handler = { request in
            let messages = try #require(try Self.body(request)["messages"] as? [[String: Any]])
            let text = try #require(messages[1]["content"] as? String)
            let facts = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let materials = try #require(facts["本轮已观察到的材料"] as? [[String: Any]])
            signal.yield()
            Thread.sleep(forTimeInterval: 0.1)
            return try Self.response(["title": "AI 稍后返回的主题", "confidence": 0.9,
                "evidenceIDs": materials.map { $0["id"] as! String }, "matchingTopicID": NSNull()])
        }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "本轮函数依赖笔记")
        state.tick()
        try await waitForRequest(stream)
        state.renameActivitySession(sessionID, title: "我的软考复习")
        try await Task.sleep(for: .milliseconds(200))
        let record = state.workRecord(for: .session(sessionID))
        #expect(record?.titleOverride == "我的软考复习")
        #expect(record?.activityTopic?.title == "我的软考复习")
        #expect(!state.identifyingActivity)
    }

    @Test @MainActor func deletingEvidenceWhileASummaryIsInFlightCannotReintroduceIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (stream, signal) = AsyncStream<Void>.makeStream()
        RecordingProtocol.handler = { request in
            let messages = try #require(try Self.body(request)["messages"] as? [[String: Any]])
            if messages[1]["content"] is String {
                return try Self.response(["title": "", "confidence": 0.2, "evidenceIDs": [], "matchingTopicID": NSNull()])
            }
            signal.yield()
            Thread.sleep(forTimeInterval: 0.1)
            return try Self.response(["activities": ["不应重新出现的已删除材料"], "outcomes": [], "nextSteps": [], "uncertainties": []])
        }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "本轮函数依赖笔记")
        state.endEarlyOrSkip()
        state.tick()
        try await waitForRequest(stream)
        state.removeFocusActivity(try #require(state.data.focusActivities.first).id)
        try await waitUntil { state.generatingScopes.isEmpty }
        #expect(state.workRecord(for: .session(sessionID))?.summary == nil)
        #expect(state.data.focusActivities.isEmpty)
        #expect(try state.repository.load().focusActivities.isEmpty)
    }

    @Test @MainActor func lockingDuringFinalIdentificationDefersTheSummaryUntilUnlock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (stream, signal) = AsyncStream<Void>.makeStream()
        RecordingProtocol.handler = { request in
            let messages = try #require(try Self.body(request)["messages"] as? [[String: Any]])
            if messages[1]["content"] is String {
                signal.yield()
                Thread.sleep(forTimeInterval: 0.1)
                return try Self.response(["title": "", "confidence": 0.2, "evidenceIDs": [], "matchingTopicID": NSNull()])
            }
            return try Self.response(["activities": ["解锁后整理便签变更"], "outcomes": [], "nextSteps": [], "uncertainties": []])
        }
        let (state, sessionID, noteID) = try activeState(at: root)
        state.updateNoteText(noteID, text: "本轮函数依赖笔记")
        state.endEarlyOrSkip()
        state.tick()
        try await waitForRequest(stream)
        state.deviceLocked = true
        try await waitUntil { state.generatingScopes.isEmpty }
        #expect(state.workRecord(for: .session(sessionID))?.autoReviewAttemptedAt == nil)
        #expect(state.workRecord(for: .session(sessionID))?.summary == nil)
        state.deviceLocked = false
        state.tick()
        try await waitUntil { state.workRecord(for: .session(sessionID))?.summary != nil }
        #expect(state.workRecord(for: .session(sessionID))?.autoReviewAttemptedAt != nil)
    }
}
