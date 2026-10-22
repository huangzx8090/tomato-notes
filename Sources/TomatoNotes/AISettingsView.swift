import SwiftUI
import TomatoCore

struct ReviewSettingsSection: View {
    @ObservedObject var state: AppState
    @Binding var hasUnsavedChanges: Bool
    var requestNotifications: () -> Void
    @ViewState private var apiKey = ""
    @ViewState private var customURL = ""
    @ViewState private var hour = "21"
    @ViewState private var minute = "30"
    @ViewState private var connectionValidation: String?
    @ViewState private var timeValidation: String?
    @ViewState private var loaded = false
    @ViewState private var showingRemoveKey = false
    @ViewState private var showingProviderDiscard = false
    @ViewState private var pendingProvider: String?

    private var provider: AIProviderConfig { state.aiProvider }
    private var isCustom: Bool { provider.id == "custom" }
    private var busy: Bool { state.loadingAIModels || state.testingAI }
    private var connectionDirty: Bool {
        loaded && (!apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (isCustom && customURL != state.settings.ai.customBaseURL))
    }
    private var timeDirty: Bool {
        loaded && state.settings.review.scheduleEnabled &&
            (hour != String(format: "%02d", state.settings.review.hour) ||
             minute != String(format: "%02d", state.settings.review.minute))
    }
    private var dirty: Bool { connectionDirty || timeDirty }
    private var availableModels: [String] {
        var models = state.aiModels
        if !provider.defaultModel.isEmpty && !models.contains(provider.defaultModel) {
            models.insert(provider.defaultModel, at: 0)
        }
        return models
    }

    var body: some View {
        VStack(spacing: 14) {
            connection
            models
            automation
            privacy
        }
        .onAppear {
            customURL = state.settings.ai.customBaseURL
            hour = String(format: "%02d", state.settings.review.hour)
            minute = String(format: "%02d", state.settings.review.minute)
            loaded = true; hasUnsavedChanges = false
            state.refreshCredentialStatus()
        }
        .onChange(of: dirty) { _, value in hasUnsavedChanges = value }
        .confirmationDialog("移除 \(provider.name) 的本机密钥？", isPresented: $showingRemoveKey, titleVisibility: .visible) {
            Button("移除密钥", role: .destructive) { state.removeAPIKey() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("之后使用这个服务商时，需要重新填写 API Key。其他服务商的密钥会保留；环境变量提供的密钥不受影响。")
        }
        .confirmationDialog("更换服务商？", isPresented: $showingProviderDiscard, titleVisibility: .visible) {
            Button("放弃连接信息并更换", role: .destructive) {
                if let pendingProvider { selectProvider(pendingProvider) }
                pendingProvider = nil
            }
            Button("继续编辑", role: .cancel) { pendingProvider = nil }
        } message: {
            Text("当前填写的密钥或接口地址还没有保存。")
        }
    }

    private var connection: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsStepTitle(number: 1, title: "连接 AI 服务商")
                SettingsHelpText("选择你已有账号的服务商，粘贴它提供的 API Key。")
                Picker("服务商", selection: Binding(get: { state.settings.ai.providerID }, set: requestProvider)) {
                    ForEach(AIProviderCatalog.presets) { Text($0.name).tag($0.id) }
                }.font(.system(size: 12)).accessibilityLabel("AI 服务商")
                if isCustom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("接口地址").font(.system(size: 11, weight: .medium))
                        TextField("https://your-gateway.com/v1", text: $customURL)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("自定义接口地址")
                        SettingsHelpText("填写 OpenAI 兼容接口的基础地址，通常以 /v1 结尾。")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API Key").font(.system(size: 11, weight: .medium))
                        Spacer()
                        if state.hasAPIKey {
                            Label("本机已找到密钥", systemImage: "checkmark.circle")
                                .font(.system(size: 10)).foregroundStyle(Theme.green)
                        }
                    }
                    SecureField(state.hasAPIKey ? "已保存；填写新密钥可替换" : "粘贴 API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("\(provider.name) API Key")
                }
                if let connectionValidation {
                    Text(connectionValidation).font(.system(size: 11)).foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 9) {
                    Button("保存连接信息", action: saveConnection).buttonStyle(SettingsButtonStyle())
                        .disabled(!connectionDirty)
                    if connectionDirty {
                        Text("有未保存的修改").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    } else if state.hasAPIKey {
                        Text("下一步：获取并选择模型").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            }.disabled(busy)
        }
    }

    private var models: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 13) {
                SettingsStepTitle(number: 2, title: "选择模型并验证")
                if !state.hasAPIKey {
                    SettingsHelpText("先完成上方的连接信息，再获取服务商提供的模型列表。")
                } else if connectionDirty {
                    SettingsHelpText("先保存刚才修改的连接信息，再继续。")
                }
                Button(state.loadingAIModels ? "正在获取模型…" : "获取可用模型", action: state.fetchAIModels)
                    .buttonStyle(SettingsButtonStyle())
                    .disabled(!state.hasAPIKey || connectionDirty || busy)
                if !availableModels.isEmpty {
                    Picker("使用模型", selection: Binding(get: { provider.defaultModel }, set: { model in
                        state.updateAIProvider { $0.modelOverride = model }
                    })) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model + (!state.aiModels.isEmpty && !state.aiModels.contains(model) ? "（当前配置）" : ""))
                                .tag(model)
                        }
                    }.font(.system(size: 12)).accessibilityLabel("AI 模型")
                        .disabled(!state.hasAPIKey || connectionDirty || busy)
                    SettingsHelpText("模型选择会自动保存。需要理解图片或检查网页时，请选择支持图片的模型。")
                    Button(state.testingAI ? "正在验证连接…" : "测试当前模型连接", action: state.testAIConnection)
                        .buttonStyle(SettingsButtonStyle())
                        .disabled(!state.hasAPIKey || connectionDirty || busy)
                }
                Label(state.aiStatus, systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var automation: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsStepTitle(number: 3, title: "按需开启自动回顾")
                SettingsHelpText("开启后，会将对应记录、补充文字和所选图片发送给 \(provider.name)。也可在「进展」中手动生成。")
                if !state.hasAPIKey { SettingsHelpText("连接配置完成后，即可开启下方选项。") }
                SettingsToggleRow(title: "每轮专注后整理成果", detail: "投入至少 1 分钟后，在后台整理这一轮。失败时保留记录，可手动重试。",
                                  value: Binding(get: { state.settings.review.autoSummarizeSessions }, set: { value in
                    var next = state.settings; next.review.autoSummarizeSessions = value; _ = state.updateSettings(next)
                })).disabled(!state.hasAPIKey)
                Divider()
                SettingsToggleRow(title: "每天定时生成回顾", detail: "把当天的专注成果整理成一份回顾。",
                                  value: Binding(get: { state.settings.review.scheduleEnabled }, set: { value in
                    var next = state.settings; next.review.scheduleEnabled = value
                    if state.updateSettings(next), value { requestNotifications() }
                })).disabled(!state.hasAPIKey)
                if state.settings.review.scheduleEnabled {
                    HStack(spacing: 7) {
                        Text("每天").font(.system(size: 12))
                        timeField($hour, label: "回顾小时")
                        Text(":").foregroundStyle(Theme.secondary)
                        timeField($minute, label: "回顾分钟")
                        Spacer(minLength: 0)
                        Button("保存时间", action: saveTime).buttonStyle(SettingsButtonStyle()).disabled(!timeDirty)
                    }
                    if let timeValidation {
                        Text(timeValidation).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    SettingsHelpText("已设为每天 \(state.settings.review.timeLabel)。当天错过时，启动或解锁后补生成；应用退出时不会执行。")
                }
            }
        }
    }

    private var privacy: some View {
        PaperCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsHelpText("API Key 按服务商分别保存在本机钥匙串。切换服务商时，可以继续使用已保存的密钥。")
                    SettingsHelpText("成果回顾会发送目标、App 时长、完成待办及你添加的文字和图片。专注守护的 AI 检查还需要当前普通 Chrome 窗口的截图、标题和网址，须在每轮单独授权；截图不保存。")
                    SettingsHelpText("基础计时与白名单外时长统计在本机完成。")
                    Button("重新检测本机密钥", action: state.refreshCredentialStatus)
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    if state.hasAPIKey {
                        Button("移除 \(provider.name) 的本机密钥") { showingRemoveKey = true }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                }.font(.system(size: 11)).padding(.top, 10)
            } label: {
                Label("密钥与数据使用", systemImage: "lock.shield").font(.system(size: 12, weight: .medium))
            }.tint(Theme.secondary)
        }
    }

    private func requestProvider(_ id: String) {
        guard id != state.settings.ai.providerID else { return }
        if connectionDirty { pendingProvider = id; showingProviderDiscard = true }
        else { selectProvider(id) }
    }

    private func selectProvider(_ id: String) {
        apiKey = ""; connectionValidation = nil
        state.updateAIProvider { $0.providerID = id; $0.modelOverride = "" }
        customURL = state.settings.ai.customBaseURL
    }

    private func saveConnection() {
        if isCustom {
            let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = trimmed.contains("://") ? trimmed : "https://" + trimmed
            guard !trimmed.isEmpty, let url = URL(string: address), url.host?.isEmpty == false,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                connectionValidation = "请填写有效的接口地址，例如 https://your-gateway.com/v1。"; return
            }
            state.updateAIProvider { $0.customBaseURL = trimmed }
            customURL = trimmed
        }
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard state.saveAPIKey(apiKey) else { connectionValidation = state.aiStatus; return }
            apiKey = ""
        }
        connectionValidation = nil
    }

    private func timeField(_ value: Binding<String>, label: String) -> some View {
        TextField("00", text: value).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
            .font(.system(size: 12).monospacedDigit()).frame(width: 38).accessibilityLabel(label)
    }

    private func saveTime() {
        guard let h = Int(hour), (0...23).contains(h), let m = Int(minute), (0...59).contains(m) else {
            timeValidation = "小时填写 00–23，分钟填写 00–59。"; return
        }
        var next = state.settings; next.review.hour = h; next.review.minute = m
        if state.updateSettings(next) {
            hour = String(format: "%02d", h); minute = String(format: "%02d", m); timeValidation = nil
        }
    }
}
