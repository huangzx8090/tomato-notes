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
                Label("专注守护", systemImage: "leaf.circle").font(.system(size: 14, weight: .semibold))
                if let plan = controller.plan {
                    Text(plan.goal).font(.system(size: 13, weight: .medium))
                    Text(plan.allowAIClosing ? "本轮允许 AI 核对后关闭无关标签" : "本轮仅提醒 · AI 关闭未开启")
                        .font(.system(size: 11)).foregroundStyle(Theme.green)
                    Text(controller.status).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("本轮 AI \(controller.checks) / \(state.settings.focusGuard.maxChecks) 次 · 输入 \(controller.inputTokens) / 输出 \(controller.outputTokens) Tokens")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Button("查看或调整本轮白名单") { state.openGuardSetup(startAfter: false) }.buttonStyle(SubtleButtonStyle())
                } else {
                    Text(state.isTimerOnlyRound ? "这轮安心计时，不检查页面；下一轮仍按原设置开始。" : "选好这轮要做的事，离开白名单太久时，轻轻提醒你回来。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if state.timer.stage == .focus && (state.timer.phase == .running || state.timer.phase == .paused) {
                        Button("设置本轮白名单") { state.openGuardSetup(startAfter: false) }.buttonStyle(SubtleButtonStyle())
                    } else if state.timer.phase == .idle || (state.timer.phase == .completed && state.timer.nextStage == .focus) {
                        Button("设置并开始专注") { state.openGuardSetup(startAfter: true) }.buttonStyle(SubtleButtonStyle())
                    } else {
                        Text("下一轮专注开始时，可选择本轮白名单。 ").font(.system(size: 11)).foregroundStyle(Theme.secondary)
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
    var onClose: () -> Void
    @ViewState private var goal = ""
    @ViewState private var allowedApps: Set<String> = []
    @ViewState private var pages: [FocusPageRule] = []
    @ViewState private var manualPage = ""
    @ViewState private var manualKind = FocusPageRule.Kind.page
    @ViewState private var allowClosing = false
    @ViewState private var hasCapture = FocusPageCapture.hasPermission
    @ViewState private var validation: String?
    @ViewState private var tabFilter = ""
    @ViewState private var expandedHosts: Set<String> = []
    @FocusState private var goalFocused: Bool

    private var runningApps: [AppIdentity] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular &&
            $0.bundleIdentifier != "com.google.Chrome" && !($0.bundleIdentifier?.hasPrefix("com.zixuan.TomatoNotes") ?? true) }
            .compactMap { app in app.bundleIdentifier.map { AppIdentity(name: app.localizedName ?? $0, bundleID: $0) } }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    private var maySave: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && goal.count <= 300 &&
            !recommender.loading && (confirmedPlan.pages.isEmpty || controller.chromeReady) &&
            (!allowClosing || (hasCapture && controller.chromeReady && state.hasAPIKey))
    }
    private var confirmedPlan: FocusGuardPlan {
        let draft = FocusGuardPlan(goal: goal.trimmingCharacters(in: .whitespacesAndNewlines), appIDs: allowedApps,
                                   pages: pages, allowAIClosing: allowClosing)
        return recommender.confirmedPlan(from: draft, provider: controller.aiProvider)
    }
    private var unfinishedTodos: [TodoItem] {
        Array(state.data.todos.filter { $0.effectiveScheduledDay == state.todayKey && !$0.isCompleted }.prefix(12))
    }
    private var visibleTabs: [GuardPage] {
        controller.availableTabs.filter {
            FocusPageRule.pageKey($0.url) != nil &&
            (tabFilter.isEmpty || ($0.title + " " + $0.host).localizedCaseInsensitiveContains(tabFilter))
        }
    }
    private var tabGroups: [TabGroup] {
        let hosts = Dictionary(grouping: visibleTabs) { $0.host }
        return hosts
            .map { TabGroup(host: $0.key, tabs: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.host.localizedCompare($1.host) == .orderedAscending }
    }
    /// 已选规则的胶囊展示顺序：网站在前，页面按加入顺序在后。
    private var selectedChips: [FocusPageRule] {
        pages.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .site }
            return pages.firstIndex(of: lhs) ?? 0 < pages.firstIndex(of: rhs) ?? 0
        }
    }
    private var favoritePages: [FocusPageRule] { state.settings.focusGuard.favoritePages }

    struct TabGroup: Identifiable {
        let host: String
        let tabs: [GuardPage]
        var id: String { host }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("给这一轮，留一片专注空间").font(.system(size: 20, weight: .semibold))
                    Text("白名单只在本轮有效，暂停时保留；应用重启后需重新设置。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { state.guardSetupPresented = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("取消设置本轮白名单")
            }.padding(22)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这轮学习什么").font(.system(size: 13, weight: .semibold))
                            TextField("例如：高数第三章练习，或完成 Swift 作业", text: $goal)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("本轮学习目标")
                                .focused($goalFocused)
                            if goal.count > 300 {
                                Text("目标请控制在 300 字内，让这轮要做的事更明确。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
                            }
                            if !unfinishedTodos.isEmpty {
                                Menu {
                                    ForEach(unfinishedTodos) { todo in Button(todo.text) { goal = todo.text } }
                                } label: { Label("从今天未完成的待办选一个", systemImage: "checklist") }
                                .font(.system(size: 11))
                            }
                            Text("写好目标后，可让 AI 读取当前 App 与网页，帮你选好本轮白名单。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                    FocusWhitelistRecommendationView(model: recommender, providerName: controller.aiProvider.name,
                                                     hasKey: state.hasAPIKey,
                                                     canRecommend: !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                                        goal.count <= 300 && !controller.loadingTabs,
                                                     onRecommend: { recommender.recommend(goal: goal, controller: controller) })
                    PaperCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("本轮允许的 Chrome 页面").font(.system(size: 13, weight: .semibold))
                            if !pages.isEmpty {
                                RuleChipsView(pages: selectedChips,
                                              emptyHint: "") { rule in pages.removeAll { $0.id == rule.id } }
                            }
                            if !controller.availableTabs.isEmpty {
                                HStack(spacing: 8) {
                                    TextField("筛选标题或网站", text: $tabFilter).textFieldStyle(.roundedBorder)
                                        .accessibilityLabel("筛选 Chrome 标签")
                                    Menu {
                                        ForEach(tabGroups) { group in
                                            Button("\(group.host)（\(group.tabs.count) 个标签）") { addSite(group.host) }
                                        }
                                        Divider()
                                        Button("按页面逐个加入全部") { visibleTabs.forEach(addPage) }
                                    } label: { Label("全部放行", systemImage: "checkmark.circle") }
                                        .font(.system(size: 11))
                                        .accessibilityLabel("将筛选出的标签全部加入白名单")
                                }
                            }
                            if controller.availableTabs.isEmpty {
                                Button(controller.loadingTabs ? "正在连接…" : "连接 Chrome / 读取所有普通窗口标签") { controller.loadTabs() }
                                    .buttonStyle(SubtleButtonStyle()).disabled(controller.loadingTabs)
                            }
                            Text(controller.permissionStatus).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            if controller.availableTabs.isEmpty && !controller.loadingTabs {
                                Text("连接后，这里的标签会按网站分组；点组头放行整个网站，展开后也可只勾选其中几页。")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            ForEach(tabGroups) { group in
                                TabGroupRow(group: group,
                                            expanded: expandedHosts.contains(group.host),
                                            siteAdded: isSiteAdded(group.host),
                                            selectedCount: group.tabs.filter { isPageAdded($0) }.count,
                                            onToggleExpand: { toggleExpanded(group.host) },
                                            onAddSite: { addSite(group.host) },
                                            onRemoveSite: { pages.removeAll { $0.kind == .site && $0.value == group.host } },
                                            isPageAdded: isPageAdded,
                                            addPage: addPage)
                            }
                            if !tabFilter.isEmpty && visibleTabs.isEmpty {
                                Text("没有匹配的标签，也可以在下方手动添加网址。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                            HStack {
                                TextField("也可粘贴页面网址或输入域名", text: $manualPage).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("本轮白名单网址")
                                Picker("放行范围", selection: $manualKind) {
                                    Text("此页").tag(FocusPageRule.Kind.page)
                                    Text("网站").tag(FocusPageRule.Kind.site)
                                }.labelsHidden().frame(width: 75)
                                Button("加入") { addManual() }.buttonStyle(SubtleButtonStyle())
                            }
                            if let validation { Text(validation).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                            if pages.isEmpty {
                                Text("还没放行任何页面。也可以先从常用白名单导入。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            } else if !controller.chromeReady {
                                Text("请先连接 Chrome，才能识别这些页面；也可选择“本轮仅计时”。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("常用白名单", systemImage: "star.circle").font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("\(favoritePages.count) 条规则").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            if favoritePages.isEmpty {
                                Text("选好本轮名单后点“存为常用”，下次一键导入，不用重新选。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            } else {
                                RuleChipsView(pages: favoritePages, emptyHint: "") { rule in
                                    var settings = state.settings
                                    settings.focusGuard.favoritePages.removeAll { $0.id == rule.id }
                                    _ = state.updateSettings(settings)
                                }
                                HStack(spacing: 10) {
                                    Button("导入到本轮") {
                                        for rule in favoritePages where !pages.contains(where: { $0.id == rule.id }) {
                                            pages.append(rule)
                                        }
                                    }.buttonStyle(SubtleButtonStyle()).disabled(favoritePages.isEmpty)
                                    if !pages.isEmpty {
                                        Button("替换本轮名单") {
                                            pages = favoritePages
                                        }.buttonStyle(SubtleButtonStyle())
                                    }
                                    Spacer()
                                    Button("清除常用", role: .destructive) {
                                        var settings = state.settings
                                        settings.focusGuard.favoritePages = []
                                        _ = state.updateSettings(settings)
                                    }.buttonStyle(SubtleButtonStyle())
                                }
                            }
                            if !pages.isEmpty {
                                Button(pages.count == 1 && favoritePages.contains(pages[0]) ? "已存为常用" : "存为常用") {
                                    var settings = state.settings
                                    for rule in pages where !settings.focusGuard.favoritePages.contains(where: { $0.id == rule.id }) {
                                        settings.focusGuard.favoritePages.append(rule)
                                    }
                                    _ = state.updateSettings(settings)
                                }.buttonStyle(SubtleButtonStyle())
                                .disabled(pages.allSatisfy { rule in favoritePages.contains(where: { $0.id == rule.id }) })
                            }
                        }
                    }
                    PaperCard {
                        DisclosureGroup("本轮允许使用的 App（Chrome 按页面判断）") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(runningApps, id: \.bundleID) { app in
                                    Toggle(app.name, isOn: Binding(get: { allowedApps.contains(app.bundleID) }, set: { value in
                                        if value { allowedApps.insert(app.bundleID) } else { allowedApps.remove(app.bundleID) }
                                    })).font(.system(size: 12))
                                }
                                Text("番茄小记自动放行，方便使用待办和便签。其他 App 超时只提醒，不自动退出。")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }.padding(.top, 10)
                        }.font(.system(size: 12))
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Toggle("允许 AI 确认后关闭无关 Chrome 标签页", isOn: $allowClosing).font(.system(size: 12, weight: .medium))
                            Text("离开白名单 \(state.settings.focusGuard.remindAfterSeconds) 秒后提醒，再停留 \(state.settings.focusGuard.graceSeconds) 秒时才调用 AI；本轮最多 \(state.settings.focusGuard.maxChecks) 次。时间可在设置中调整。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            if allowClosing {
                                Text("届时将当前普通 Chrome 窗口截图、标题、网站和本轮目标发送给当前配置的 AI 服务商。截图不保存；无痕窗口不读取，不截图，不关闭。AI 无法确定或调用失败时保留页面。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                                if !state.hasAPIKey { Text("请先在设置中配置当前 AI 服务商的 API Key。").font(.system(size: 11)).foregroundStyle(Theme.accent) }
                                if !controller.chromeReady { Text("请先连接 Chrome。").font(.system(size: 11)).foregroundStyle(Theme.accent) }
                                HStack {
                                    Button(hasCapture ? "已允许屏幕读取" : "允许关闭前读取 Chrome 窗口") {
                                        hasCapture = FocusPageCapture.requestPermission()
                                    }.buttonStyle(SubtleButtonStyle()).disabled(hasCapture)
                                    Button("刷新权限") { hasCapture = FocusPageCapture.hasPermission }.buttonStyle(SubtleButtonStyle())
                                }
                                Text("误关时可在 Chrome 按 Command + Shift + T 恢复最近关闭的标签。")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }
            HStack {
                Button("取消") { state.guardSetupPresented = false }.buttonStyle(SubtleButtonStyle())
                Button("本轮仅计时") { state.useTimerOnlyForRound(goal: goal) }.buttonStyle(SubtleButtonStyle())
                    .help("仅跳过这一轮的守护，不改变全局设置")
                Spacer()
                Button(state.guardSetupActionTitle) {
                    state.saveGuardPlan(confirmedPlan)
                }.buttonStyle(SubtleButtonStyle()).disabled(!maySave)
            }.padding(20)
        }
        .frame(width: 590, height: min(730, (NSScreen.main?.visibleFrame.height ?? 800) - 70))
        .background(Theme.background).foregroundStyle(Theme.primary).preferredColorScheme(state.settings.appearance.colorScheme)
        .environment(\.glassControlsEnabled, state.settings.glassControlsEnabled)
        .onAppear {
            if let plan = controller.plan { goal = plan.goal; allowedApps = plan.appIDs; pages = plan.pages; allowClosing = plan.allowAIClosing }
            else if let draft = state.settings.focusGuard.reusablePlan {
                goal = draft.goal
                pages = draft.pages
                allowedApps = draft.appIDs
                allowClosing = false
            }
            if controller.plan == nil, !state.focusGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                goal = state.focusGoalDraft
            }
            goalFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in hasCapture = FocusPageCapture.hasPermission }
        .onChange(of: goal) { _, _ in
            if recommender.loading || !recommender.suggestions.isEmpty {
                recommender.cancel(message: "目标已修改，可重新读取并推荐。")
            }
        }
        .onChange(of: state.settings.ai) { _, _ in recommender.cancel(message: "AI 配置已修改，请重新推荐。") }
        .onDisappear { recommender.cancel() }
        .onChange(of: state.guardSetupPresented) { _, presented in
            if !presented { recommender.cancel(); onClose() }
        }
        .onExitCommand { state.guardSetupPresented = false }
    }
    private func isPageAdded(_ page: GuardPage) -> Bool {
        pages.contains { $0.kind == .page && $0.matches(page.url) }
    }
    private func isSiteAdded(_ page: GuardPage) -> Bool {
        pages.contains { $0.kind == .site && $0.matches(page.url) }
    }
    private func addPage(_ page: GuardPage) {
        guard let key = FocusPageRule.pageKey(page.url) else { return }
        add(.init(kind: .page, value: key, title: page.title))
    }
    private func addSite(_ input: String) {
        guard let host = FocusPageRule.siteHost(input) else { validation = "请输入有效域名。"; return }
        add(.init(kind: .site, value: host, title: host))
    }
    private func add(_ rule: FocusPageRule) {
        if !pages.contains(where: { $0.id == rule.id }) { pages.append(rule) }
        validation = nil; manualPage = ""
    }
    private func toggleExpanded(_ host: String) {
        if expandedHosts.contains(host) { expandedHosts.remove(host) } else { expandedHosts.insert(host) }
    }
    private func isSiteAdded(_ host: String) -> Bool {
        pages.contains { $0.kind == .site && $0.value == host }
    }
    private func addManual() {
        if manualKind == .site { addSite(manualPage) }
        else if let key = FocusPageRule.pageKey(manualPage) { add(.init(kind: .page, value: key, title: URLComponents(string: key)?.host ?? "学习页面")) }
        else { validation = "仅此页面请填写完整 http / https 网址，也可选择“网站”后输入域名。" }
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

/// 单个网站的分组行：组头显示域名 + 全站勾选，展开后逐页勾选。
struct TabGroupRow: View {
    let group: FocusGuardSetupView.TabGroup
    let expanded: Bool
    let siteAdded: Bool
    let selectedCount: Int
    var onToggleExpand: () -> Void
    var onAddSite: () -> Void
    var onRemoveSite: () -> Void
    var isPageAdded: (GuardPage) -> Bool
    var addPage: (GuardPage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.host).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(siteAdded ? Theme.green : Theme.primary)
                        Text("\(group.tabs.count) 个标签" + (selectedCount > 0 ? " · 已选 \(selectedCount) 页" : ""))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button(action: siteAdded ? onRemoveSite : onAddSite) {
                        HStack(spacing: 4) {
                            Image(systemName: siteAdded ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                            Text(siteAdded ? "整个网站" : "全选")
                                .font(.system(size: 11, weight: siteAdded ? .semibold : .medium))
                        }.foregroundStyle(siteAdded ? Theme.green : Theme.secondary)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(siteAdded ? "取消放行网站：\(group.host)" : "放行整个网站：\(group.host)")
                }.padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.tabs) { page in
                        Button {
                            if !isPageAdded(page) { addPage(page) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isPageAdded(page) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(isPageAdded(page) ? Theme.green : Theme.secondary)
                                    .frame(width: 14)
                                Text(page.title).lineLimit(1).font(.system(size: 11))
                                Spacer()
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .disabled(isPageAdded(page))
                        .accessibilityLabel("仅放行页面：\(page.title)")
                        if page.id != group.tabs.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }.padding(.leading, 20).padding(.bottom, 6)
            }
        }.padding(.horizontal, 10)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.4), lineWidth: 0.5))
    }
}

@MainActor
final class FocusGuardSetupWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState
    private let recommender = FocusWhitelistRecommender()
    var onClosed: (() -> Void)?
    init(state: AppState) {
        self.state = state
        let height = min(730, (NSScreen.main?.visibleFrame.height ?? 800) - 70)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "本轮专注白名单"
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.backgroundNS
        window.contentView = makePaperHostingView(rootView: FocusGuardSetupView(state: state, controller: state.guardController,
                                                                             recommender: recommender,
                                                                             onClose: { [weak self] in self?.window?.close() }),
                                                  size: NSSize(width: 590, height: height))
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) {
        recommender.cancel()
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
