import Foundation
import Testing
@testable import TomatoNotes
@testable import TomatoCore

private final class RankingProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct LeaderboardTests {
    private func fixture() -> (AppData, Date) {
        let start = Date(timeIntervalSince1970: 1_793_520_000)
        var data = AppData()
        var session = FocusSession(startedAt: start, goal: "私密目标")
        session.endedAt = start.addingTimeInterval(120)
        session.completed = true
        data.sessions = [session]
        data.intervals = [
            FocusInterval(sessionID: session.id, startedAt: start, endedAt: start.addingTimeInterval(40), localDay: "2026-11-01", timeZoneID: "Asia/Shanghai", seconds: 40),
            FocusInterval(sessionID: session.id, startedAt: start.addingTimeInterval(80), endedAt: start.addingTimeInterval(120), localDay: "2026-11-01", timeZoneID: "Asia/Shanghai", seconds: 40)
        ]
        return (data, start)
    }

    @Test func retainsServerMicrosecondsBeforeRoundingConsentUp() throws {
        let parsed = try #require(RankingSync.parse("2026-11-01T08:00:00.123678+08:00"))
        #expect(abs(parsed.timeIntervalSince1970 - 1_793_491_200.123678) < 0.000001)
        #expect(RankingSync.parse("2026-11-01T00:00:00Z") != nil)
    }

    @Test func clipsConsentAndKeepsPausedIntervalsSeparate() throws {
        let (data, start) = fixture()
        let since = start.addingTimeInterval(20.1234)
        let record = try #require(RankingSync.snapshot(session: data.sessions[0], intervals: data.intervals,
            since: since, now: start.addingTimeInterval(130), remoteID: UUID().uuidString, version: 1))
        #expect(record.intervals.count == 2)
        let parts = record.intervals.sorted { $0.startedAt < $1.startedAt }
        #expect(try #require(RankingSync.parse(parts[0].startedAt)) >= since)
        #expect(abs(parts[0].effectiveSeconds - 19.876) < 0.002)
        #expect(parts[1].effectiveSeconds == 40)
        let body = try RankingSync.uploadBody(version: 4, records: [record])
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["consent_version"] as? Int == 4)
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("私密目标") && !text.contains("local_day") && !text.contains("time_zone"))
        #expect(text.contains("started_at") && text.contains("effective_seconds"))
    }

    @Test func retriesSameSnapshotBeforeSendingNewVersion() throws {
        var (data, start) = fixture()
        data.sessions[0].endedAt = nil
        data.sessions[0].completed = false
        data.intervals.removeLast()
        let key = data.sessions[0].id.uuidString.lowercased()
        let first = RankingSync.makeQueue(data: data, since: start, now: start.addingTimeInterval(130), scope: "test:1", existing: [:])
        let original = try #require(first[key])
        data.intervals[0].endedAt = start.addingTimeInterval(50)
        let retry = RankingSync.makeQueue(data: data, since: start, now: start.addingTimeInterval(130), scope: "test:1", existing: first)
        #expect(retry[key]?.record == original.record)
        var confirmed = retry
        confirmed[key]?.acknowledged = true
        let next = RankingSync.makeQueue(data: data, since: start, now: start.addingTimeInterval(130), scope: "test:1", existing: confirmed)
        #expect(next[key]?.record.version == 2)
        #expect(next[key]?.record.id == original.record.id)
        #expect(next[key]?.record.intervals[0].effectiveSeconds == 50)
    }

    @Test func queueKeepsAccountsSeparateAndDropsOldConsent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try RankingSyncStore(url: directory.appendingPathComponent("queue.json"))
        let (data, start) = fixture()
        let queue = RankingSync.makeQueue(data: data, since: start, now: start.addingTimeInterval(130), scope: "test:1", existing: [:])
        let a1 = RankingSync.scope(userID: "a", consentVersion: 1)
        let a2 = RankingSync.scope(userID: "a", consentVersion: 2)
        let b1 = RankingSync.scope(userID: "b", consentVersion: 1)
        try store.set(queue, scope: a1)
        try store.set(queue, scope: b1)
        try store.set([:], scope: a2)
        let restored = try RankingSyncStore(url: store.url)
        #expect(restored.state.scopes[a1] == nil)
        #expect(restored.state.scopes[b1]?.count == 1)
        #expect(restored.state.scopes[a2]?.isEmpty == true)
        let sessionID = data.sessions[0].id.uuidString.lowercased()
        #expect(RankingSync.remoteID(scope: a1, sessionID: sessionID) == RankingSync.remoteID(scope: a1, sessionID: sessionID))
        #expect(RankingSync.remoteID(scope: a1, sessionID: sessionID) != RankingSync.remoteID(scope: a2, sessionID: sessionID))
    }

    @Test func apiDecodesBackendResponsesAndAuthenticates() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RankingProtocol.self]
        let api = LeaderboardAPI(baseURL: URL(string: "http://127.0.0.1:8080")!, session: URLSession(configuration: configuration))
        RankingProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/auth/login")
            return (200, Data(#"{"code":"OK","message":"成功","data":{"user_id":"user","session_id":"session","access_token":"access","refresh_token":"refresh","expires_in":900,"refresh_expires_at":"2026-12-01T00:00:00Z"}}"#.utf8))
        }
        let login: LeaderboardSession = try await api.request("POST", "/auth/login", body: Data("{}".utf8))
        #expect(login.userID == "user" && login.accessToken == "access")
        #expect(login.accessExpiresAt > Date())
        let restored = try JSONDecoder().decode(LeaderboardSession.self, from: JSONEncoder().encode(login))
        #expect(restored.refreshToken == "refresh")
        RankingProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/leaderboards/daily")
            #expect(request.url?.query?.contains("page=2") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
            return (200, Data(#"{"code":"OK","message":"成功","data":{"date":"2026-11-01","state":"live","total":2,"page":2,"page_size":20,"items":[{"entry_key":"key","rank":1,"nickname":"匿名用户","focus_seconds":12.5,"completed_sessions":1,"is_me":true}]}}"#.utf8))
        }
        let board: DailyBoard = try await api.request("GET", "/leaderboards/daily", token: login.accessToken, query: [.init(name: "page", value: "2")])
        #expect(board.items.first?.entryKey == "key" && board.items.first?.isMe == true)
        #expect(board.items.first?.focusSeconds == 12.5)
        RankingProtocol.handler = { _ in (401, Data(#"{"code":"UNAUTHENTICATED","message":"请重新登录","data":null}"#.utf8)) }
        do { let _: DailyBoard = try await api.request("GET", "/leaderboards/daily"); Issue.record("应拒绝未登录") }
        catch let error as LeaderboardAPIError { #expect(error.code == "UNAUTHENTICATED") }
    }
}

private final class TestCredentials: RankingCredentialStore {
    var bytes: Data?
    func read() throws -> Data? { bytes }
    func save(_ data: Data) throws { bytes = data }
    func remove() throws { bytes = nil }
}

extension LeaderboardTests {
    @Test @MainActor func controllerLoginConsentUploadAndLogout() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RankingProtocol.self]
        let api = LeaderboardAPI(baseURL: URL(string: "http://127.0.0.1:8080")!, session: URLSession(configuration: config))
        let credentials = TestCredentials()
        let controller = LeaderboardController(repository: LocalRepository(fileURL: root.appendingPathComponent("data.json")), api: api, credentials: credentials)
        let start = Date().addingTimeInterval(-100)
        var data = AppData()
        var session = FocusSession(startedAt: start, goal: "仅保存在本机")
        session.endedAt = start.addingTimeInterval(80)
        session.completed = true
        data.sessions = [session]
        data.intervals = [.init(sessionID: session.id, startedAt: start, endedAt: start.addingTimeInterval(80), localDay: "2026-11-01", timeZoneID: "Asia/Shanghai", seconds: 80)]
        controller.tick(data: data)
        let formatter = ISO8601DateFormatter()
        let since = formatter.string(from: start.addingTimeInterval(30))
        let lock = NSLock()
        var participating = false
        var uploads = 0
        RankingProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            let path = request.url!.path
            func reply(_ object: Any) throws -> (Int, Data) {
                (200, try JSONSerialization.data(withJSONObject: ["code": "OK", "message": "成功", "data": object]))
            }
            switch (request.httpMethod!, path) {
            case ("POST", "/api/v1/auth/login"):
                return try reply(["user_id":"user", "session_id":"session", "access_token":"access", "refresh_token":"refresh", "expires_in":900, "refresh_expires_at":"2026-12-01T00:00:00Z"])
            case ("GET", "/api/v1/me"):
                return try reply(["nickname":"番茄"])
            case ("GET", "/api/v1/me/privacy"), ("PATCH", "/api/v1/me/privacy"):
                if request.httpMethod == "PATCH" { participating = true }
                return try reply(["participating":participating, "display_mode":"anonymous", "consent_version":1, "participation_since":since])
            case ("GET", "/api/v1/leaderboards/daily"):
                return try reply(["date":"2026-11-01", "state":"live", "total":0, "page":1, "page_size":20, "items":[]])
            case ("GET", "/api/v1/leaderboards/daily/me"):
                return try reply(["status":"no_score", "entry":NSNull()])
            case ("POST", "/api/v1/focus/records/batch"):
                uploads += 1
                var bytes = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        bytes.append(contentsOf: buffer.prefix(count))
                    }
                }
                let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let records = try #require(object["records"] as? [[String: Any]])
                let intervals = try #require(records.first?["intervals"] as? [[String: Any]])
                #expect(intervals.count == 1)
                #expect((intervals[0]["effective_seconds"] as? Double ?? 0) < 51)
                #expect(!String(decoding: bytes, as: UTF8.self).contains("仅保存在本机"))
                return try reply(["results":[["id":records[0]["id"]!, "status":"accepted"]], "frozen_days":[]])
            case ("POST", "/api/v1/auth/logout"):
                return try reply(["logged_out":true])
            default:
                Issue.record("意外请求 \(path)")
                return try reply([:])
            }
        }
        func waitUntilIdle() async throws {
            for _ in 0..<200 {
                if !controller.busy { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            Issue.record("请求未结束")
        }
        controller.login(username: "example", password: "example-password")
        try await waitUntilIdle()
        #expect(controller.loggedIn && controller.nickname == "番茄")
        #expect(controller.privacy?.participating == false)
        #expect(uploads == 0)
        controller.setParticipation(true, mode: "anonymous")
        try await waitUntilIdle()
        #expect(controller.privacy?.participating == true)
        #expect(uploads == 1)
        #expect(credentials.bytes != nil)
        #expect(controller.message == nil)
        controller.logout()
        try await waitUntilIdle()
        #expect(!controller.loggedIn && credentials.bytes == nil)
    }
}

extension LeaderboardTests {
    @Test @MainActor func uncertainRefreshClearsCredentialsInsteadOfReplaying() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RankingProtocol.self]
        let api = LeaderboardAPI(baseURL: URL(string: "http://127.0.0.1:8080")!, session: URLSession(configuration: config))
        let credentials = TestCredentials()
        let controller = LeaderboardController(repository: LocalRepository(fileURL: root.appendingPathComponent("data.json")), api: api, credentials: credentials)
        var refreshCalls = 0
        RankingProtocol.handler = { request in
            if request.url?.path == "/api/v1/auth/login" {
                return (200, Data(#"{"code":"OK","message":"成功","data":{"user_id":"u","session_id":"s","access_token":"a","refresh_token":"r","expires_in":0,"refresh_expires_at":"2026-12-01T00:00:00Z"}}"#.utf8))
            }
            if request.url?.path == "/api/v1/auth/refresh" {
                refreshCalls += 1
                let saved = try #require(credentials.bytes)
                let object = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
                #expect(object["refreshPending"] as? Bool == true)
                throw URLError(.timedOut)
            }
            Issue.record("刷新失败后不应继续请求")
            throw URLError(.unknown)
        }
        controller.login(username: "example", password: "example-password")
        for _ in 0..<200 {
            if !controller.busy { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(refreshCalls == 1)
        #expect(!controller.loggedIn && credentials.bytes == nil)
        #expect(controller.message?.contains("重新登录") == true)
        controller.tick(data: AppData())
        #expect(refreshCalls == 1)
    }
}
