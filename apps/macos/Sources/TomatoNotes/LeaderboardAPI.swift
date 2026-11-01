import Foundation
import Security

struct LeaderboardSession: Codable, Sendable {
    let userID: String
    let sessionID: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let refreshExpiresAt: String
    var accessExpiresAt: Date = .distantPast

    enum CodingKeys: String, CodingKey {
        case userID = "userId", sessionID = "sessionId", accessToken = "accessToken"
        case refreshToken = "refreshToken", expiresIn = "expiresIn", refreshExpiresAt = "refreshExpiresAt"
        case accessExpiresAt = "accessExpiresAt"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userID = try values.decode(String.self, forKey: .userID)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        accessToken = try values.decode(String.self, forKey: .accessToken)
        refreshToken = try values.decode(String.self, forKey: .refreshToken)
        expiresIn = try values.decode(Int.self, forKey: .expiresIn)
        refreshExpiresAt = try values.decode(String.self, forKey: .refreshExpiresAt)
        accessExpiresAt = try values.decodeIfPresent(Date.self, forKey: .accessExpiresAt) ?? Date().addingTimeInterval(Double(expiresIn) - 30)
    }
}

struct BoardPrivacy: Codable, Sendable {
    let participating: Bool
    let displayMode: String
    let consentVersion: Int
    let participationSince: String
}
struct BoardUser: Decodable, Sendable { let nickname: String }
struct BoardEntry: Decodable, Identifiable, Sendable {
    let entryKey: String
    let rank: Int
    let nickname: String
    let focusSeconds: Double
    let completedSessions: Int
    let isMe: Bool
    var id: String { entryKey }
}
struct DailyBoard: Decodable, Sendable {
    let date: String
    let state: String
    let total: Int
    let page: Int
    let pageSize: Int
    let items: [BoardEntry]
}
struct OwnRank: Decodable, Sendable { let status: String; let entry: BoardEntry? }
struct UploadResult: Decodable, Sendable {
    struct Result: Decodable, Sendable { let id: String; let status: String; let message: String? }
    let results: [Result]
    let frozenDays: [String]
}
private struct APIEnvelope<Value: Decodable>: Decodable { let code: String; let message: String; let data: Value? }
struct LeaderboardAPIError: LocalizedError {
    let code: String
    let detail: String
    var errorDescription: String? { detail }
}
private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct LeaderboardAPI {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        }
    }

    func request<T: Decodable & Sendable>(_ method: String, _ path: String, token: String? = nil,
                               body: Data? = nil, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw LeaderboardAPIError(code: "URL", detail: "服务地址无效。")
        }
        components.path = "/api/v1" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw LeaderboardAPIError(code: "URL", detail: "请求地址无效。") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LeaderboardAPIError(code: "NETWORK", detail: "服务器响应无效。")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope: APIEnvelope<T>
        do { envelope = try decoder.decode(APIEnvelope<T>.self, from: data) }
        catch { throw LeaderboardAPIError(code: "RESPONSE", detail: "服务器响应无法识别（HTTP \(response.statusCode)）。") }
        guard (200..<300).contains(response.statusCode), let result = envelope.data else {
            throw LeaderboardAPIError(code: envelope.code, detail: envelope.message)
        }
        return result
    }

    static func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
}

/// 两个轮换令牌作为一个钥匙串条目原子保存，不写入资料文件或日志。
protocol RankingCredentialStore {
    func read() throws -> Data?
    func save(_ data: Data) throws
    func remove() throws
}

struct LeaderboardCredentials: RankingCredentialStore {
    let account: String
    private var identity: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.zixuan.TomatoNotes.leaderboard", kSecAttrAccount: account]
    }
    func read() throws -> Data? {
        var query = identity
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LeaderboardAPIError(code: "KEYCHAIN", detail: "无法读取排行榜钥匙串（\(status)）。") }
        return result as? Data
    }
    func save(_ data: Data) throws {
        var status = SecItemUpdate(identity as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LeaderboardAPIError(code: "KEYCHAIN", detail: "无法保存排行榜钥匙串（\(status)）。") }
    }
    func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LeaderboardAPIError(code: "KEYCHAIN", detail: "无法清除排行榜钥匙串（\(status)）。")
        }
    }
}
