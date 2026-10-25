import Foundation
import Testing
import TomatoCore
@testable import TomatoSystem

private final class FocusGoalProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, bytes) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct FocusGoalClientTests {
    private var context: FocusGoalContext {
        .init(plan: .init(goal: "", appIDs: [], pages: [
            .init(kind: .page, value: "https://course.example/watch?token=local-secret", title: "高数 · 导数练习")
        ], allowAIClosing: false), apps: [])
    }
    private func client(_ provider: AIProviderConfig = AIProviderCatalog.deepseek) -> AIReviewClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FocusGoalProtocol.self]
        return .init(provider: provider, session: URLSession(configuration: configuration))
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private static func reply(_ content: String, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]],
            "usage": ["prompt_tokens": 20, "completion_tokens": 8]])
    }

    @Test(arguments: [true, false])
    func usesConfiguredProviderAndSendsOnlySelectedText(thinkingFlag: Bool) async throws {
        let provider = AIProviderConfig(id: "test", name: "模拟服务", baseURL: "https://gateway.example/v1", defaultModel: "chosen-model", sendsThinkingFlag: thinkingFlag)
        FocusGoalProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://gateway.example/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key")
            let body = try Self.body(request)
            #expect(body["model"] as? String == "chosen-model" && body["stream"] as? Bool == false)
            #expect((body["thinking"] != nil) == thinkingFlag)
            let messages = try #require(body["messages"] as? [[String: String]])
            #expect(messages.count == 2 && messages[0]["content"]?.contains("不可信资料") == true)
            let facts = try #require(messages.last?["content"])
            #expect(facts.contains("导数练习") && facts.contains("course.example"))
            for secret in ["token", "local-secret", "/watch", "bundleID", "image_url", "windowID"] { #expect(!facts.contains(secret)) }
            return (200, try Self.reply("{\"title\":\" 高数 · 导数练习 \"}"))
        }
        let result = try await client(provider).suggestFocusGoal(context: context, apiKey: "fake-key")
        #expect(result.title == "高数 · 导数练习" && result.inputTokens == 20 && result.outputTokens == 8)
    }

    @Test(arguments: ["{}", "{\"title\":\" \"}", "{\"title\":1}", "{\"title\":\"名称\",\"extra\":true}",
                      "{\"title\":\"两行\\n名称\"}", "{\"title\":\"" + String(repeating: "长", count: 41) + "\"}", "not json"])
    func rejectsMalformedNames(content: String) async {
        FocusGoalProtocol.handler = { _ in (200, try Self.reply(content)) }
        await #expect(throws: FocusGoalError.self) { _ = try await client().suggestFocusGoal(context: context, apiKey: "fake-key") }
    }

    @Test func rejectsTruncatedResponsesAndHidesServerAndTransportDetails() async {
        FocusGoalProtocol.handler = { _ in (200, try Self.reply("{\"title\":\"未完成\"}", finish: "length")) }
        await #expect(throws: FocusGoalError.self) { _ = try await client().suggestFocusGoal(context: context, apiKey: "fake-key") }
        FocusGoalProtocol.handler = { _ in (401, Data("server-secret fake-key".utf8)) }
        do { _ = try await client().suggestFocusGoal(context: context, apiKey: "fake-key"); Issue.record("应拒绝 HTTP 错误") }
        catch { #expect(!error.localizedDescription.contains("server-secret") && !error.localizedDescription.contains("fake-key")) }
        FocusGoalProtocol.handler = { _ in throw NSError(domain: "server-secret", code: 1, userInfo: [NSLocalizedDescriptionKey: "fake-key"]) }
        do { _ = try await client().suggestFocusGoal(context: context, apiKey: "fake-key"); Issue.record("应拒绝网络错误") }
        catch { #expect(!error.localizedDescription.contains("server-secret") && !error.localizedDescription.contains("fake-key")) }
    }

    @Test func emptyWhitelistOrMissingConfigurationDoesNotSendRequests() async {
        FocusGoalProtocol.handler = { _ in Issue.record("配置或白名单为空时不能发出请求"); return (200, Data()) }
        let empty = FocusGoalContext(plan: .init(goal: "", appIDs: [], pages: [], allowAIClosing: false), apps: [])
        await #expect(throws: FocusGoalError.self) { _ = try await client().suggestFocusGoal(context: empty, apiKey: "fake-key") }
        await #expect(throws: AIReviewError.self) { _ = try await client().suggestFocusGoal(context: context, apiKey: " ") }
        var provider = AIProviderCatalog.deepseek
        provider.defaultModel = ""
        await #expect(throws: AIReviewError.self) { _ = try await client(provider).suggestFocusGoal(context: context, apiKey: "fake-key") }
    }
}
