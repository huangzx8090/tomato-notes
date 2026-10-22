import Foundation
import Testing
import TomatoCore
@testable import TomatoSystem

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, bytes) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct DeepSeekTests {
    private func client() -> DeepSeekClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return DeepSeekClient(session: URLSession(configuration: configuration))
    }

    private func context(images: [WorkImage] = []) -> ReviewContext {
        var data = AppData()
        var record = WorkRecord(localDay: "2026-10-21")
        record.userText = "检查页面并完成布局"
        record.images = images
        data.workRecords = [record]
        return ReviewContextBuilder.build(for: .day("2026-10-21"), from: data)
    }

    @Test func sendsMultimodalRequestAndParsesStructuredResults() async throws {
        let expected = WorkSummary(activities: ["检查页面"], outcomes: ["图片显示布局结果"], nextSteps: ["继续验收"], uncertainties: [])
        StubProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-key")
            let body: Data
            if let bytes = request.httpBody { body = bytes }
            else {
                let stream = try #require(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var bytes = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
                body = bytes
            }
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == DeepSeekClient.model)
            #expect((json["thinking"] as? [String: String])?["type"] == "disabled")
            let messages = try #require(json["messages"] as? [[String: Any]])
            let parts = try #require(messages[1]["content"] as? [[String: Any]])
            #expect(parts.count == 2)
            #expect((parts[1]["image_url"] as? [String: String])?["url"] == "data:image/jpeg;base64,AQID")
            let result = String(data: try JSONEncoder().encode(expected), encoding: .utf8)!
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": result]]]]))
        }
        let summary = try await client().summarize(context: context(images: [WorkImage(name: "测试.jpg")]), images: [Data([1, 2, 3])], apiKey: "fake-test-key")
        #expect(summary == expected)
    }

    @Test func authorizationFailureDoesNotExposeServerBodyOrKey() async throws {
        StubProtocol.handler = { _ in (401, Data("response contains fake-test-key".utf8)) }
        do {
            _ = try await client().summarize(context: context(), images: [], apiKey: "fake-test-key")
            Issue.record("401 应显示可重试错误")
        } catch {
            #expect(error.localizedDescription.contains("API Key"))
            #expect(!error.localizedDescription.contains("fake-test-key"))
            #expect(!error.localizedDescription.contains("response contains"))
        }
    }

    @Test func refusesTruncatedOrMalformedCompletion() async throws {
        for response in [
            ["choices": [["finish_reason": "length", "message": ["content": "{}"]]]],
            ["choices": [["finish_reason": "stop", "message": ["content": "not json"]]]]
        ] {
            StubProtocol.handler = { _ in (200, try JSONSerialization.data(withJSONObject: response)) }
            do {
                _ = try await client().summarize(context: context(), images: [], apiKey: "fake-test-key")
                Issue.record("不完整或错误结果不能覆盖已保存的总结")
            } catch is DeepSeekError {}
        }
    }

    @Test func missingPicturesAndMissingKeyNeverSendRequest() async throws {
        StubProtocol.handler = { _ in Issue.record("缺少材料时不应发请求"); return (200, Data()) }
        do {
            _ = try await client().summarize(context: context(images: [WorkImage(name: "missing.jpg")]), images: [], apiKey: "fake-test-key")
            Issue.record("缺少图片应阻止生成")
        } catch is DeepSeekError {}
        do {
            _ = try await client().summarize(context: context(), images: [], apiKey: "")
            Issue.record("缺少密钥应阻止生成")
        } catch is DeepSeekError {}
    }

    @Test func testConnectionOnlyChecksModelEndpoint() async throws {
        StubProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/models")
            #expect(request.httpBody == nil)
            return (200, Data("{\"data\":[]}".utf8))
        }
        try await client().testConnection(apiKey: "fake-test-key")
    }

    @Test func focusAssessmentSendsOneImageWithoutURLSecretsAndReturnsUsage() async throws {
        StubProtocol.handler = { request in
            let data = try Self.requestBody(request)
            let raw = String(decoding: data, as: UTF8.self)
            #expect(!raw.contains("private-query-value"))
            let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["max_tokens"] as? Int == 400)
            let messages = try #require(body["messages"] as? [[String: Any]])
            let parts = try #require(messages[1]["content"] as? [[String: Any]])
            #expect(parts.count == 2)
            let relevance = FocusRelevance(verdict: .unrelated, confidence: 0.97, reason: "截图显示与数学无关的游戏页面")
            let content = String(decoding: try JSONEncoder().encode(relevance), as: UTF8.self)
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]],
                                                                    "usage": ["prompt_tokens": 1300, "completion_tokens": 50]]))
        }
        let result = try await client().assessFocus(goal: "微积分", page: testPage(), image: Data([1, 2, 3]), apiKey: "fake-test-key")
        #expect(result.relevance.permitsClosing)
        #expect(result.inputTokens == 1300 && result.outputTokens == 50)
    }

    @Test func invalidOrUncertainFocusResultsNeverAuthorizeClosing() async throws {
        for content in ["{\"verdict\":\"unrelated\",\"confidence\":2,\"reason\":\"错误置信度\"}", "not json"] {
            StubProtocol.handler = { _ in (200, try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]])) }
            do {
                _ = try await client().assessFocus(goal: "微积分", page: testPage(), image: Data([1]), apiKey: "fake-test-key")
                Issue.record("非法 AI 结果应拒绝关闭")
            } catch is FocusAssessmentError {}
        }
        StubProtocol.handler = { _ in
            let content = "{\"verdict\":\"uncertain\",\"confidence\":0.95,\"reason\":\"可能是课程视频\"}"
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]]))
        }
        let result = try await client().assessFocus(goal: "微积分", page: testPage(), image: Data([1]), apiKey: "fake-test-key")
        #expect(!result.relevance.permitsClosing)
    }

    @Test func privateInternalAndInvalidWindowsNeverSendFocusImage() async throws {
        StubProtocol.handler = { _ in Issue.record("不可读取的页面不能发送截图"); return (200, Data()) }
        var privatePage = testPage(); privatePage.isPrivate = true
        var internalPage = testPage(); internalPage.url = "chrome://settings"
        var filePage = testPage(); filePage.url = "file:///Users/example/private.html"
        var invalid = testPage(); invalid.bounds.width = .nan
        for page in [privatePage, internalPage, filePage, invalid] {
            do {
                _ = try await client().assessFocus(goal: "微积分", page: page, image: Data([1]), apiKey: "fake-test-key")
                Issue.record("应拒绝无法可靠核对的页面")
            } catch is FocusAssessmentError {}
        }
        do {
            _ = try await client().assessFocus(goal: String(repeating: "学", count: 301), page: testPage(), image: Data([1]), apiKey: "fake-test-key")
            Issue.record("不能截断学习目标后按不完整的目标关闭页面")
        } catch is FocusAssessmentError {}
    }

    private func testPage() -> GuardPage {
        .init(windowID: "w1", tabID: "t1", url: "https://example.test/watch?token=private-query-value", title: "休闲游戏",
              isPrivate: false, bounds: .init(x: 0, y: 0, width: 1000, height: 700))
    }
    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}
