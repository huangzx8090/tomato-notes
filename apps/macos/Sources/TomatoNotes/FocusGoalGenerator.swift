import Foundation
import Combine
import TomatoCore
import TomatoSystem

@MainActor
final class FocusGoalGenerator: ObservableObject {
    @Published var goal = "" {
        didSet {
            guard goal != oldValue, !applyingSuggestion else { return }
            generatedGoal = nil
            lastAttempt = nil
            cancel()
        }
    }
    @Published private(set) var loading = false
    @Published private(set) var status = ""
    private(set) var generatedGoal: String?
    private var applyingSuggestion = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var currentInput: Input?
    private var lastAttempt: Input?
    private let debounceNanoseconds: UInt64
    private let keyReader: @MainActor (String) throws -> String?
    private let suggest: @MainActor (AIProviderConfig, FocusGoalContext, String) async throws -> FocusGoalSuggestion

    private struct Input: Equatable {
        let context: FocusGoalContext
        let provider: AIProviderConfig
        let available: Bool
    }

    init(debounceNanoseconds: UInt64 = 700_000_000,
         keyReader: @escaping @MainActor (String) throws -> String? = { try AIProviderCredentials().read(providerID: $0) },
         suggest: @escaping @MainActor (AIProviderConfig, FocusGoalContext, String) async throws -> FocusGoalSuggestion = {
             try await AIReviewClient(provider: $0).suggestFocusGoal(context: $1, apiKey: $2)
         }) {
        self.debounceNanoseconds = debounceNanoseconds
        self.keyReader = keyReader
        self.suggest = suggest
    }

    @discardableResult
    func update(context: FocusGoalContext, provider: AIProviderConfig, hasKey: Bool,
                ready: Bool = true, force: Bool = false) -> Task<Void, Never>? {
        let input = Input(context: context, provider: provider, available: hasKey && ready)
        if currentInput != input { cancel(); currentInput = input; lastAttempt = nil }
        guard input.available, !context.isEmpty else { return nil }
        // 手写目标始终优先；只有用户主动点生成，才允许替换手写内容。
        guard force || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal == generatedGoal else { return nil }
        guard force || lastAttempt != input else { return task }
        cancel()
        lastAttempt = input
        let token = generation, originalGoal = goal
        loading = true
        status = "正在根据本轮白名单生成名称…"
        let request = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token { self.loading = false; self.task = nil }
            }
            do {
                if !force { try await Task.sleep(nanoseconds: self.debounceNanoseconds) }
                try Task.checkCancellation()
                guard let key = try self.keyReader(provider.id) else { throw AIReviewError.missingKey }
                let result = try await self.suggest(provider, context, key)
                try Task.checkCancellation()
                guard self.generation == token, self.currentInput == input, self.goal == originalGoal else { return }
                self.generatedGoal = result.title
                self.applyingSuggestion = true
                self.goal = result.title
                self.applyingSuggestion = false
                self.status = "已根据白名单生成，可直接修改。"
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                // 不展示底层网络或钥匙串错误附带的地址、密钥等内容。
                self.status = (error as? AIReviewError)?.localizedDescription ?? FocusGoalError.invalidResponse.localizedDescription
            }
        }
        task = request
        return request
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        loading = false
        status = ""
    }
}
