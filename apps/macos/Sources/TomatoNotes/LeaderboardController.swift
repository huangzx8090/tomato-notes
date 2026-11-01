import AppKit
import CryptoKit
import Foundation
import TomatoCore

private struct SavedRankingCredentials: Codable {
    var session: LeaderboardSession
    var refreshPending: Bool
}
private struct EmptyResponse: Decodable, Sendable {}

@MainActor
final class LeaderboardController: ObservableObject {
    static let serverURL = URL(string: "http://59.110.50.227:8080")!
    @Published private(set) var loggedIn = false
    @Published private(set) var busy = false
    @Published private(set) var nickname = ""
    @Published private(set) var profile: BoardUser?
    @Published private(set) var profileAvatar: Data?
    @Published private(set) var boardAvatars: [String: Data] = [:]
    @Published private(set) var privacy: BoardPrivacy?
    @Published private(set) var board: DailyBoard?
    @Published private(set) var own: OwnRank?
    @Published var message: String?
    @Published private(set) var page = 1
    @Published private(set) var selectedDay: String?
    private var auth: LeaderboardSession?
    private let api: LeaderboardAPI
    private let credentials: any RankingCredentialStore
    private let syncURL: URL
    private var lastPoll: TimeInterval = 0
    private var latestData: AppData?

    init(repository: LocalRepository, api: LeaderboardAPI? = nil, credentials: (any RankingCredentialStore)? = nil) {
        self.api = api ?? LeaderboardAPI(baseURL: Self.serverURL)
        let hash = SHA256.hash(data: Data(repository.fileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        self.credentials = credentials ?? LeaderboardCredentials(account: hash)
        self.syncURL = repository.fileURL.deletingLastPathComponent().appendingPathComponent("leaderboard-sync.json")
        do {
            if let bytes = try self.credentials.read() {
                let saved = try JSONDecoder().decode(SavedRankingCredentials.self, from: bytes)
                if saved.refreshPending {
                    try self.credentials.remove()
                    message = "上次登录刷新结果未确认，请重新登录。"
                } else {
                    auth = saved.session
                    loggedIn = true
                }
            }
        } catch { message = "读取排行榜登录状态失败：\(error.localizedDescription)" }
    }

    private func persist(_ session: LeaderboardSession, pending: Bool = false) throws {
        try credentials.save(JSONEncoder().encode(SavedRankingCredentials(session: session, refreshPending: pending)))
    }

    private func accessToken() async throws -> String {
        guard let current = auth else { throw LeaderboardAPIError(code: "AUTH", detail: "请先登录。") }
        guard current.accessExpiresAt <= Date() else { return current.accessToken }
        // 旧刷新令牌一旦发出就不可再重试。崩溃或超时后重新登录，防止重放撤销会话。
        try persist(current, pending: true)
        do {
            let body = try LeaderboardAPI.json(["refresh_token": current.refreshToken])
            let next: LeaderboardSession = try await api.request("POST", "/auth/refresh", body: body)
            try persist(next)
            auth = next
            return next.accessToken
        } catch {
            auth = nil
            loggedIn = false
            clearAccountState()
            try? credentials.remove()
            throw LeaderboardAPIError(code: "REFRESH", detail: "登录刷新未完成，请重新登录。")
        }
    }

    private func authenticated<T: Decodable & Sendable>(_ method: String, _ path: String, body: Data? = nil,
                                              query: [URLQueryItem] = [], contentType: String = "application/json") async throws -> T {
        let token = try await accessToken()
        do { return try await api.request(method, path, token: token, body: body, query: query, contentType: contentType) }
        catch let error as LeaderboardAPIError where error.code == "UNAUTHENTICATED" {
            auth = nil; loggedIn = false; clearAccountState()
            try? credentials.remove()
            throw LeaderboardAPIError(code: error.code, detail: "登录已失效，请重新登录。")
        }
    }

    func login(username: String, password: String) {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let body = try LeaderboardAPI.json(["username": username, "password": password, "platform": "macos", "device_name": Host.current().localizedName ?? "Mac"])
                let session: LeaderboardSession = try await api.request("POST", "/auth/login", body: body)
                try persist(session)
                auth = session; loggedIn = true
                try await reload()
                try await sync()
            } catch { message = error.localizedDescription }
        }
    }

    func logout() {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            var remoteFailed = false
            do { let _: EmptyResponse = try await authenticated("POST", "/auth/logout") }
            catch { remoteFailed = true }
            do { try credentials.remove() }
            catch { message = error.localizedDescription; return }
            auth = nil; loggedIn = false; clearAccountState()
            message = remoteFailed ? "已清除本机登录；服务器会话未能撤销。" : "已退出登录。"
        }
    }

    private func clearAccountState() {
        privacy = nil; board = nil; own = nil; nickname = ""
        profile = nil; profileAvatar = nil; boardAvatars = [:]
    }

    func updateNickname(_ name: String) {
        guard !busy, loggedIn else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 40, !trimmed.contains("\n"), !trimmed.contains("\r"), !trimmed.contains("\0") else {
            message = "昵称需为 1 至 40 个字符，不能包含换行。"; return
        }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let body = try LeaderboardAPI.json(["nickname": trimmed])
                let updated: BoardUser = try await authenticated("PATCH", "/me", body: body)
                profile = updated; nickname = updated.nickname
                message = "昵称已更新。"
                try? await loadBoard()
            } catch { message = error.localizedDescription }
        }
    }

    func uploadAvatar(_ data: Data, mime: String) {
        guard !busy, loggedIn else { return }
        guard !data.isEmpty, data.count <= 5 * 1024 * 1024,
              ["image/png", "image/jpeg", "image/gif"].contains(mime) else {
            message = "请选择不超过 5 MiB 的 PNG、JPG 或 GIF 图片。"; return
        }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let boundary = "TomatoNotes-" + UUID().uuidString
                let body = LeaderboardAPI.avatarBody(data: data, type: mime, boundary: boundary)
                let uploaded: AvatarUpload = try await authenticated("PUT", "/me/avatar", body: body,
                    contentType: "multipart/form-data; boundary=\(boundary)")
                let token = try await accessToken()
                profileAvatar = try? await api.avatar(path: uploaded.avatarUrl, token: token)
                if let previous = profile {
                    profile = BoardUser(nickname: previous.nickname, username: previous.username,
                                        avatarUrl: uploaded.avatarUrl, avatarPreviewUrl: uploaded.previewUrl)
                }
                message = profileAvatar == nil ? "头像已更新，预览暂时无法加载。" : "头像已更新。"
                try? await loadBoard()
            } catch { message = error.localizedDescription }
        }
    }

    func removeAvatar() {
        guard !busy, loggedIn else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let _: EmptyResponse = try await authenticated("DELETE", "/me/avatar")
                profileAvatar = nil
                if let previous = profile {
                    profile = BoardUser(nickname: previous.nickname, username: previous.username,
                                        avatarUrl: nil, avatarPreviewUrl: nil)
                }
                message = "头像已移除。"
                try? await loadBoard()
            } catch { message = error.localizedDescription }
        }
    }

    func setParticipation(_ participating: Bool, mode: String) {
        guard !busy, loggedIn else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let body = try LeaderboardAPI.json(["participating": participating, "display_mode": mode])
                let updated: BoardPrivacy = try await authenticated("PATCH", "/me/privacy", body: body)
                privacy = updated
                if participating { try await sync() }
                try await loadBoard()
            } catch { message = error.localizedDescription }
        }
    }

    func refresh() {
        guard !busy, loggedIn else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { try await reload(); try await sync(); try await loadBoard() }
            catch { message = error.localizedDescription }
        }
    }

    func showPage(_ newPage: Int) {
        guard !busy, loggedIn, newPage > 0 else { return }
        page = newPage
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { try await loadBoard() } catch { message = error.localizedDescription }
        }
    }

    func changeDay(_ direction: Int) {
        guard !busy, loggedIn else { return }
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "yyyy-MM-dd"
        let current = selectedDay ?? board?.date ?? formatter.string(from: Date())
        guard let date = formatter.date(from: current),
              let next = formatter.calendar.date(byAdding: .day, value: direction, to: date) else { return }
        let text = formatter.string(from: next)
        guard text <= formatter.string(from: Date()) else { return }
        selectedDay = text == formatter.string(from: Date()) ? nil : text; page = 1
        showPage(1)
    }

    func tick(data: AppData) {
        latestData = data
        let uptime = ProcessInfo.processInfo.systemUptime
        guard loggedIn, !busy, uptime - lastPoll >= 30 else { return }
        lastPoll = uptime
        busy = true
        Task {
            defer { busy = false }
            do {
                // 每次上传前重新读取隐私状态，服务器也会核对授权版本。
                let current: BoardPrivacy = try await authenticated("GET", "/me/privacy")
                privacy = current
                try await sync()
                if board == nil { try await reload() } else { try await loadBoard() }
            } catch { message = error.localizedDescription }
        }
    }

    private func reload() async throws {
        let user: BoardUser = try await authenticated("GET", "/me")
        profile = user; nickname = user.nickname
        profileAvatar = nil
        if let path = user.avatarUrl {
            let token = try await accessToken()
            profileAvatar = try? await api.avatar(path: path, token: token)
        }
        let current: BoardPrivacy = try await authenticated("GET", "/me/privacy")
        privacy = current
        try await loadBoard()
    }

    private func loadBoard() async throws {
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: "20")]
        if let selectedDay { query.append(URLQueryItem(name: "date", value: selectedDay)) }
        let loaded: DailyBoard = try await authenticated("GET", "/leaderboards/daily", query: query)
        var ownQuery: [URLQueryItem] = []
        if let selectedDay { ownQuery.append(URLQueryItem(name: "date", value: selectedDay)) }
        let rank: OwnRank = try await authenticated("GET", "/leaderboards/daily/me", query: ownQuery)
        board = loaded; own = rank
        boardAvatars = [:]
        let paths = loaded.items.compactMap { entry in entry.avatarUrl.map { (entry.entryKey, $0) } }
        guard !paths.isEmpty else { return }
        let token = try await accessToken()
        let client = api
        let images = await withTaskGroup(of: (String, Data?).self, returning: [String: Data].self) { group in
            for (key, path) in paths {
                group.addTask { (key, try? await client.avatar(path: path, token: token)) }
            }
            var result: [String: Data] = [:]
            for await (key, data) in group { if let data { result[key] = data } }
            return result
        }
        boardAvatars = images
    }

    private func sync() async throws {
        guard let auth, let privacy, privacy.participating, let data = latestData,
              let since = RankingSync.parse(privacy.participationSince) else { return }
        let store = try RankingSyncStore(url: syncURL)
        let scope = RankingSync.scope(userID: auth.userID, consentVersion: privacy.consentVersion)
        var items = RankingSync.makeQueue(data: data, since: since, now: Date(), scope: scope, existing: store.state.scopes[scope] ?? [:])
        // 在发出请求前持久化版本和完整快照，网络错误后以同一 ID / 版本重试。
        try store.set(items, scope: scope)
        var pending = Array(items.filter { !$0.value.acknowledged && $0.value.error == nil }
            .sorted { $0.key < $1.key }.prefix(50))
        guard !pending.isEmpty else { return }
        var body = try RankingSync.uploadBody(version: privacy.consentVersion, records: pending.map { $0.value.record })
        while body.count > 900_000 && pending.count > 1 {
            pending.removeLast()
            body = try RankingSync.uploadBody(version: privacy.consentVersion, records: pending.map { $0.value.record })
        }
        guard body.count <= 900_000 else {
            throw LeaderboardAPIError(code: "BATCH_TOO_LARGE", detail: "专注记录过大，无法上传。")
        }
        let result: UploadResult = try await authenticated("POST", "/focus/records/batch", body: body)
        for response in result.results {
            guard let key = items.first(where: { $0.value.record.id.lowercased() == response.id.lowercased() })?.key else { continue }
            if response.status == "accepted" || response.status == "duplicate" {
                items[key]?.acknowledged = true
            } else {
                items[key]?.error = response.message ?? "服务器返回 \(response.status)"
            }
        }
        try store.set(items, scope: scope)
        if let failure = items.values.first(where: { $0.error != nil })?.error {
            message = "部分专注记录未能同步：\(failure)"
        } else if !result.frozenDays.isEmpty {
            message = "部分日期的榜单已结算，补传记录不会改变这些日期的成绩。"
        }
    }
}
