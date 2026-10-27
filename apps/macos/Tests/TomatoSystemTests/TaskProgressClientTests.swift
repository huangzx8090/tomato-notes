import Foundation
import Testing
import TomatoCore
@testable import TomatoSystem

private final class TaskProgressProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct TaskProgressClientTests {
    private func client() -> AIReviewClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TaskProgressProtocol.self]
        return AIReviewClient(provider: AIProviderCatalog.deepseek, session: URLSession(configuration: config))
    }
    private static func response(_ content: String, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
    }

    @Test func sendsOnlyExplicitTaskFacts() async throws {
        TaskProgressProtocol.handler = { request in
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(object["messages"] as? [[String: String]])
            let raw = try #require(messages.last?["content"])
            let facts = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            #expect(Set(facts.keys) == ["待办标题", "用户填写的进展", "本轮专注秒数"])
            #expect(facts["待办标题"] as? String == "模拟待办")
            #expect(facts["用户填写的进展"] as? String == "核对了第一步")
            #expect(facts["本轮专注秒数"] as? Double == 120)
            return try Self.response("{\"progress\":\"已核对第一步。\"}")
        }
        #expect(try await client().suggestTaskProgress(title: "模拟待办", evidence: "核对了第一步", focusSeconds: 120, apiKey: "fake-key") == "已核对第一步。")
    }

    @Test(arguments: ["{}", "{\"progress\":\" \"}", "{\"progress\":5}", "{\"progress\":\"ok\",\"extra\":true}", "{\"progress\":\"a\\u0001b\"}", "not json"])
    func rejectsInvalidOutput(_ response: String) async {
        TaskProgressProtocol.handler = { _ in try Self.response(response) }
        await #expect(throws: AIReviewError.self) {
            _ = try await client().suggestTaskProgress(title: "待办", evidence: "实际进展", focusSeconds: 10, apiKey: "fake-key")
        }
    }

    @Test func emptyEvidenceNeverSendsAndTruncatedResponseIsRejected() async {
        TaskProgressProtocol.handler = { _ in Issue.record("空进展不能发起请求"); return Data() }
        await #expect(throws: AIReviewError.self) {
            _ = try await client().suggestTaskProgress(title: "待办", evidence: " ", focusSeconds: 10, apiKey: "fake-key")
        }
        TaskProgressProtocol.handler = { _ in try Self.response("{\"progress\":\"未完整\"}", finish: "length") }
        await #expect(throws: AIReviewError.self) {
            _ = try await client().suggestTaskProgress(title: "待办", evidence: "进展", focusSeconds: 10, apiKey: "fake-key")
        }
    }
}
