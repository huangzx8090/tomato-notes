import SwiftUI
import TomatoCore

struct ActivityRecordingSettingsCard: View {
    @ObservedObject var state: AppState

    private func source(_ key: WritableKeyPath<ActivityRecordingSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.settings.activityRecording[keyPath: key] }, set: { value in
            var next = state.settings
            next.activityRecording[keyPath: key] = value
            _ = state.updateSettings(next)
        })
    }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("AI 自动记录", systemImage: "sparkles").font(.system(size: 14, weight: .semibold))
                SettingsHelpText("点开始后直接做事，AI 会根据下方允许的材料识别主题，到点后自动整理这一轮，无需填写或确认。")
                SettingsHelpText("开启后，选中的页面标题、网站、便签变更与完成待办会在本机保存，并发送给 \(state.aiProvider.name) 判断主题和生成回顾。标题可能包含个人信息，请按需选择。")
                SettingsToggleRow(title: "开启 AI 自动记录", detail: "约两分钟后初步识别；结束后后台整理。默认关闭，可随时停止。", value: source(\.enabled))
                Divider()
                SettingsToggleRow(title: "Chrome 浏览材料", detail: "只记录专注时前台普通页面的标题、网站及采样停留时间。", value: source(\.chromeEnabled))
                SettingsToggleRow(title: "本轮便签与完成待办", detail: "记录专注期间写入或修改的便签文字和勾选完成的待办；不读取整份历史便签。", value: source(\.notesEnabled))
                SettingsToggleRow(title: "用 App 时长辅助识别主题", detail: "需同时开启「数据与隐私」中的 App 明细记录；App 名称本身不能确定具体工作。", value: source(\.appUsageEnabled))
                if state.settings.activityRecording.enabled && state.settings.activityRecording.chromeEnabled {
                    Button("允许读取 Chrome", action: state.requestActivityChromeAccess).buttonStyle(SettingsButtonStyle())
                    SettingsHelpText(state.activityStatus)
                }
                if state.settings.activityRecording.enabled && !state.hasAPIKey {
                    SettingsHelpText("当前没有可用密钥，活动仍在本机记录；连接 AI 后可识别新材料，历史记录可手动整理。")
                }
                SettingsHelpText("暂停、休息、锁屏时停止采集。不读取无痕窗口、网页正文，不自动截图；自动采集不保存完整网址路径与查询参数。活动可在每轮详情中查看和删除，关闭开关会保留已有记录。")
            }
        }
    }
}

struct ActivitySessionDetails: View {
    @ObservedObject var state: AppState
    let sessionID: UUID
    @ViewState private var editingTitle = false
    @ViewState private var titleDraft = ""
    @ViewState private var expanded = false

    private var activities: [FocusActivity] { ActivityRecorder.activities(sessionID: sessionID, in: state.data) }
    private var record: WorkRecord? { state.workRecord(for: .session(sessionID)) }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("主题与活动依据", systemImage: "text.magnifyingglass").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("修改主题") {
                        titleDraft = SessionProgress.build(sessionID: sessionID, from: state.data)?.title ?? ""
                        editingTitle.toggle()
                    }.buttonStyle(SubtleButtonStyle())
                }
                if editingTitle {
                    HStack {
                        TextField("这一轮的主题", text: $titleDraft).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("修改本轮记录主题")
                            .onSubmit(saveTitle)
                        Button("保存", action: saveTitle).buttonStyle(SubtleButtonStyle()).disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if record?.titleOverride != nil {
                    Text("使用你修改的名称；AI 后续会参考，当前名称不会被覆盖。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else if let topic = record?.activityTopic {
                    Text("AI 初步识别 · \(topic.model) · 可随时修改")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if activities.isEmpty {
                    Text("还没有活动材料。开启 AI 自动记录并允许相应来源后，新活动会出现在这里。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                } else {
                    DisclosureGroup("查看 \(activities.count) 条原始活动", isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(activities) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.label).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                        Text(timeLabel(item)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                        if let detail = item.detail, !detail.isEmpty {
                                            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Button { state.removeFocusActivity(item.id) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                                        .accessibilityLabel("删除活动：\(item.title)")
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.top, 12)
                    }.font(.system(size: 12))
                    Text("删除会移除本轮相同材料的记录及依赖的 AI 总结，并在这一轮停止记录该材料。浏览时间是采样估计，不代表读完或学会。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func saveTitle() {
        state.renameActivitySession(sessionID, title: titleDraft)
        editingTitle = false
    }

    private func timeLabel(_ item: FocusActivity) -> String {
        let start = item.startedAt.formatted(date: .omitted, time: .shortened)
        if item.kind == .chromePage {
            return "\(start)–\(item.endedAt.formatted(date: .omitted, time: .shortened)) · \(item.site ?? "") · 约 \(durationLabel(item.seconds))"
        }
        return start
    }
}

struct QuickActivitySupplement: View {
    @ObservedObject var state: AppState
    let sessionID: UUID
    @ViewState private var expanded = false
    @ViewState private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if expanded {
            HStack(spacing: 7) {
                TextField("例如：纸上做完了两道练习", text: $text).textFieldStyle(.roundedBorder)
                    .font(.system(size: 12)).focused($focused).onSubmit(save)
                    .accessibilityLabel("给这一轮补一句")
                Button("记下", action: save).buttonStyle(SubtleButtonStyle()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            Button { expanded = true; focused = true } label: { Label("补一句", systemImage: "plus.bubble") }
                .buttonStyle(SubtleButtonStyle())
        }
    }

    private func save() {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let scope = WorkScope.session(sessionID)
        let existing = state.workRecord(for: scope)?.userText ?? ""
        state.updateWorkText(existing.isEmpty ? line : existing + "\n" + line, for: scope)
        state.flushWorkChanges()
        text = ""; expanded = false
    }
}
