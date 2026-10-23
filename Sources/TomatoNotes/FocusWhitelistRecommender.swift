import AppKit
import TomatoCore
import TomatoSystem

@MainActor
final class FocusWhitelistRecommender: ObservableObject {
    @Published private(set) var snapshot: FocusWhitelistSnapshot?
    @Published private(set) var suggestions: [FocusWhitelistSuggestion] = []
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    @Published private(set) var inputTokens = 0
    @Published private(set) var outputTokens = 0
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var requestedGoal = ""
    private var requestedProvider: AIProviderConfig?

    func recommend(goal: String, controller: FocusGuardController) {
        cancel()
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, goal.count <= 300 else { return }
        requestedGoal = goal
        let provider = controller.aiProvider
        requestedProvider = provider
        let token = generation
        loading = true
        status = "正在读取当前运行的 App 与 Chrome 网页…"
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token { self.loading = false; self.task = nil }
            }
            do {
                guard let key = try AIProviderCredentials().read(providerID: provider.id) else { throw AIReviewError.missingKey }
                let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                    .compactMap { app in app.bundleIdentifier.map { AppIdentity(name: app.localizedName ?? $0, bundleID: $0) } }
                var tabs: [GuardPage] = []
                if apps.contains(where: { $0.bundleID == "com.google.Chrome" }) {
                    // Chrome 读取失败时终止，避免把遗漏网页的结果显示成完整推荐。
                    tabs = try await controller.readTabsForRecommendation()
                }
                try Task.checkCancellation()
                let snapshot = FocusWhitelistSnapshot(apps: apps, pages: tabs)
                guard !snapshot.items.isEmpty else {
                    self.status = "没有可推荐的 App 或普通网页；可在下方手动添加。"
                    return
                }
                guard self.generation == token, controller.aiProvider == provider else { return }
                self.status = "已读取 \(snapshot.appCount) 个 App、\(snapshot.pageCount) 个不同网页，AI 正在逐项推荐…"
                let result = try await AIReviewClient(provider: provider).recommendWhitelist(goal: goal, candidates: snapshot.candidates, apiKey: key)
                try Task.checkCancellation()
                guard self.generation == token, controller.aiProvider == provider else { return }
                self.snapshot = snapshot
                self.suggestions = result.suggestions
                self.selectedIDs = Set(result.suggestions.filter { $0.disposition == .recommended }.map(\.id))
                self.inputTokens = result.inputTokens
                self.outputTokens = result.outputTokens
                self.status = "已为 \(snapshot.appCount) 个 App、\(snapshot.pageCount) 个不同网页给出建议"
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.status = "本次推荐未完成，仍可手动选择白名单。"
            }
        }
    }

    func cancel(message: String = "") {
        generation = UUID()
        task?.cancel()
        task = nil
        loading = false
        snapshot = nil
        suggestions = []
        selectedIDs = []
        error = nil
        status = message
        inputTokens = 0
        outputTokens = 0
        requestedProvider = nil
    }

    func confirmedPlan(from draft: FocusGuardPlan, provider: AIProviderConfig) -> FocusGuardPlan {
        guard !loading, requestedGoal == draft.goal, requestedProvider == provider,
              !suggestions.isEmpty, let snapshot else { return draft }
        return snapshot.adding(selectedIDs, to: draft)
    }
}
