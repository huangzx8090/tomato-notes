import Foundation
import Testing
import TomatoCore
import TomatoSystem
@testable import TomatoNotes

// 故意不响应取消，以验证晚到的截图、成功或失败结果仍会被控制器丢弃。
@MainActor
private final class ProviderResultGate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func receive() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume(_ value: Value) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: value)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct FocusGuardProviderTests {
    private func provider(_ id: String) -> AIProviderConfig {
        .init(id: id, name: id, baseURL: "https://\(id).example/v1", defaultModel: "vision-test", sendsThinkingFlag: false)
    }

    private var page: GuardPage {
        .init(windowID: "fake-window", tabID: "fake-tab", url: "https://page.example/lesson", title: "模拟页面",
              isPrivate: false, bounds: .init(x: 0, y: 0, width: 1000, height: 700))
    }

    private var result: FocusAssessment {
        .init(relevance: .init(verdict: .unrelated, confidence: 0.99, reason: "模拟无关页面"), inputTokens: 12, outputTokens: 3)
    }

    @MainActor private func activate(_ controller: FocusGuardController) -> (UUID, FocusGuardPlan) {
        let round = UUID()
        var timer = TimerSnapshot()
        timer.phase = .running
        timer.sessionID = round
        var settings = FocusGuardSettings()
        settings.enabled = true
        let plan = FocusGuardPlan(goal: "学习数据库", appIDs: [], pages: [], allowAIClosing: true)
        controller.currentSnapshot = { (timer, false, settings) }
        controller.configure(plan, sessionID: round)
        return (round, plan)
    }

    @Test @MainActor func unchangedConfigurationKeepsClientKeyAndClosingBehavior() async throws {
        let selected = provider("first"), page = page, result = result
        let capture = ProviderResultGate<Data>()
        var keyProviders: [String] = []
        var requests = 0, closed = 0
        let controller = FocusGuardController(
            keyReader: { keyProviders.append($0); return "fake-key-\($0)" },
            capturePage: { _ in await capture.receive() },
            frontPage: { page },
            assessPage: { client, goal, current, image, key in
                #expect(client.provider == selected)
                #expect(client.provider.baseURL == "https://first.example/v1")
                #expect(key == "fake-key-first")
                #expect(goal == "学习数据库" && current == page && image == Data([1]))
                requests += 1
                return result
            },
            closePage: { current in #expect(current == page); closed += 1; return true })
        controller.updateAIProvider(selected)
        let (round, plan) = activate(controller)
        let task = try #require(controller.assess(page, round: round, plan: plan))
        await capture.waitUntilStarted()
        controller.updateAIProvider(selected)
        #expect(!task.isCancelled && controller.assessing)
        capture.resume(Data([1]))
        await task.value
        #expect(keyProviders == [selected.id] && requests == 1 && closed == 1)
        #expect(controller.checks == 1 && controller.inputTokens == 12 && controller.outputTokens == 3)
        #expect(!controller.assessing)
    }

    @Test @MainActor func changeDuringCaptureCancelsOldRequestWithoutClearingANewerAssessment() async throws {
        let first = provider("first"), second = provider("second"), page = page, result = result
        let oldCapture = ProviderResultGate<Data>(), newCapture = ProviderResultGate<Data>()
        var keyProviders: [String] = [], requestProviders: [AIProviderConfig] = []
        var captures = 0, pageReads = 0, closed = 0
        let controller = FocusGuardController(
            keyReader: { keyProviders.append($0); return "fake-key-\($0)" },
            capturePage: { _ in
                captures += 1
                return await (captures == 1 ? oldCapture : newCapture).receive()
            },
            frontPage: { pageReads += 1; return page },
            assessPage: { client, _, _, _, key in
                #expect(key == "fake-key-\(client.provider.id)")
                requestProviders.append(client.provider)
                return result
            },
            closePage: { _ in closed += 1; return true })
        controller.updateAIProvider(first)
        let (round, plan) = activate(controller)
        let old = try #require(controller.assess(page, round: round, plan: plan))
        await oldCapture.waitUntilStarted()
        controller.updateAIProvider(second)
        #expect(old.isCancelled && !controller.assessing)
        let fresh = try #require(controller.assess(page, round: round, plan: plan))
        await newCapture.waitUntilStarted()
        oldCapture.resume(Data([1]))
        await old.value
        #expect(controller.assessing && !fresh.isCancelled)
        #expect(requestProviders.isEmpty && pageReads == 0 && controller.checks == 0)
        newCapture.resume(Data([2]))
        await fresh.value
        #expect(keyProviders == [first.id, second.id])
        #expect(requestProviders == [second] && pageReads == 1 && closed == 1)
        #expect(controller.checks == 1 && controller.inputTokens == 12 && !controller.assessing)
    }

    @Test(arguments: ["endpoint", "model"])
    @MainActor func changeDuringPageReadInvalidatesTheRequestEvenForTheSameProviderID(field: String) async throws {
        let selected = provider("first"), page = page, result = result
        let front = ProviderResultGate<GuardPage>()
        var requests = 0, closed = 0
        let controller = FocusGuardController(
            keyReader: { _ in "fake-key-first" },
            capturePage: { _ in Data([1]) },
            frontPage: { await front.receive() },
            assessPage: { _, _, _, _, _ in requests += 1; return result },
            closePage: { _ in closed += 1; return true })
        controller.updateAIProvider(selected)
        let (round, plan) = activate(controller)
        let task = try #require(controller.assess(page, round: round, plan: plan))
        await front.waitUntilStarted()
        var changed = selected
        if field == "endpoint" { changed.baseURL = "https://changed.example/v1" }
        else { changed.defaultModel = "another-vision-model" }
        controller.updateAIProvider(changed)
        #expect(task.isCancelled && !controller.assessing)
        front.resume(page)
        await task.value
        #expect(requests == 0 && closed == 0 && controller.checks == 0)
        #expect(controller.inputTokens == 0 && controller.outputTokens == 0)
    }

    @Test @MainActor func aLateSuccessCannotCloseAfterSwitchingAwayAndBackToTheSameProvider() async throws {
        let first = provider("first"), second = provider("second"), page = page, result = result
        let response = ProviderResultGate<FocusAssessment>()
        var requests: [AIProviderConfig] = []
        var closed = 0, notices = 0
        let controller = FocusGuardController(
            keyReader: { "fake-key-\($0)" },
            capturePage: { _ in Data([1]) },
            frontPage: { page },
            assessPage: { client, _, _, _, key in
                #expect(client.provider == first && key == "fake-key-first")
                requests.append(client.provider)
                let result = await response.receive()
                #expect(Task.isCancelled)
                return result
            },
            closePage: { _ in closed += 1; return true })
        controller.onNotice = { _, _, _ in notices += 1 }
        controller.updateAIProvider(first)
        let (round, plan) = activate(controller)
        let task = try #require(controller.assess(page, round: round, plan: plan))
        await response.waitUntilStarted()
        controller.updateAIProvider(second)
        controller.updateAIProvider(first)
        let status = controller.status
        #expect(task.isCancelled && !controller.assessing)
        response.resume(result)
        await task.value
        #expect(requests == [first] && closed == 0 && notices == 0)
        #expect(controller.checks == 1 && controller.inputTokens == 0 && controller.outputTokens == 0)
        #expect(controller.status == status && !controller.assessing)
    }

    @Test(arguments: [false, true])
    @MainActor func failuresOnlyPublishForTheCurrentConfiguration(changeProvider: Bool) async throws {
        let first = provider("first"), second = provider("second"), page = page
        let response = ProviderResultGate<Result<FocusAssessment, AIReviewError>>()
        var closed = 0, notices = 0
        let controller = FocusGuardController(
            keyReader: { _ in "fake-key-first" },
            capturePage: { _ in Data([1]) },
            frontPage: { page },
            assessPage: { _, _, _, _, _ in try await response.receive().get() },
            closePage: { _ in closed += 1; return true })
        controller.onNotice = { _, _, _ in notices += 1 }
        controller.updateAIProvider(first)
        let (round, plan) = activate(controller)
        let task = try #require(controller.assess(page, round: round, plan: plan))
        await response.waitUntilStarted()
        if changeProvider { controller.updateAIProvider(second) }
        let status = controller.status
        response.resume(.failure(.http(429)))
        await task.value
        #expect(closed == 0 && controller.checks == 1 && !controller.assessing)
        #expect(controller.inputTokens == 0 && controller.outputTokens == 0)
        #expect(notices == (changeProvider ? 0 : 1))
        if changeProvider { #expect(controller.status == status && task.isCancelled) }
        else { #expect(controller.status == AIReviewError.http(429).localizedDescription && !task.isCancelled) }
    }

    @Test @MainActor func changeBeforeTheTaskStartsDoesNotReadKeysOrCapturePages() async throws {
        let page = page, result = result
        var keyReads = 0, captures = 0, requests = 0, closed = 0
        let controller = FocusGuardController(
            keyReader: { _ in keyReads += 1; return "fake-key" },
            capturePage: { _ in captures += 1; return Data([1]) },
            frontPage: { page },
            assessPage: { _, _, _, _, _ in requests += 1; return result },
            closePage: { _ in closed += 1; return true })
        controller.updateAIProvider(provider("first"))
        let (round, plan) = activate(controller)
        let task = try #require(controller.assess(page, round: round, plan: plan))
        controller.updateAIProvider(provider("second"))
        await task.value
        #expect(task.isCancelled && !controller.assessing)
        #expect(keyReads == 0 && captures == 0 && requests == 0 && closed == 0)
    }
}
