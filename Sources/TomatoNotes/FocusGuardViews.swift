import AppKit
import SwiftUI
import TomatoCore
import TomatoSystem

struct FocusGuardCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var controller: FocusGuardController
    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("专注范围", systemImage: "checkmark.shield").font(.system(size: 14, weight: .semibold))
                if let plan = controller.plan {
                    Text(plan.goal).font(.system(size: 13, weight: .medium))
                    Text(plan.allowAIClosing ? "已开启 AI 关闭无关页面" : "离开勾选内容过久时提醒")
                        .font(.system(size: 11)).foregroundStyle(Theme.green)
                    Text(controller.status).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("调整勾选内容") { state.openGuardSetup(startAfter: false) }.buttonStyle(SubtleButtonStyle())
                } else {
                    if state.isTimerOnlyRound {
                        Text("本轮仅计时").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    if state.timer.stage == .focus && (state.timer.phase == .running || state.timer.phase == .paused) {
                        Button("选择允许的应用和网页") { state.openGuardSetup(startAfter: false) }.buttonStyle(SubtleButtonStyle())
                    } else if state.timer.phase == .idle || (state.timer.phase == .completed && state.timer.nextStage == .focus) {
                        Button("选择应用和网页并开始") { state.openGuardSetup(startAfter: true) }.buttonStyle(SubtleButtonStyle())
                    } else {
                        Text("下一轮开始时可重新勾选。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }
}

struct FocusGuardSetupView: View {
    @ObservedObject var state: AppState
    @ObservedObject var controller: FocusGuardController
    @ObservedObject var recommender: FocusWhitelistRecommender
    @ObservedObject var goalGenerator: FocusGoalGenerator
    var onClose: () -> Void
    private var goal: String {
        get { goalGenerator.goal }
        nonmutating set { goalGenerator.goal = newValue }
    }
    @ViewState private var allowedApps: Set<String> = []
    @ViewState private var pages: [FocusPageRule] = []
    @ViewState private var manualPage = ""
    @ViewState private var manualKind = FocusPageRule.Kind.page
    @ViewState private var allowClosing = false
    @ViewState private var hasCapture = FocusPageCapture.hasPermission
    @ViewState private var validation: String?
    @ViewState private var tabFilter = ""
    @ViewState private var moreExpanded = false

    private var confirmedPlan: FocusGuardPlan {
        let draft = FocusGuardPlan(goal: goal.trimmingCharacters(in: .whitespacesAndNewlines), appIDs: allowedApps,
                                   pages: pages, allowAIClosing: allowClosing)
        return recommender.confirmedPlan(from: draft, provider: controller.aiProvider)
    }
    private var unavailableReason: String? {
        if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "填写这轮要做的事，再开始专注" }
        if goal.count > 300 { return "目标请控制在 300 字内" }
        if goalGenerator.loading { return "AI 正在生成名称…" }
        if recommender.loading { return "AI 正在推荐，也可以勾选清单切回手动" }
        let plan = confirmedPlan
        if plan.appIDs.isEmpty && plan.pages.isEmpty { return "勾选至少一项，或选“仅计时”" }
        if (!plan.pages.isEmpty || allowClosing) && !controller.chromeReady { return "点“读取网页”后再确认选择" }
        if allowClosing && (!hasCapture || !state.hasAPIKey) { return "请在“更多选项”完成 AI 关闭授权" }
        return nil
    }
    private var maySave: Bool { unavailableReason == nil }
    private var selectableApps: [AppIdentity] {
        var apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != "com.google.Chrome" &&
                !($0.bundleIdentifier?.hasPrefix("com.zixuan.TomatoNotes") ?? true)
        }.compactMap { app in app.bundleIdentifier.map { AppIdentity(name: app.localizedName ?? $0, bundleID: $0) } }
        let known = Set(apps.map(\.bundleID))
        for id in confirmedPlan.appIDs.subtracting(known).sorted() {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map {
                FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
            } ?? id
            apps.append(AppIdentity(name: name, bundleID: id))
        }
        var seen: Set<String> = []
        return apps.filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var goalContext: FocusGoalContext {
        let plan = confirmedPlan
        let apps = plan.appIDs.sorted().compactMap { id -> AppIdentity? in
            guard let app = selectableApps.first(where: { $0.bundleID == id }), app.name != id else { return nil }
            return app
        }
        return FocusGoalContext(plan: plan, apps: apps, tabs: controller.availableTabs)
    }
    private var unfinishedTodos: [TodoItem] {
        Array(state.data.todos.filter { $0.effectiveScheduledDay == state.todayKey && !$0.isCompleted }.prefix(12))
    }
    private var favoritePages: [FocusPageRule] { state.settings.focusGuard.favoritePages }
    private var selectionSummary: String {
        let plan = confirmedPlan
        let sites = plan.pages.filter { $0.kind == .site }.count
        let exactPages = plan.pages.count - sites
        return "已勾选 \(plan.appIDs.count) 个应用、\(exactPages) 个网页" + (sites > 0 ? "、\(sites) 个网站" : "")
    }

    var body: some View {
        VStack(spacing: 0) {
            FocusWhitelistPickerHeader { state.guardSetupPresented = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FocusWhitelistGoalCard(
                        goal: Binding(get: { goal }, set: { goal = $0 }),
                        todos: unfinishedTodos,
                        canGenerate: state.hasAPIKey && !goalContext.isEmpty && !recommender.loading,
                        isGenerating: goalGenerator.loading,
                        hasGenerated: goalGenerator.generatedGoal != nil,
                        status: goalGenerator.status,
                        providerName: controller.aiProvider.name,
                        hasKey: state.hasAPIKey,
                        onGenerate: { updateGoalGeneration(force: true) },
                        onCancel: { goalGenerator.cancel() }
                    )
                    appsCard
                    pagesCard
                    DisclosureGroup("更多选项", isExpanded: $moreExpanded) {
                        VStack(alignment: .leading, spacing: 14) {
                            FocusWhitelistRecommendationView(model: recommender, providerName: controller.aiProvider.name,
                                                             hasKey: state.hasAPIKey,
                                                             canRecommend: !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                                                goal.count <= 300 && !controller.loadingTabs,
                                                             onRecommend: { recommender.recommend(goal: goal, controller: controller) })
                            manualCard
                            favoritesCard
                            closingCard
                        }.padding(.top, 12)
                    }.font(.system(size: 12, weight: .medium)).tint(Theme.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }
            footer
        }
        .frame(width: 590, height: min(730, (NSScreen.main?.visibleFrame.height ?? 800) - 70))
        .background(Theme.background).foregroundStyle(Theme.primary).preferredColorScheme(state.settings.appearance.colorScheme)
        .environment(\.glassControlsEnabled, state.settings.glassControlsEnabled)
        .onAppear {
            if let plan = controller.plan {
                goal = plan.goal; allowedApps = plan.appIDs; pages = plan.pages; allowClosing = plan.allowAIClosing
            } else if let draft = state.settings.focusGuard.reusablePlan {
                goal = draft.goal; pages = draft.pages; allowedApps = draft.appIDs; allowClosing = false
            }
            if controller.plan == nil, !state.focusGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                goal = state.focusGoalDraft
            }
            updateGoalGeneration()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in hasCapture = FocusPageCapture.hasPermission }
        .onChange(of: goal) { previous, value in
            if goalGenerator.generatedGoal == value {
                // 起名会使推荐结果过期；保留当前勾选项，仍由底部按钮最终确认。
                let draft = FocusGuardPlan(goal: previous.trimmingCharacters(in: .whitespacesAndNewlines),
                                           appIDs: allowedApps, pages: pages, allowAIClosing: allowClosing)
                let selected = recommender.confirmedPlan(from: draft, provider: controller.aiProvider)
                allowedApps = selected.appIDs
                pages = selected.pages
            }
            if recommender.loading || !recommender.suggestions.isEmpty {
                recommender.cancel(message: "目标已修改，可重新读取并推荐。")
            }
            updateGoalGeneration()
        }
        .onChange(of: goalContext) { _, _ in updateGoalGeneration() }
        .onChange(of: recommender.loading) { _, _ in updateGoalGeneration() }
        .onChange(of: state.hasAPIKey) { _, _ in updateGoalGeneration() }
        .onChange(of: state.settings.ai) { _, _ in
            recommender.cancel(message: "AI 配置已修改，请重新推荐。")
            updateGoalGeneration()
        }
        .onDisappear { recommender.cancel(); goalGenerator.cancel() }
        .onChange(of: state.guardSetupPresented) { _, presented in
            if !presented { recommender.cancel(); goalGenerator.cancel(); onClose() }
        }
        .onExitCommand { state.guardSetupPresented = false }
    }

    private func updateGoalGeneration(force: Bool = false) {
        goalGenerator.update(context: goalContext, provider: controller.aiProvider,
                             hasKey: state.hasAPIKey,
                             ready: state.guardSetupPresented && !recommender.loading &&
                                    (force || recommender.suggestions.isEmpty),
                             force: force)
    }

    private var appsCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("应用").font(.system(size: 13, weight: .semibold))
                FocusWhitelistAppChecklist(apps: selectableApps, selectedIDs: confirmedPlan.appIDs, onSet: setApp)
            }
        }
    }

    private var pagesCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Chrome 网页").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if controller.loadingTabs { ProgressView().controlSize(.small) }
                    Button(controller.availableTabs.isEmpty ? "读取网页" : "刷新") { controller.loadTabs() }
                        .buttonStyle(SubtleButtonStyle()).disabled(controller.loadingTabs)
                        .accessibilityIdentifier("guard.readPages")
                }
                if controller.availableTabs.isEmpty {
                    Text(controller.chromeReady ? "没有可勾选的普通网页" : "点“读取网页”，再勾选这轮需要的页面。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                FocusWhitelistPageChecklist(pages: controller.availableTabs, rules: confirmedPlan.pages, filter: $tabFilter,
                                             onSet: setPage, onSetVisible: setPages, onRemoveRule: removeRule)
                if !controller.chromeReady, !controller.loadingTabs,
                   controller.permissionStatus != "连接 Chrome 后可选择本轮学习页面" {
                    Text(controller.permissionStatus).font(.system(size: 11)).foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !confirmedPlan.pages.isEmpty && !controller.chromeReady {
                    Text("读取网页后即可确认；也可以取消已勾选的网页。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var manualCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("手动添加网址").font(.system(size: 13, weight: .semibold))
                HStack {
                    TextField("页面网址或网站域名", text: $manualPage).textFieldStyle(.roundedBorder)
                    Picker("范围", selection: $manualKind) {
                        Text("仅此页").tag(FocusPageRule.Kind.page)
                        Text("整个网站").tag(FocusPageRule.Kind.site)
                    }.labelsHidden().frame(width: 100)
                    Button("加入") { addManual() }.buttonStyle(SubtleButtonStyle())
                }
                if manualKind == .site {
                    Text("整个网站包括它的子域和后续新开的页面。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if let validation { Text(validation).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                let siteRules = confirmedPlan.pages.filter { $0.kind == .site }
                if !siteRules.isEmpty {
                    Text("已允许的整个网站").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    ForEach(siteRules) { rule in
                        Toggle(rule.value, isOn: Binding(get: { confirmedPlan.pages.contains { $0.id == rule.id } },
                                                         set: { if !$0 { removeRule(rule) } }))
                            .toggleStyle(.checkbox).font(.system(size: 12))
                    }
                }
            }
        }
    }

    private var favoritesCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("常用网页").font(.system(size: 13, weight: .semibold))
                RuleChipsView(pages: favoritePages, emptyHint: "还没有保存的常用网页") { rule in
                    var settings = state.settings
                    settings.focusGuard.favoritePages.removeAll { $0.id == rule.id }
                    _ = state.updateSettings(settings)
                }
                HStack(spacing: 8) {
                    Button("加入清单") {
                        adoptRecommendations()
                        for rule in favoritePages where !pages.contains(where: { $0.id == rule.id }) { pages.append(rule) }
                    }.buttonStyle(SubtleButtonStyle()).disabled(favoritePages.isEmpty)
                    Button("替换网页选择") {
                        adoptRecommendations(); pages = favoritePages
                    }.buttonStyle(SubtleButtonStyle()).disabled(favoritePages.isEmpty)
                    Button("将勾选网页存为常用") {
                        var settings = state.settings
                        for rule in confirmedPlan.pages where !settings.focusGuard.favoritePages.contains(where: { $0.id == rule.id }) {
                            settings.focusGuard.favoritePages.append(rule)
                        }
                        _ = state.updateSettings(settings)
                    }.buttonStyle(SubtleButtonStyle()).disabled(confirmedPlan.pages.isEmpty)
                }
                if !favoritePages.isEmpty {
                    Button("清除常用网页", role: .destructive) {
                        var settings = state.settings
                        settings.focusGuard.favoritePages = []
                        _ = state.updateSettings(settings)
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var closingCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 11) {
                Toggle("AI 确认后关闭无关 Chrome 页面", isOn: $allowClosing)
                    .toggleStyle(.checkbox).font(.system(size: 12, weight: .medium))
                if allowClosing {
                    Text("离开勾选内容 \(state.settings.focusGuard.remindAfterSeconds) 秒后提醒，再停留 \(state.settings.focusGuard.graceSeconds) 秒才请求 AI 判断。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("届时会将普通 Chrome 窗口截图、标题、网站和本轮目标发送给当前 AI 服务商。截图不保存；无痕页面不读取或关闭，判断失败保留页面。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if !state.hasAPIKey { Text("请先在设置中配置当前 AI 服务商的 API Key。").font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    if !controller.chromeReady { Text("请先读取 Chrome 网页。").font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    HStack {
                        Button(hasCapture ? "已允许屏幕读取" : "允许关闭前读取 Chrome 窗口") {
                            hasCapture = FocusPageCapture.requestPermission()
                        }.buttonStyle(SubtleButtonStyle()).disabled(hasCapture)
                        Button("刷新权限") { hasCapture = FocusPageCapture.hasPermission }.buttonStyle(SubtleButtonStyle())
                    }
                    Text("误关时可在 Chrome 按 Command + Shift + T 恢复。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Text("本轮 AI \(controller.checks) / \(state.settings.focusGuard.maxChecks) 次 · 输入 \(controller.inputTokens) / 输出 \(controller.outputTokens) Tokens")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(unavailableReason ?? selectionSummary)
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if allowClosing { Text("AI 关闭已开启").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
            }
            HStack {
                Button("取消") { state.guardSetupPresented = false }.buttonStyle(SubtleButtonStyle())
                Button("仅计时") { state.useTimerOnlyForRound(goal: goal) }.buttonStyle(SubtleButtonStyle())
                    .help("本轮不提醒或检查页面")
                Spacer()
                Button(state.guardSetupActionTitle == "设置并开始专注" ? "开始专注" : "保存选择") {
                    state.saveGuardPlan(confirmedPlan)
                }.buttonStyle(SubtleButtonStyle()).disabled(!maySave)
                    .help("选择仅在本轮生效；暂停时保留，重启后需重新确认")
                    .accessibilityIdentifier("guard.confirmSelection")
            }
        }.padding(20)
    }

    private func adoptRecommendations() {
        let current = confirmedPlan
        allowedApps = current.appIDs
        pages = current.pages
        // 手动调整先接住屏幕上的 AI 勾选结果，再取消旧请求，避免取消的项目又被加入。
        if recommender.loading || !recommender.suggestions.isEmpty {
            recommender.cancel(message: "已保留清单中的选择，可继续勾选调整。")
        }
    }
    private func setApp(_ id: String, _ allowed: Bool) {
        adoptRecommendations()
        if allowed { allowedApps.insert(id) } else { allowedApps.remove(id) }
    }
    private func setPage(_ page: GuardPage, _ allowed: Bool) {
        adoptRecommendations()
        pages = FocusWhitelistSelection.setting(page, allowed: allowed, in: pages, availablePages: controller.availableTabs)
    }
    private func setPages(_ visible: [GuardPage], _ allowed: Bool) {
        adoptRecommendations()
        pages = FocusWhitelistSelection.setting(visible, allowed: allowed, in: pages, availablePages: controller.availableTabs)
    }
    private func removeRule(_ rule: FocusPageRule) {
        adoptRecommendations()
        pages = FocusWhitelistSelection.removing(rule, in: pages, availablePages: controller.availableTabs)
    }
    private func addManual() {
        let rule: FocusPageRule
        if manualKind == .site, let host = FocusPageRule.siteHost(manualPage) {
            rule = .init(kind: .site, value: host, title: host)
        } else if manualKind == .page, let key = FocusPageRule.pageKey(manualPage) {
            rule = .init(kind: .page, value: key, title: URLComponents(string: key)?.host ?? "手动添加的页面")
        } else { validation = "请输入有效的网站域名或完整 http / https 网址。"; return }
        adoptRecommendations()
        if !pages.contains(where: { $0.id == rule.id }) { pages.append(rule) }
        validation = nil; manualPage = ""
    }
}

/// 已选白名单规则的胶囊标签：网站规则在前（绿色）、页面规则在后（陶色），点 × 移除。
struct RuleChipsView: View {
    let pages: [FocusPageRule]
    var emptyHint: String
    var onRemove: (FocusPageRule) -> Void
    var body: some View {
        if pages.isEmpty {
            if !emptyHint.isEmpty {
                Text(emptyHint).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 7, alignment: .leading)],
                      alignment: .leading, spacing: 7) {
                ForEach(pages) { rule in
                    HStack(spacing: 5) {
                        Image(systemName: rule.kind == .site ? "globe" : "doc.text")
                            .font(.system(size: 9)).foregroundStyle(rule.kind == .site ? Theme.green : Theme.accent)
                        Text(rule.kind == .site ? rule.value : rule.title)
                            .lineLimit(1).font(.system(size: 11))
                        Spacer(minLength: 2)
                        Button {
                            onRemove(rule)
                        } label: { Image(systemName: "xmark") .font(.system(size: 8, weight: .semibold)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                            .accessibilityLabel("移除白名单：\(rule.title)")
                    }.padding(.horizontal, 9).padding(.vertical, 5)
                        .background(rule.kind == .site ? Theme.greenSoft : Theme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

@MainActor
final class FocusGuardSetupWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState
    private let recommender = FocusWhitelistRecommender()
    private let goalGenerator = FocusGoalGenerator()
    var onClosed: (() -> Void)?
    init(state: AppState) {
        self.state = state
        let height = min(730, (NSScreen.main?.visibleFrame.height ?? 800) - 70)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "本轮允许的应用和网页"
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.backgroundNS
        window.contentView = makePaperHostingView(rootView: FocusGuardSetupView(state: state, controller: state.guardController,
                                                                             recommender: recommender, goalGenerator: goalGenerator,
                                                                             onClose: { [weak self] in self?.window?.close() }),
                                                  size: NSSize(width: 590, height: height))
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) {
        recommender.cancel()
        goalGenerator.cancel()
        state.guardSetupPresented = false
        onClosed?()
    }
}

@MainActor
final class GuardNoticePresenter {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?
    func show(title: String, message: String, allow: (() -> Void)?, glassEnabled: Bool) {
        panel?.orderOut(nil); dismissal?.cancel()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 164),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = makePaperHostingView(rootView: VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "leaf.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(message).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let allow { Button("本轮放行") { allow(); panel.orderOut(nil) }.buttonStyle(SubtleButtonStyle()) }
                Spacer()
                Button("知道了") { panel.orderOut(nil) }.buttonStyle(SubtleButtonStyle())
            }
        }.padding(18).frame(width: 360, height: 164).background(Theme.surface).foregroundStyle(Theme.primary)
            .environment(\.glassControlsEnabled, glassEnabled), size: NSSize(width: 360, height: 164))
        let available = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrameOrigin(NSPoint(x: available.maxX - 378, y: available.maxY - 184))
        panel.orderFrontRegardless()
        self.panel = panel
        let item = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        dismissal = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }
}
