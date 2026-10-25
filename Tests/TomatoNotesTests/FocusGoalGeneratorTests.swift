import Foundation
import Testing
import TomatoCore
import TomatoSystem
@testable import TomatoNotes

@MainActor
private final class FocusGoalGate {
    private var continuation: CheckedContinuation<FocusGoalSuggestion, Never>?
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func receive() async -> FocusGoalSuggestion {
        await withCheckedContinuation {
            continuation = $0
            started = true
            waiters.forEach { $0.resume() }; waiters.removeAll()
        }
    }
    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { waiters.append($0) } }
    }
    func finish(_ title: String) { continuation?.resume(returning: .init(title: title)); continuation = nil }
}

@Suite(.timeLimit(.minutes(1)))
struct FocusGoalGeneratorTests {
    private let provider = AIProviderCatalog.deepseek
    private func context(_ title: String = "导数练习") -> FocusGoalContext {
        .init(plan: .init(goal: "", appIDs: [], pages: [
            .init(kind: .page, value: "https://course.example/lesson", title: title)
        ], allowAIClosing: false), apps: [])
    }

    @Test @MainActor func fillsEmptyGoalAndUpdatesGeneratedGoalWhenWhitelistChanges() async throws {
        var requests = 0
        let model = FocusGoalGenerator(debounceNanoseconds: 0, keyReader: { _ in "fake-key" }, suggest: { provider, context, key in
            #expect(provider == self.provider && key == "fake-key")
            requests += 1
            return .init(title: context.entries.first!.name)
        })
        let first = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await first.value
        #expect(model.goal == "导数练习" && !model.loading)
        #expect(model.update(context: context(), provider: provider, hasKey: true) == nil)
        let second = try #require(model.update(context: context("数据库复习"), provider: provider, hasKey: true))
        await second.value
        #expect(model.goal == "数据库复习" && requests == 2)
    }

    @Test @MainActor func manualEditsWinOverLateResultsAndAutomaticUpdates() async throws {
        let gate = FocusGoalGate()
        let model = FocusGoalGenerator(debounceNanoseconds: 0, keyReader: { _ in "fake-key" }, suggest: { _, _, _ in await gate.receive() })
        let request = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await gate.waitUntilStarted()
        model.goal = "我手写的学习计划"
        gate.finish("晚到的旧名称")
        await request.value
        #expect(model.goal == "我手写的学习计划" && !model.loading && model.status.isEmpty)
        #expect(model.update(context: context("新白名单"), provider: provider, hasKey: true) == nil)
    }

    @Test(arguments: ["whitelist", "provider", "model", "close", "removeKey"])
    @MainActor func changesDiscardOldResults(change: String) async throws {
        let oldGate = FocusGoalGate(), newGate = FocusGoalGate()
        var requests = 0
        let model = FocusGoalGenerator(debounceNanoseconds: 0, keyReader: { _ in "fake-key" }, suggest: { _, _, _ in
            requests += 1
            return await (requests == 1 ? oldGate : newGate).receive()
        })
        let old = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await oldGate.waitUntilStarted()
        var nextProvider = provider
        if change == "provider" { nextProvider.id = "changed"; nextProvider.baseURL = "https://changed.example/v1" }
        if change == "model" { nextProvider.defaultModel = "changed-model" }
        let newer: Task<Void, Never>?
        if change == "close" { model.cancel(); newer = nil }
        else { newer = model.update(context: context(change == "whitelist" ? "数据库复习" : "导数练习"), provider: nextProvider, hasKey: change != "removeKey") }
        if newer != nil { await newGate.waitUntilStarted() }
        oldGate.finish("旧名称")
        await old.value
        #expect(model.goal.isEmpty)
        if let newer {
            #expect(model.loading)
            newGate.finish("新名称")
            await newer.value
            #expect(model.goal == "新名称" && !model.loading)
        } else { #expect(!model.loading) }
    }

    @Test @MainActor func failureAllowsManualEntryAndExplicitRetryWithoutLooping() async throws {
        var requests = 0
        let model = FocusGoalGenerator(debounceNanoseconds: 0, keyReader: { _ in "fake-key" }, suggest: { _, _, _ in
            requests += 1
            if requests == 1 { throw FocusGoalError.invalidResponse }
            return .init(title: "高数练习")
        })
        let failed = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await failed.value
        #expect(model.goal.isEmpty && !model.loading && !model.status.isEmpty)
        #expect(model.update(context: context(), provider: provider, hasKey: true) == nil && requests == 1)
        model.goal = "手动目标"
        #expect(model.update(context: context(), provider: provider, hasKey: true) == nil)
        let retry = try #require(model.update(context: context(), provider: provider, hasKey: true, force: true))
        await retry.value
        #expect(model.goal == "高数练习" && requests == 2)
    }

    @Test @MainActor func rapidSelectionChangesAreDebouncedAndUnavailableInputsDoNotRequest() async throws {
        var requests = 0
        let model = FocusGoalGenerator(debounceNanoseconds: 60_000_000_000, keyReader: { _ in "fake-key" }, suggest: { _, _, _ in
            requests += 1; return .init(title: "不应生成")
        })
        #expect(model.update(context: context(), provider: provider, hasKey: false) == nil)
        #expect(model.update(context: context(), provider: provider, hasKey: true, ready: false) == nil)
        let first = try #require(model.update(context: context(), provider: provider, hasKey: true))
        let second = try #require(model.update(context: context("数据库"), provider: provider, hasKey: true))
        model.cancel()
        await first.value; await second.value
        #expect(requests == 0 && model.goal.isEmpty && !model.loading)
    }

    @Test @MainActor func pendingWhitelistRecommendationSuspendsNamingUntilReady() async throws {
        let gate = FocusGoalGate()
        var requests = 0
        let model = FocusGoalGenerator(debounceNanoseconds: 0, keyReader: { _ in "fake-key" }, suggest: { _, _, _ in
            requests += 1
            if requests == 1 { return await gate.receive() }
            return .init(title: "重新起名")
        })
        let old = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await gate.waitUntilStarted()
        #expect(model.update(context: context(), provider: provider, hasKey: true, ready: false) == nil)
        gate.finish("不能覆盖待确认推荐的旧名称")
        await old.value
        #expect(model.goal.isEmpty && !model.loading && requests == 1)
        let resumed = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await resumed.value
        #expect(model.goal == "重新起名" && requests == 2)
    }

    @Test @MainActor func confirmedGeneratedNameIsSavedWithTheFocusSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FocusGoalTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data.json"))
        var fixture = AppData()
        fixture.settings.notificationsEnabled = false
        try repository.save(fixture)
        let state = AppState(repository: repository, keyReader: { _ in nil })
        state.deviceLocked = false
        let model = FocusGoalGenerator(debounceNanoseconds: 0, keyReader: { _ in "fake-key" }, suggest: { _, _, _ in .init(title: "高数 · 导数练习") })
        let request = try #require(model.update(context: context(), provider: provider, hasKey: true))
        await request.value
        #expect(state.data.sessions.isEmpty && state.guardController.plan == nil)
        state.openGuardSetup(startAfter: true)
        state.saveGuardPlan(.init(goal: model.goal, appIDs: ["local.editor"], pages: [], allowAIClosing: false))
        #expect(state.timer.phase == .running && state.data.sessions.last?.goal == model.goal)
        #expect(state.guardController.plan?.goal == model.goal)
        #expect(try repository.load().sessions.last?.goal == model.goal)
        state.prepareForQuit()
    }
}
