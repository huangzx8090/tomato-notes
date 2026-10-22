import AppKit
import TomatoCore
import TomatoSystem

@MainActor
final class FocusGuardController: ObservableObject {
    @Published private(set) var plan: FocusGuardPlan?
    @Published private(set) var status = "本轮尚未设置白名单"
    @Published private(set) var checks = 0
    @Published private(set) var inputTokens = 0
    @Published private(set) var outputTokens = 0
    @Published private(set) var assessing = false
    @Published private(set) var chromeReady = false
    @Published private(set) var permissionStatus = "连接 Chrome 后可选择本轮学习页面"
    @Published private(set) var loadingTabs = false
    @Published private(set) var availableTabs: [GuardPage] = []
    private(set) var sessionID: UUID?
    private var usageSessionID: UUID?
    var currentSnapshot: (() -> (TimerSnapshot, Bool, FocusGuardSettings))?
    var onNotice: ((String, String, (() -> Void)?) -> Void)?
    private let browser = ChromeBrowser()
    private let ai = DeepSeekClient()
    private let credentials = DeepSeekCredentials()
    private var monitor = GuardDwellMonitor()
    private var lastPoll: Double = 0
    private var polling: Task<Void, Never>?
    private var assessment: Task<Void, Never>?
    private var generation = UUID()
    private var currentPage: GuardPage?
    private var currentApp: AppIdentity?
    private var ignoredPages: Set<String> = []
    private var decisionStatus: [String: String] = [:]
    private var suspended = false
    private let checkURL: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard Bundle.main.bundleIdentifier == "com.zixuan.TomatoNotes.GuardQA",
              let flag = args.firstIndex(of: "--guard-check-url"), args.indices.contains(flag + 1),
              let url = URL(string: args[flag + 1]), ["127.0.0.1", "localhost"].contains(url.host ?? "") else { return nil }
        return FocusPageRule.pageKey(url.absoluteString)
    }()

    func configure(_ plan: FocusGuardPlan, sessionID: UUID) {
        let sameRound = usageSessionID == sessionID
        stop()
        self.plan = plan
        self.sessionID = sessionID
        usageSessionID = sessionID
        if !sameRound { checks = 0; inputTokens = 0; outputTokens = 0 }
        ignoredPages = []
        decisionStatus = [:]
        suspended = false
        status = "本轮白名单生效，返回白名单后重新计时"
        trace("configured")
    }

    func stop() {
        generation = UUID()
        polling?.cancel(); polling = nil
        assessment?.cancel(); assessment = nil
        assessing = false
        monitor.reset()
        currentPage = nil
    }

    func foregroundDidChange() {
        guard plan != nil else { return }
        stop()
        status = "已切换 App，停留时间重新计算"
    }

    func disableForRound() {
        stop()
        plan = nil
        sessionID = nil
        status = "本轮仅计时，下一轮按全局设置开启守护"
    }

    func loadTabs() {
        guard !loadingTabs else { return }
        loadingTabs = true
        Task {
            defer { loadingTabs = false }
            do {
                try await browser.requestAccess()
                availableTabs = try await browser.currentWindowTabs()
                chromeReady = true
                permissionStatus = "已连接 Chrome；读取当前普通窗口的 \(availableTabs.count) 个标签"
            } catch { permissionStatus = error.localizedDescription; chromeReady = false }
        }
    }

    func tick(timer: TimerSnapshot, locked: Bool, settings: FocusGuardSettings) {
        guard let bound = sessionID, plan != nil else { return }
        if timer.sessionID != bound || timer.stage != .focus || timer.phase == .completed || timer.phase == .idle {
            stop(); sessionID = nil; plan = nil
            status = "本轮结束，白名单已失效"
            return
        }
        guard settings.enabled, timer.phase == .running, !locked else {
            if !suspended { stop(); status = "守护暂停，暂停时间不计入停留时长"; suspended = true }
            return
        }
        suspended = false
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPoll >= 1.5, polling == nil else { return }
        lastPoll = now
        let token = generation
        polling = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.polling = nil } }
            let app = AppState.frontmostApp()
            var page: GuardPage?
            var unavailable: String?
            if app?.bundleID == "com.google.Chrome" {
                do {
                    if !self.chromeReady {
                        // 沿用名单或重启后只恢复已有授权，后台绝不弹出新权限请求。
                        try await self.browser.requestAccess(askUserIfNeeded: false)
                        self.chromeReady = true
                        self.permissionStatus = "Chrome 已连接，可读取当前普通窗口标签"
                    }
                    page = try await self.browser.frontPage()
                }
                catch { unavailable = error.localizedDescription }
            }
            guard !Task.isCancelled, self.generation == token, self.isActive(bound),
                  AppState.frontmostApp()?.bundleID == app?.bundleID, let app, let plan = self.plan else { return }
            if self.assessing {
                // AI 请求期间仍检查页面；中途离开后，即使再切回来也要重新提醒。
                if page?.id != self.currentPage?.id || app.bundleID != self.currentApp?.bundleID {
                    self.stop()
                    self.status = "页面已切换，已取消本次 AI 关闭"
                }
                return
            }
            self.currentApp = app
            self.currentPage = page
            if let checkURL = self.checkURL, page.flatMap({ FocusPageRule.pageKey($0.url) }) != checkURL {
                self.monitor.reset(); self.status = "受控验收中：只处理指定的本地测试页面"; return
            }
            let explicitlyAllowed = plan.allows(appID: app.bundleID, url: page?.url)
            let reviewed = page.map { self.ignoredPages.contains($0.id) } == true
            let allowed = explicitlyAllowed || reviewed
            let identity = allowed ? nil : (page?.id ?? app.bundleID)
            if explicitlyAllowed { self.status = "正在使用本轮白名单内的内容" }
            else if reviewed, let page { self.status = self.decisionStatus[page.id] ?? "本页已检查，本轮不再重复请求 AI" }
            else if let unavailable { self.status = unavailable }
            else if plan.allowAIClosing && self.checks >= max(1, min(5, settings.maxChecks)) {
                self.status = "本轮已达到 AI 判断上限，之后仅提醒"
            }
            else { self.status = "当前不在白名单内，停留超时后提醒" }
            let mayAssess = plan.allowAIClosing && page?.mayAssess == true &&
                self.checks < max(1, min(5, settings.maxChecks))
            let action = self.monitor.update(identity: identity, at: ProcessInfo.processInfo.systemUptime,
                                             settings: settings, mayAssess: mayAssess)
            if action == .remind {
                self.trace("reminded")
                self.status = mayAssess ? "已提醒，\(settings.graceSeconds) 秒后仍未返回将交由 AI 核对" : "已提醒，本轮对当前内容仅提醒"
                var allowAction: (() -> Void)?
                if app.bundleID != "com.google.Chrome" || page.flatMap({ FocusPageRule.pageKey($0.url) }) != nil {
                    allowAction = { [weak self] in self?.allow(app: app, page: page, round: bound) }
                }
                self.onNotice?("回到这一轮的学习吧", "目标：\(plan.goal)\n当前停留：\(page?.host ?? app.name)", allowAction)
            } else if action == .assess, let page { self.assess(page, round: bound, plan: plan) }
        }
    }

    private func allow(app: AppIdentity, page: GuardPage?, round: UUID) {
        guard var plan, sessionID == round, let (timer, _, _) = currentSnapshot?(),
              timer.sessionID == round, timer.stage == .focus,
              timer.phase == .running || timer.phase == .paused else { return }
        if app.bundleID == "com.google.Chrome" {
            // 只放行提示所指的页面，不能把点击按钮时碰巧停留的新页面加入名单。
            guard let page, let key = FocusPageRule.pageKey(page.url) else { return }
            plan.pages.append(.init(kind: .page, value: key, title: page.title))
        } else { plan.appIDs.insert(app.bundleID) }
        self.plan = plan
        stop()
        status = "已放行，只在本轮专注中有效"
    }

    private func isActive(_ round: UUID) -> Bool {
        guard let (timer, locked, settings) = currentSnapshot?() else { return false }
        return sessionID == round && settings.enabled && timer.sessionID == round && timer.stage == .focus && timer.phase == .running && !locked
    }

    private func assess(_ page: GuardPage, round: UUID, plan: FocusGuardPlan) {
        guard !assessing, let (_, _, settings) = currentSnapshot?(), checks < max(1, min(5, settings.maxChecks)) else { return }
        assessing = true
        status = "关闭前由 AI 核对当前 Chrome 页面…"
        let token = generation
        assessment = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.assessing = false; self.assessment = nil } }
            do {
                guard let key = try self.credentials.read() else { throw DeepSeekError.missingKey }
                let image = try await FocusPageCapture.image(for: page)
                guard try await self.browser.frontPage() == page, self.isActive(round), !Task.isCancelled,
                      self.generation == token else { return }
                self.checks += 1
                self.trace("requesting")
                let result = try await self.ai.assessFocus(goal: plan.goal, page: page, image: image, apiKey: key)
                guard self.isActive(round), !Task.isCancelled, self.generation == token else { return }
                self.inputTokens += max(0, result.inputTokens)
                self.outputTokens += max(0, result.outputTokens)
                self.ignoredPages.insert(page.id)
                self.trace("decision-" + result.relevance.verdict.rawValue)
                if result.relevance.permitsClosing {
                    guard self.plan?.allows(appID: "com.google.Chrome", url: page.url) == false,
                          self.plan?.allowAIClosing == true else { return }
                    _ = try await self.browser.closeIfUnchanged(page)
                    self.trace("closed")
                    self.status = "已关闭无关标签：\(result.relevance.reason)"
                    self.onNotice?("已收起无关页面", result.relevance.reason, nil)
                } else {
                    self.status = "本轮保留此页：\(result.relevance.reason)"
                    self.decisionStatus[page.id] = self.status
                    self.onNotice?(result.relevance.verdict == .related ? "这个页面可以继续学习" : "AI 无法确认，已保留页面", result.relevance.reason, nil)
                }
            } catch {
                guard self.isActive(round), !Task.isCancelled, self.generation == token else { return }
                self.ignoredPages.insert(page.id)
                self.trace("failed")
                self.status = error.localizedDescription
                self.decisionStatus[page.id] = "本次检查未完成，已保留页面：" + error.localizedDescription
                self.onNotice?("本次检查未能完成", error.localizedDescription, nil)
            }
        }
    }

    private func trace(_ stage: String) {
        guard checkURL != nil else { return }
        let line = "guard-check \(stage) checks=\(checks) input=\(inputTokens) output=\(outputTokens)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
