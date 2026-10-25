import Foundation
import Testing
import TomatoCore
@testable import TomatoSystem

private enum FocusWhitelistStubReply {
    case http(Int, Data)
    case nonHTTP(Data)
    case pending
}

/// 与 AIReviewClientTests 的 StubProtocol 隔离，避免两个 suite 并行时覆盖 handler。
private final class FocusWhitelistStubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> FocusWhitelistStubReply)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let response: URLResponse, bytes: Data
            switch try handler(request) {
            case .http(let status, let data):
                response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
                bytes = data
            case .nonHTTP(let data):
                response = URLResponse(url: request.url!, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: "utf-8")
                bytes = data
            case .pending: return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class FocusWhitelistRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [Int] = []

    @discardableResult func record(_ size: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        sizes.append(size)
        return sizes.count
    }
    var batchSizes: [Int] {
        lock.lock(); defer { lock.unlock() }
        return sizes
    }
}

private actor FocusWhitelistRequestSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() {
        signaled = true
        continuation?.resume(); continuation = nil
    }
    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

@Suite(.serialized)
struct FocusWhitelistClientTests {
    private struct Facts: Decodable {
        let goal: String
        let candidates: [FocusWhitelistCandidate]
    }

    private func client(provider: AIProviderConfig = AIProviderCatalog.deepseek) -> AIReviewClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FocusWhitelistStubProtocol.self]
        return AIReviewClient(provider: provider, session: URLSession(configuration: configuration))
    }

    private func candidates(_ count: Int = 2) -> [FocusWhitelistCandidate] {
        (0..<count).map { .init(id: "a\($0)", kind: .app, name: "编辑器 \($0)", detail: "编程工具") }
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private static func facts(_ request: URLRequest) throws -> Facts {
        let body = try #require(try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
        return try facts(body)
    }

    private static func facts(_ body: [String: Any]) throws -> Facts {
        let messages = try #require(body["messages"] as? [[String: Any]])
        let text = try #require(messages.last?["content"] as? String)
        return try JSONDecoder().decode(Facts.self, from: Data(text.utf8))
    }

    private static func completion(content: String?, finishReason: String = "stop", usage: (Int, Int)? = nil) throws -> FocusWhitelistStubReply {
        var body: [String: Any] = ["choices": [["finish_reason": finishReason, "message": ["content": content as Any? ?? NSNull()]]]]
        if let usage { body["usage"] = ["prompt_tokens": usage.0, "completion_tokens": usage.1] }
        return .http(200, try JSONSerialization.data(withJSONObject: body))
    }

    private static func reply(_ suggestions: [FocusWhitelistSuggestion], usage: (Int, Int)? = nil) throws -> FocusWhitelistStubReply {
        let content = String(decoding: try JSONEncoder().encode(["suggestions": suggestions]), as: UTF8.self)
        return try completion(content: content, usage: usage)
    }

    private static func success(_ candidates: [FocusWhitelistCandidate], usage: (Int, Int)? = nil) throws -> FocusWhitelistStubReply {
        try reply(candidates.reversed().map { .init(id: $0.id, disposition: .optional, reason: "可能用于本轮任务，具体用途待确认") }, usage: usage)
    }

    private func expectInvalidResponse(candidates: [FocusWhitelistCandidate]? = nil) async {
        do {
            _ = try await client().recommendWhitelist(goal: "编写程序", candidates: candidates ?? self.candidates(), apiKey: "fake-whitelist-key")
            Issue.record("应拒绝无效白名单推荐")
        } catch FocusWhitelistRecommendationError.invalidResponse {
        } catch { Issue.record("响应错误应使用白名单推荐专用类型") }
    }

    @Test func sendsOnlyTextDescriptionsAndMapsResultsByTemporaryID() async throws {
        let candidates: [FocusWhitelistCandidate] = [
            .init(id: "a0", kind: .app, name: "编辑器", detail: "编程工具"),
            .init(id: "p0", kind: .page, name: "Swift 课程", detail: "课程页面")
        ]
        // 这些真实映射仅留在本地，客户端只能收到临时 ID 及文本描述。
        let localMapping = ["a0": "com.private.editor", "p0": "https://course.test/watch?token=private-query-value#secret"]
        FocusWhitelistStubProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-whitelist-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let data = try Self.requestBody(request)
            let raw = String(decoding: data, as: UTF8.self)
            for secret in localMapping.values { #expect(!raw.contains(secret)) }
            for field in ["private-query-value", "bundleID", "windowID", "tabID", "image_url", "base64", "screenshot"] {
                #expect(!raw.contains(field))
            }
            let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["model"] as? String == "deepseek-chat")
            #expect(body["stream"] as? Bool == false)
            #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
            #expect((body["max_tokens"] as? Int ?? 0) >= 6000)
            #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
            let messages = try #require(body["messages"] as? [[String: Any]])
            #expect(messages.count == 2)
            #expect(messages[0]["role"] as? String == "system")
            #expect(messages[1]["role"] as? String == "user")
            #expect(messages.allSatisfy { $0["content"] is String })
            let instructions = try #require(messages[0]["content"] as? String)
            #expect(instructions.contains("不可信数据"))
            #expect(instructions.contains("optional"))
            #expect(instructions.contains("中文"))
            #expect(instructions.contains("全部放行"))
            #expect(instructions.contains("只有 distraction 才能对应 excluded"))
            #expect(instructions.contains("Clash Verge") && instructions.contains("音乐可能是学习背景音"))
            let text = try #require(messages[1]["content"] as? String)
            let factsJSON = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(Set(factsJSON.keys) == ["goal", "candidates"])
            let entries = try #require(factsJSON["candidates"] as? [[String: Any]])
            #expect(entries.allSatisfy { Set($0.keys) == ["id", "kind", "name", "detail"] })
            let facts = try Self.facts(body)
            #expect(facts.goal == "完成 Swift 练习")
            #expect(facts.candidates == candidates)
            return try Self.reply([.init(id: "p0", disposition: .recommended, reason: " \n课程直接支持本轮练习 "),
                                   .init(id: "a0", disposition: .optional, reason: "可用于编写练习，需确认用途")], usage: (321, 87))
        }
        let result = try await client().recommendWhitelist(goal: " \n完成 Swift 练习\t ", candidates: candidates, apiKey: " fake-whitelist-key\n")
        #expect(result.suggestions.map(\.id) == ["a0", "p0"])
        #expect(result.suggestions[0].disposition == .optional)
        #expect(result.suggestions[1].disposition == .recommended)
        #expect(result.suggestions[1].reason == "课程直接支持本轮练习")
        #expect(result.inputTokens == 321 && result.outputTokens == 87)
    }

    @Test func openAIAndCustomProviderUseTheirEndpointModelAndThinkingPreference() async throws {
        for provider in [
            AIProviderConfig(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1/", defaultModel: "gpt-4o-mini", sendsThinkingFlag: false),
            AIProviderConfig(id: "custom", name: "自定义", baseURL: "https://gateway.test/api/v1///", defaultModel: "custom-model", sendsThinkingFlag: true)
        ] {
            FocusWhitelistStubProtocol.handler = { request in
                #expect(request.url == provider.apiURL)
                let body = try #require(try JSONSerialization.jsonObject(with: Self.requestBody(request)) as? [String: Any])
                #expect(body["model"] as? String == provider.defaultModel)
                if provider.sendsThinkingFlag {
                    #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
                } else { #expect(body["thinking"] == nil) }
                return try Self.success(Self.facts(body).candidates)
            }
            let result = try await client(provider: provider).recommendWhitelist(goal: "编写程序", candidates: candidates(), apiKey: "fake-whitelist-key")
            #expect(result.suggestions.count == 2)
            #expect(result.inputTokens == 0 && result.outputTokens == 0)
        }
    }

    @Test func missingKeyModelOrEndpointNeverSendsARequest() async {
        FocusWhitelistStubProtocol.handler = { _ in Issue.record("缺少配置时不能发请求"); return .http(200, Data()) }
        for key in ["", " \n\t "] {
            do {
                _ = try await client().recommendWhitelist(goal: "编写程序", candidates: candidates(), apiKey: key)
                Issue.record("空 Key 应阻止请求")
            } catch AIReviewError.missingKey {
            } catch { Issue.record("应提示缺少 API Key") }
        }
        let missingModel = AIProviderConfig(id: "custom", name: "自定义", baseURL: "https://gateway.test", defaultModel: " ", sendsThinkingFlag: false)
        do {
            _ = try await client(provider: missingModel).recommendWhitelist(goal: "编写程序", candidates: candidates(), apiKey: "fake-whitelist-key")
            Issue.record("缺少模型应阻止请求")
        } catch AIReviewError.missingModel {
        } catch { Issue.record("应提示缺少模型") }
        let invalidURL = AIProviderConfig(id: "custom", name: "自定义", baseURL: "file:///private", defaultModel: "model", sendsThinkingFlag: false)
        do {
            _ = try await client(provider: invalidURL).recommendWhitelist(goal: "编写程序", candidates: candidates(), apiKey: "fake-whitelist-key")
            Issue.record("无效地址应阻止请求")
        } catch AIReviewError.invalidBaseURL {
        } catch { Issue.record("应提示接口地址无效") }
    }

    @Test func validatesAllBatchesBeforeSendingAndNeverSilentlyTruncates() async {
        FocusWhitelistStubProtocol.handler = { _ in Issue.record("后续批次的资料无效时，第一批也不能发出"); return .http(200, Data()) }
        var duplicate = candidates(81)
        duplicate[80].id = duplicate[0].id
        var longName = candidates(81)
        longName[80].name = String(repeating: "名", count: 241)
        var longDetail = candidates(81)
        longDetail[80].detail = String(repeating: "详", count: 161)
        let overBatchLimit = candidates(FocusWhitelistRecommendation.maximumCandidatesPerBatch * FocusWhitelistRecommendation.maximumBatchCount + 1)
        for input in [[], duplicate, longName, longDetail, overBatchLimit] {
            do {
                _ = try await client().recommendWhitelist(goal: "编写程序", candidates: input, apiKey: "fake-whitelist-key")
                Issue.record("全量校验不能截断候选或忽略跨批重复 ID")
            } catch FocusWhitelistRecommendationError.invalidContext {
            } catch { Issue.record("候选资料无效应返回专用上下文错误") }
        }
        for goal in [" \n ", String(repeating: "学", count: 301)] {
            do {
                _ = try await client().recommendWhitelist(goal: goal, candidates: candidates(), apiKey: "fake-whitelist-key")
                Issue.record("目标无效不能截断后发送")
            } catch FocusWhitelistRecommendationError.invalidContext {
            } catch { Issue.record("目标无效应返回专用上下文错误") }
        }
    }

    @Test func totalTextBudgetIsCheckedBeforeAnyBatchIsSent() async {
        FocusWhitelistStubProtocol.handler = { _ in Issue.record("全量文本超限时不能发送部分候选"); return .http(200, Data()) }
        let name = String(repeating: "名\u{0301}", count: 240)
        let detail = String(repeating: "详\u{0301}", count: 160)
        let input = candidates(10_240).map { FocusWhitelistCandidate(id: $0.id, kind: .app, name: name, detail: detail) }
        do {
            _ = try await client().recommendWhitelist(goal: "编写程序", candidates: input, apiKey: "fake-whitelist-key")
            Issue.record("16 MiB 全量预算应明确报错")
        } catch FocusWhitelistRecommendationError.invalidContext {
        } catch { Issue.record("超出尺寸预算应返回专用上下文错误") }
    }

    @Test func httpFailuresDoNotExposeServerBodyOrAPIKey() async {
        for status in [302, 401, 402, 403, 404, 429, 500] {
            FocusWhitelistStubProtocol.handler = { _ in .http(status, Data("server-secret fake-whitelist-key".utf8)) }
            do {
                _ = try await client().recommendWhitelist(goal: "编写程序", candidates: candidates(), apiKey: "fake-whitelist-key")
                Issue.record("HTTP 错误不能返回建议")
            } catch AIReviewError.http(let code) {
                #expect(code == status)
                let text = AIReviewError.http(code).localizedDescription
                #expect(!text.contains("server-secret"))
                #expect(!text.contains("fake-whitelist-key"))
                #expect(!text.contains("总结"))
            } catch { Issue.record("应保留现有服务商 HTTP 错误") }
        }
    }

    @Test func networkErrorsAreSanitizedRatherThanEchoingUnderlyingDescriptions() async {
        FocusWhitelistStubProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "server-secret fake-whitelist-key"])
        }
        do {
            _ = try await client().recommendWhitelist(goal: "编写程序", candidates: candidates(), apiKey: "fake-whitelist-key")
            Issue.record("网络失败不能返回建议")
        } catch FocusWhitelistRecommendationError.invalidResponse {
            let text = FocusWhitelistRecommendationError.invalidResponse.localizedDescription
            #expect(!text.contains("server-secret"))
            #expect(!text.contains("fake-whitelist-key"))
            #expect(text.contains("白名单推荐"))
        } catch { Issue.record("不能透传可能包含密钥的底层错误") }
    }

    @Test func rejectsNonHTTPAndOversizedResponses() async {
        for reply in [FocusWhitelistStubReply.nonHTTP(Data()), .http(200, Data(repeating: 32, count: 1024 * 1024 + 1))] {
            FocusWhitelistStubProtocol.handler = { _ in reply }
            await expectInvalidResponse()
        }
    }

    @Test func rejectsMalformedIncompleteAndNullCompletions() async throws {
        let valid = "{\"suggestions\":[{\"id\":\"a0\",\"disposition\":\"optional\",\"reason\":\"用途待确认\"},{\"id\":\"a1\",\"disposition\":\"excluded\",\"reason\":\"与目标无关\"}]}"
        for reply in [
            FocusWhitelistStubReply.http(200, Data("not json".utf8)),
            .http(200, Data("{\"choices\":[]}".utf8)),
            try Self.completion(content: nil),
            try Self.completion(content: "not json"),
            try Self.completion(content: "{\"suggestions\":["),
            try Self.completion(content: valid, finishReason: "length"),
            try Self.completion(content: valid, finishReason: "content_filter")
        ] {
            FocusWhitelistStubProtocol.handler = { _ in reply }
            await expectInvalidResponse()
        }
    }

    @Test func rejectsUnknownDuplicateMissingIDsAndInvalidReasons() async throws {
        let valid = candidates().map { FocusWhitelistSuggestion(id: $0.id, disposition: .optional, reason: "用途待确认") }
        var cases: [[FocusWhitelistSuggestion]] = [Array(valid.prefix(1)), valid + [.init(id: "unknown", disposition: .recommended, reason: "虚构候选")]]
        for id in ["unknown", "a0", "https://invented.test/", "com.private.editor"] {
            var invalid = valid
            invalid[1].id = id
            cases.append(invalid)
        }
        for reason in ["", " \n\t ", String(repeating: "理", count: 201)] {
            var invalid = valid
            invalid[1].reason = reason
            cases.append(invalid)
        }
        for suggestions in cases {
            FocusWhitelistStubProtocol.handler = { _ in try Self.reply(suggestions) }
            await expectInvalidResponse()
        }
        for content in [
            "{\"suggestions\":[{\"id\":\"a0\",\"disposition\":\"allow\",\"reason\":\"用途\"},{\"id\":\"a1\",\"disposition\":\"optional\",\"reason\":\"用途\"}]}",
            "{\"suggestions\":[],\"rules\":[{\"url\":\"https://invented.test/\"}]}"
        ] {
            FocusWhitelistStubProtocol.handler = { _ in try Self.completion(content: content) }
            await expectInvalidResponse()
        }
    }

    @Test func allDistractionsCanBeExcluded() async throws {
        let input: [FocusWhitelistCandidate] = [.init(id: "game", kind: .app, name: "游戏", detail: "游戏娱乐"),
                                                .init(id: "drama", kind: .page, name: "电视剧全集", detail: "追剧")]
        let expected = input.map { FocusWhitelistSuggestion(id: $0.id, disposition: .excluded, reason: "本轮无关的游戏或追剧内容", purpose: .distraction) }
        FocusWhitelistStubProtocol.handler = { _ in try Self.reply(expected) }
        let result = try await client().recommendWhitelist(goal: "练习写作", candidates: input, apiKey: "fake-whitelist-key")
        #expect(result.suggestions == expected)
    }

    @Test func networkAndStudySupportAreRetainedWhileActualEntertainmentIsExcluded() async throws {
        let input: [FocusWhitelistCandidate] = [
            .init(id: "network", kind: .app, name: "Clash Verge", detail: "网络连接辅助工具", support: .network),
            .init(id: "control", kind: .page, name: "AI API 控制台", detail: "127.0.0.1"),
            .init(id: "project", kind: .page, name: "番茄小记 · Releases", detail: "github.com"),
            .init(id: "music", kind: .app, name: "NetEaseMusic", detail: "当前运行的应用"),
            .init(id: "course", kind: .page, name: "数据库课程", detail: "课程网站"),
            .init(id: "drama", kind: .page, name: "追剧：电视剧全集", detail: "视频网站"),
            .init(id: "game", kind: .app, name: "游戏对局", detail: "游戏应用")
        ]
        FocusWhitelistStubProtocol.handler = { request in
            let facts = try Self.facts(request)
            #expect(facts.candidates == input && facts.candidates[0].support == .network)
            return try Self.reply([
                .init(id: "network", disposition: .excluded, reason: "与软考无直接关系", purpose: .distraction),
                .init(id: "control", disposition: .excluded, reason: "与软考无直接关系", purpose: .support),
                .init(id: "project", disposition: .excluded, reason: "与软考无直接关系", purpose: .support),
                .init(id: "music", disposition: .excluded, reason: "背景音乐用途待确认", purpose: .uncertain),
                .init(id: "course", disposition: .recommended, reason: "提供数据库学习资料", purpose: .learning),
                .init(id: "drama", disposition: .excluded, reason: "无关追剧活动", purpose: .distraction),
                .init(id: "game", disposition: .excluded, reason: "游戏对局会分散本轮注意力", purpose: .distraction)
            ])
        }
        let result = try await client().recommendWhitelist(goal: "软考复习", candidates: input, apiKey: "fake-whitelist-key")
        #expect(result.suggestions.map(\.disposition) == [.recommended, .recommended, .recommended, .optional, .recommended, .excluded, .excluded])
    }

    @Test func batchesMoreThanOneHundredCandidatesAndAccumulatesUsage() async throws {
        let input = candidates(121)
        let log = FocusWhitelistRequestLog()
        FocusWhitelistStubProtocol.handler = { request in
            let facts = try Self.facts(request)
            #expect(facts.goal == "编写程序")
            #expect(facts.candidates.count <= 40)
            let index = log.record(facts.candidates.count)
            return try Self.success(facts.candidates, usage: (index * 100, index * 10))
        }
        let result = try await client().recommendWhitelist(goal: "编写程序", candidates: input, apiKey: "fake-whitelist-key")
        #expect(log.batchSizes == [40, 40, 40, 1])
        #expect(result.suggestions.map(\.id) == input.map(\.id))
        #expect(result.inputTokens == 1000 && result.outputTokens == 100)
    }

    @Test func failureInLaterBatchReturnsNoPartialResultAndStartsNoFurtherBatch() async {
        let log = FocusWhitelistRequestLog()
        FocusWhitelistStubProtocol.handler = { request in
            let facts = try Self.facts(request)
            let index = log.record(facts.candidates.count)
            if index == 2 {
                // 即使 ID 属于第一批，也不能替代当前批次的候选。
                var invalid = facts.candidates
                invalid[0].id = "a0"
                return try Self.success(invalid)
            }
            return try Self.success(facts.candidates, usage: (10, 5))
        }
        await expectInvalidResponse(candidates: candidates(81))
        #expect(log.batchSizes == [40, 40])
    }

    @Test func rejectsNegativeAndOverflowingTokenUsage() async throws {
        for usage in [(-1, 10), (10, -1)] {
            FocusWhitelistStubProtocol.handler = { request in try Self.success(Self.facts(request).candidates, usage: usage) }
            await expectInvalidResponse()
        }
        let log = FocusWhitelistRequestLog()
        FocusWhitelistStubProtocol.handler = { request in
            let facts = try Self.facts(request)
            let index = log.record(facts.candidates.count)
            return try Self.success(facts.candidates, usage: index == 1 ? (Int.max, Int.max) : (1, 1))
        }
        await expectInvalidResponse(candidates: candidates(41))
        #expect(log.batchSizes == [40, 1])
    }

    @Test func cancelledTaskNeverSendsFirstBatch() async {
        FocusWhitelistStubProtocol.handler = { _ in Issue.record("取消后不应发出请求"); return .http(200, Data()) }
        let client = client(), input = candidates(81)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.recommendWhitelist(goal: "编写程序", candidates: input, apiKey: "fake-whitelist-key")
        }
        do {
            _ = try await task.value
            Issue.record("预先取消的任务不能返回建议")
        } catch is CancellationError {
        } catch { Issue.record("取消应保留 CancellationError") }
    }

    @Test(.timeLimit(.minutes(1))) func cancellationDuringLaterRequestDiscardsEarlierSuggestions() async {
        let log = FocusWhitelistRequestLog()
        let started = FocusWhitelistRequestSignal()
        FocusWhitelistStubProtocol.handler = { request in
            let facts = try Self.facts(request)
            if log.record(facts.candidates.count) == 2 {
                Task { await started.signal() }
                return .pending
            }
            return try Self.success(facts.candidates, usage: (100, 20))
        }
        let client = client(), input = candidates(81)
        let task = Task { try await client.recommendWhitelist(goal: "编写程序", candidates: input, apiKey: "fake-whitelist-key") }
        await started.wait()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("取消后不能返回首批已完成的建议")
        } catch is CancellationError {
        } catch { Issue.record("请求期间取消也应保留 CancellationError") }
        #expect(log.batchSizes == [40, 40])
    }
}
