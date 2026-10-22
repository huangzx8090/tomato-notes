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
    @FocusState private var goalFocused: Bool

    private var runningApps: [AppIdentity] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular &&
            $0.bundleIdentifier != "com.google.Chrome" && !($0.bundleIdentifier?.hasPrefix("com.zixuan.TomatoNotes") ?? true) }
            .compactMap { app in app.bundleIdentifier.map { AppIdentity(name: app.localizedName ?? $0, bundleID: $0) } }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    private var maySave: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && goal.count <= 300 &&
            (pages.isEmpty || controller.chromeReady) &&
            (!allowClosing || (hasCapture && controller.chromeReady && state.hasAPIKey))
    }
    private var unfinishedTodos: [TodoItem] {
        Array(state.data.todos.filter { $0.localDay == state.todayKey && !$0.isCompleted }.prefix(12))
    }
    private var visibleTabs: [GuardPage] {
        controller.availableTabs.filter {
            FocusPageRule.pageKey($0.url) != nil &&
            (tabFilter.isEmpty || ($0.title + " " + $0.host).localizedCaseInsensitiveContains(tabFilter))
        }
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
                            Text("平时只在本机检查白名单，提醒不消耗 AI Tokens。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("本轮允许的 Chrome 页面").font(.system(size: 13, weight: .semibold))
                            Button(controller.loadingTabs ? "正在连接…" : "连接 Chrome / 读取当前窗口标签") { controller.loadTabs() }
                                .buttonStyle(SubtleButtonStyle()).disabled(controller.loadingTabs)
                            Text(controller.permissionStatus).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            if !controller.availableTabs.isEmpty {
                                TextField("筛选标题或网站", text: $tabFilter).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("筛选 Chrome 标签")
                            }
                            ForEach(visibleTabs) { page in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(page.title).lineLimit(2).font(.system(size: 12))
                                        Text(page.host).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Button(isPageAdded(page) ? "已加入" : "此页") { addPage(page) }.buttonStyle(SubtleButtonStyle())
                                        .disabled(isPageAdded(page))
                                        .accessibilityLabel("仅放行页面：\(page.title)")
                                    Button(isSiteAdded(page) ? "已放行" : "网站") { addSite(page.host) }.buttonStyle(SubtleButtonStyle())
                                        .disabled(isSiteAdded(page))
                                        .accessibilityLabel("放行网站：\(page.host)")
                                }
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
                            if !pages.isEmpty {
                                HStack {
                                    Text("已加入白名单（\(pages.count)）").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                                    Spacer()
                                    Button("清空") { pages.removeAll() }.buttonStyle(SubtleButtonStyle())
                                }
                                if !controller.chromeReady {
                                    Text("请先连接 Chrome，才能识别这些页面；也可选择“本轮仅计时”。")
                                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                                }
                            }
                            ForEach(pages) { rule in
                                HStack {
                                    Image(systemName: rule.kind == .page ? "doc.text" : "globe")
                                    Text(rule.title).lineLimit(1)
                                    Spacer()
                                    Text(rule.kind == .page ? "仅此页面" : "整个网站").foregroundStyle(Theme.secondary)
                                    Button { pages.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain).accessibilityLabel("移除白名单：\(rule.title)")
                                }.font(.system(size: 11))
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
                                Text("届时将当前普通 Chrome 窗口截图、标题、网站和本轮目标发送给 DeepSeek。截图不保存；无痕窗口不读取，不截图，不关闭。AI 无法确定或调用失败时保留页面。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                                if !state.hasAPIKey { Text("请先在设置中配置 DeepSeek API Key。").font(.system(size: 11)).foregroundStyle(Theme.accent) }
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
                    state.saveGuardPlan(.init(goal: goal.trimmingCharacters(in: .whitespacesAndNewlines), appIDs: allowedApps, pages: pages, allowAIClosing: allowClosing))
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
        .onChange(of: state.guardSetupPresented) { _, presented in if !presented { onClose() } }
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
    private func addManual() {
        if manualKind == .site { addSite(manualPage) }
        else if let key = FocusPageRule.pageKey(manualPage) { add(.init(kind: .page, value: key, title: URLComponents(string: key)?.host ?? "学习页面")) }
        else { validation = "仅此页面请填写完整 http / https 网址，也可选择“网站”后输入域名。" }
    }
}

@MainActor
final class FocusGuardSetupWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState
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
                                                                             onClose: { [weak self] in self?.window?.close() }),
                                                  size: NSSize(width: 590, height: height))
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) {
        state.guardSetupPresented = false
        onClosed?()
    }
}

struct FocusGuardSettingsSection: View {
    @ObservedObject var state: AppState
    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("专注守护 · Chrome", systemImage: "leaf.circle").font(.system(size: 14, weight: .semibold))
                Toggle("开始每轮专注时选择本轮白名单", isOn: Binding(get: { state.settings.focusGuard.enabled }, set: { value in
                    var settings = state.settings; settings.focusGuard.enabled = value; _ = state.updateSettings(settings)
                })).font(.system(size: 12))
                Toggle("自动沿用上轮目标与白名单", isOn: Binding(get: { state.settings.focusGuard.reuseLastPlan }, set: { value in
                    var settings = state.settings
                    settings.focusGuard.reuseLastPlan = value
                    settings.focusGuard.rememberDraft(value ? state.guardController.plan : nil)
                    _ = state.updateSettings(settings)
                })).font(.system(size: 12))
                if state.settings.focusGuard.hasLastPlan {
                    Text("将沿用 \(state.settings.focusGuard.lastPages.count) 个页面规则、\(state.settings.focusGuard.lastAppIDs.count) 个 App。下轮直接开始并仅提醒；AI 关闭需在该轮单独开启。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                } else {
                    Text("默认关闭，每轮重新选择。开启后保存一次名单，后续专注自动沿用；AI 关闭授权不沿用。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                secondsRow("离开白名单后提醒", key: \.remindAfterSeconds, range: 5...1800)
                secondsRow("提醒后再等待", key: \.graceSeconds, range: 5...600)
                Stepper("每轮最多 \(state.settings.focusGuard.maxChecks) 次 AI 判断", value: integerBinding(\.maxChecks, range: 1...5), in: 1...5)
                    .font(.system(size: 12))
                Text("平时零 AI 调用。只在本轮明确允许关闭、提醒后仍未返回时，由 AI 核对 Chrome；其他 App 只提醒。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func secondsRow(_ title: String, key: WritableKeyPath<FocusGuardSettings, Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12)); Spacer()
            TextField("60", value: integerBinding(key, range: range), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 55).accessibilityLabel(title + "秒数")
            Text("秒").font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }
    private func integerBinding(_ key: WritableKeyPath<FocusGuardSettings, Int>, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { state.settings.focusGuard[keyPath: key] }, set: { value in
            var settings = state.settings; settings.focusGuard[keyPath: key] = min(range.upperBound, max(range.lowerBound, value)); _ = state.updateSettings(settings)
        })
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
