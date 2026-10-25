import AppKit
import SwiftUI
import TomatoCore

enum SettingsPage: String {
    case overview, guide, timer, guardSettings, ai, reminders, appearance, data

    var title: String {
        switch self {
        case .overview: "设置"
        case .guide: "从这里开始"
        case .timer: "专注与休息"
        case .guardSettings: "专注守护"
        case .ai: "AI 助手"
        case .reminders: "提醒与快捷键"
        case .appearance: "外观与运行"
        case .data: "数据与隐私"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "slider.horizontal.3"
        case .guide: "sparkle"
        case .timer: "timer"
        case .guardSettings: "leaf"
        case .ai: "sparkles"
        case .reminders: "bell"
        case .appearance: "paintpalette"
        case .data: "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "按你想做的事，找到对应设置。"
        case .guide: "先开始一轮，再按需要开启更多能力。"
        case .timer: "选好节奏，让专注和休息自然交替。"
        case .guardSettings: "选好允许使用的应用和网页，离开时提醒你。"
        case .ai: "连接服务商，整理成果和生成每日回顾。"
        case .reminders: "选择怎样提醒，以及如何快速唤起。"
        case .appearance: "调整配色、打开方式和外接屏行为。"
        case .data: "了解记录内容，查看和备份本地数据。"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @Binding var page: SettingsPage
    @Binding var hasUnsavedChanges: Bool
    var openFocus: () -> Void
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    @ViewState private var pendingPage: SettingsPage?
    @ViewState private var showingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if page == .overview {
                overview
            } else {
                pageHeader
                switch page {
                case .overview: EmptyView()
                case .guide: guide
                case .timer: TimerSettingsPane(state: state, hasUnsavedChanges: $hasUnsavedChanges)
                case .guardSettings:
                    FocusGuardSettingsSection(state: state, openFocus: openFocus, openAI: { navigate(to: .ai) })
                case .ai:
                    ReviewSettingsSection(state: state, hasUnsavedChanges: $hasUnsavedChanges,
                                          requestNotifications: requestNotifications)
                case .reminders:
                    ReminderSettingsPane(state: state, hasUnsavedChanges: $hasUnsavedChanges,
                                         testReminder: testReminder, requestNotifications: requestNotifications)
                case .appearance: AppearanceSettingsPane(state: state)
                case .data: DataSettingsPane(state: state, openAI: { navigate(to: .ai) })
                }
            }
        }
        .toggleStyle(.switch).tint(Theme.green)
        .confirmationDialog("还有未保存的修改", isPresented: $showingDiscard, titleVisibility: .visible) {
            Button("放弃修改并返回", role: .destructive) {
                hasUnsavedChanges = false
                if let pendingPage { page = pendingPage }
                pendingPage = nil
            }
            Button("继续编辑", role: .cancel) { pendingPage = nil }
        } message: {
            Text("保存后再离开，可以保留刚才填写的内容。")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("设置").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button { navigate(to: .guide) } label: {
                    Label("使用指南", systemImage: "questionmark.circle")
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("settings.guide")
            }
            SettingsHelpText("默认节奏已就绪。回到「专注」即可开始，其他功能按需配置。")
            menuGroup("专注与成果") {
                menuRow(.timer, summary: "时长与长休息间隔", status: "\(state.settings.focusMinutes) 分钟")
                Divider().overlay(Theme.border.opacity(0.4))
                menuRow(.guardSettings, summary: "白名单、分心统计与离开提醒",
                        status: state.settings.focusGuard.enabled ? "已开启" : "按需开启")
                Divider().overlay(Theme.border.opacity(0.4))
                menuRow(.ai, summary: "连接服务商与自动回顾", status: state.hasAPIKey ? "已配置" : "可选")
            }
            menuGroup("日常偏好") {
                menuRow(.reminders, summary: "声音、系统通知与全局快捷键")
                Divider().overlay(Theme.border.opacity(0.4))
                menuRow(.appearance, summary: "配色、Dock 图标与合盖计时", status: state.settings.appearance.label)
                Divider().overlay(Theme.border.opacity(0.4))
                menuRow(.data, summary: "App 明细、本地文件与备份")
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button { navigate(to: .overview) } label: {
                Label("设置", systemImage: "chevron.left")
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                .accessibilityLabel("返回设置首页").accessibilityIdentifier("settings.back")
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: page.symbol).font(.system(size: 18))
                    .foregroundStyle(Theme.accent).frame(width: 39, height: 39)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(page.title).font(.system(size: 18, weight: .semibold))
                    SettingsHelpText(page.subtitle)
                }
            }
        }
    }

    private func menuGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).padding(.leading, 3)
            VStack(spacing: 0, content: content).padding(.horizontal, 13).padding(.vertical, 2)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border.opacity(0.6), lineWidth: 0.6))
        }
    }

    private func menuRow(_ destination: SettingsPage, summary: String, status: String? = nil) -> some View {
        Button { navigate(to: destination) } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol).font(.system(size: 14))
                    .foregroundStyle(destination == .ai ? Theme.accent : Theme.green)
                    .frame(width: 29, height: 31)
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text(summary).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                if let status { Text(status).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("settings.open.\(destination.rawValue)")
    }

    private var guide: some View {
        VStack(spacing: 12) {
            guideStep(1, title: "开始一轮专注", detail: "在「专注」中写下目标，或直接开始。默认专注 25 分钟，完成后休息 5 分钟。",
                      action: "前往专注", perform: openFocus)
            guideStep(2, title: "想知道分心多久？设置白名单", detail: "在「设置并开始专注」中选择本轮允许使用的 App 和网页。离开太久会提醒，结束后可在进展里查看白名单外时长。",
                      action: "了解专注守护", perform: { navigate(to: .guardSettings) })
            guideStep(3, title: "需要整理成果时，连接 AI", detail: "选择服务商、保存 API Key，再获取并选择模型。你可以手动整理成果，也可以开启每轮或每日自动回顾。",
                      action: "配置 AI 助手", perform: { navigate(to: .ai) })
            SettingsHelpText("锁屏和系统睡眠会暂停计时；回来后，在「专注」中主动继续。")
                .padding(.horizontal, 3)
        }
    }

    private func guideStep(_ number: Int, title: String, detail: String, action: String,
                           perform: @escaping () -> Void) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 11) {
                SettingsStepTitle(number: number, title: title)
                SettingsHelpText(detail)
                Button(action, action: perform).buttonStyle(SettingsButtonStyle())
            }
        }
    }

    private func navigate(to destination: SettingsPage) {
        if hasUnsavedChanges {
            pendingPage = destination
            showingDiscard = true
        } else { page = destination }
    }
}

struct SettingsHelpText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        SubtleButtonStyle().makeBody(configuration: configuration).opacity(isEnabled ? 1 : 0.45)
    }
}

struct SettingsStepTitle: View {
    let number: Int
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)").font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent).frame(width: 23, height: 23)
                .background(Theme.accentSoft, in: Circle())
            Text(title).font(.system(size: 13, weight: .semibold))
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var value: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $value).font(.system(size: 12, weight: .medium))
            SettingsHelpText(detail)
        }
    }
}

struct SettingsNumberRow: View {
    let title: String
    let unit: String
    let bounds: ClosedRange<Int>
    @Binding var value: Int
    var body: some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 12))
            Spacer(minLength: 6)
            TextField("", value: $value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 47)
                .font(.system(size: 12).monospacedDigit()).accessibilityLabel(title + "（" + unit + "）")
            Text(unit).font(.system(size: 11)).foregroundStyle(Theme.secondary).frame(minWidth: 13)
            Stepper(title, value: $value, in: bounds).labelsHidden().fixedSize()
                .accessibilityLabel("调整" + title)
        }
    }
}

private struct TimerSettingsPane: View {
    @ObservedObject var state: AppState
    @Binding var hasUnsavedChanges: Bool
    @ViewState private var focus = 25
    @ViewState private var shortBreak = 5
    @ViewState private var longBreak = 15
    @ViewState private var every = 4
    @ViewState private var loaded = false
    @ViewState private var saveError: String?

    private var dirty: Bool {
        loaded && (focus != state.settings.focusMinutes || shortBreak != state.settings.shortBreakMinutes ||
            longBreak != state.settings.longBreakMinutes || every != state.settings.longBreakEvery)
    }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 15) {
                Text("专注的节奏").font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    RotaryDial(title: "专注", unit: "分钟", bounds: 1...180, tint: Theme.accent, value: $focus)
                    RotaryDial(title: "短休息", unit: "分钟", bounds: 1...60, tint: Theme.green, value: $shortBreak)
                    RotaryDial(title: "长休息", unit: "分钟", bounds: 1...120, tint: Theme.green, value: $longBreak)
                    RotaryDial(title: "长休息间隔", unit: "轮", bounds: 2...8, tint: Color(hex: 0x9A7D54), value: $every)
                }.padding(.vertical, 4)
                SettingsHelpText("转动旋钮调节，− / ＋ 精确微调。调好后，点击下方按钮保存。")
                Divider()
                HStack(spacing: 9) {
                    preset("经典 · 25 / 5", focus: 25, rest: 5, longRest: 15)
                    preset("深度 · 50 / 10", focus: 50, rest: 10, longRest: 20)
                }
                SettingsHelpText("每完成 \(every) 轮专注，安排一次 \(longBreak) 分钟的长休息。")
                HStack(spacing: 10) {
                    Button(dirty ? "保存专注节奏" : "节奏已保存", action: save).buttonStyle(SettingsButtonStyle())
                        .disabled(!dirty)
                    if dirty {
                        Text("有未保存的修改").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    }
                }
                if let saveError {
                    Text(saveError).font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                SettingsHelpText("正在进行的阶段保持原时长，新节奏从后续阶段生效。")
            }
        }
        .onAppear {
            focus = state.settings.focusMinutes; shortBreak = state.settings.shortBreakMinutes
            longBreak = state.settings.longBreakMinutes; every = state.settings.longBreakEvery
            loaded = true; hasUnsavedChanges = false
        }
        .onChange(of: dirty) { _, value in hasUnsavedChanges = value }
    }
    private func preset(_ title: String, focus presetFocus: Int, rest: Int, longRest: Int) -> some View {
        let selected = focus == presetFocus && shortBreak == rest && longBreak == longRest && every == 4
        return Button {
            focus = presetFocus; shortBreak = rest; longBreak = longRest; every = 4
        } label: {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(SettingsButtonStyle()).accessibilityLabel(title + (selected ? "，已选中" : ""))
    }
    private func save() {
        var next = state.settings
        next.focusMinutes = focus; next.shortBreakMinutes = shortBreak
        next.longBreakMinutes = longBreak; next.longBreakEvery = every
        saveError = state.updateSettings(next) ? nil : state.feedback
    }
}

private struct ReminderSettingsPane: View {
    @ObservedObject var state: AppState
    @Binding var hasUnsavedChanges: Bool
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    @ViewState private var timerKey = Hotkey(letter: "P")
    @ViewState private var todoKey = Hotkey(letter: "T")
    @ViewState private var noteKey = Hotkey(letter: "N")
    @ViewState private var loaded = false
    @ViewState private var saveError: String?

    private var dirty: Bool {
        loaded && (timerKey != state.settings.timerHotkey || todoKey != state.settings.todoHotkey || noteKey != state.settings.noteHotkey)
    }

    var body: some View {
        VStack(spacing: 14) {
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("阶段结束时提醒").font(.system(size: 13, weight: .semibold))
                    SettingsToggleRow(title: "播放提示音", detail: "完成专注或休息时，播放一次声音。",
                                      value: state.settingBinding(\.soundEnabled))
                    Divider()
                    SettingsToggleRow(title: "发送系统通知", detail: "允许通知后，可在其他 App 中收到阶段结束提醒。",
                                      value: state.settingBinding(\.notificationsEnabled))
                    SettingsHelpText(state.notificationStatus)
                    HStack(spacing: 8) {
                        Button("发送测试提醒", action: testReminder)
                        Button("申请通知权限", action: requestNotifications)
                    }.buttonStyle(SettingsButtonStyle())
                    Button("打开 macOS 通知设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("全局快捷键").font(.system(size: 13, weight: .semibold))
                    SettingsHelpText("在其他 App 中也能使用。修改后，点击下方按钮保存。")
                    HotkeySettingsRow(title: "开始 / 暂停专注", value: $timerKey)
                    Divider()
                    HotkeySettingsRow(title: "快速添加待办", value: $todoKey)
                    Divider()
                    HotkeySettingsRow(title: "打开最近便签", value: $noteKey)
                    Button(dirty ? "保存快捷键" : "快捷键已保存") {
                        var next = state.settings
                        next.timerHotkey = timerKey; next.todoHotkey = todoKey; next.noteHotkey = noteKey
                        saveError = state.updateSettings(next) ? nil : state.feedback
                    }.buttonStyle(SettingsButtonStyle()).disabled(!dirty)
                    if let saveError {
                        Text(saveError).font(.system(size: 11)).foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SettingsHelpText("字母键使用 A–Z。提示占用时，请换一个组合，或关闭对应快捷键。")
                }
            }
        }
        .onAppear {
            timerKey = state.settings.timerHotkey; todoKey = state.settings.todoHotkey; noteKey = state.settings.noteHotkey
            loaded = true; hasUnsavedChanges = false
        }
        .onChange(of: dirty) { _, value in hasUnsavedChanges = value }
    }
}

private struct HotkeySettingsRow: View {
    let title: String
    @Binding var value: Hotkey
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $value.enabled).font(.system(size: 12))
            if value.enabled {
                HStack(spacing: 8) {
                    Picker("组合键", selection: $value.modifier) {
                        Text("⌃ Control + ⌥ Option").tag("controlOption")
                        Text("⌘ Command + ⇧ Shift").tag("commandShift")
                        Text("⌃ Control + ⌘ Command").tag("controlCommand")
                    }.labelsHidden().frame(maxWidth: .infinity).accessibilityLabel(title + "组合键")
                    TextField("P", text: $value.letter).textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center).font(.system(size: 12, weight: .medium)).frame(width: 36)
                        .accessibilityLabel(title + "字母键")
                }
            }
        }
    }
}

private struct AppearanceSettingsPane: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(spacing: 14) {
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("界面外观").font(.system(size: 13, weight: .semibold))
                    Picker("配色", selection: Binding(get: { state.settings.appearance }, set: { value in
                        var next = state.settings; next.appearance = value; _ = state.updateSettings(next)
                    })) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityLabel("外观模式")
                    SettingsHelpText("跟随系统会自动切换浅色和深色。")
                    Divider()
                    SettingsToggleRow(title: "按钮玻璃效果", detail: "为按钮和顶部导航加入透明质感。",
                                      value: state.settingBinding(\.glassControlsEnabled))
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("打开与运行").font(.system(size: 13, weight: .semibold))
                    SettingsToggleRow(title: "在 Dock 中显示图标", detail: "也可点击 Dock 图标打开；菜单栏入口始终可用。",
                                      value: state.settingBinding(\.showDockIcon))
                    Divider()
                    SettingsToggleRow(title: "外接屏工作时，合盖继续计时", detail: "仅在外接显示器工作时继续。锁屏或系统睡眠仍会暂停，回来后由你主动继续。",
                                      value: state.settingBinding(\.allowClamshellWithExternalDisplay))
                }
            }
            SettingsHelpText("这里的更改会自动保存。").padding(.horizontal, 3)
        }
    }
}

private struct DataSettingsPane: View {
    @ObservedObject var state: AppState
    var openAI: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("本地记录").font(.system(size: 13, weight: .semibold))
                    SettingsToggleRow(title: "记录前台 App 使用明细", detail: "只在专注运行时保存 App 名称和停留时长；暂停和休息时不记录。关闭后，对应时段显示为“未记录”。",
                                      value: state.settingBinding(\.recordingEnabled))
                    Divider()
                    Label("白名单外时长始终统计", systemImage: "leaf")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.green)
                    SettingsHelpText("配置本轮白名单后，白名单外 App 停留时长会自动累计，不受上方明细开关或 AI 关闭授权影响。")
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("备份与存放位置").font(.system(size: 13, weight: .semibold))
                    SettingsHelpText("计时、待办和便签保存在这台 Mac。备份会同时保留记录中引用的图片。")
                    HStack(spacing: 8) {
                        Button("备份数据") {
                            if let url = state.backupData() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("在 Finder 中查看") { NSWorkspace.shared.activateFileViewerSelecting([state.repository.fileURL]) }
                    }.buttonStyle(SettingsButtonStyle())
                    Divider()
                    SettingsHelpText("使用 AI 整理成果或授权检查网页时，相关内容会发送给你选择的 AI 服务商。")
                    Button("查看 AI 的使用与隐私说明", action: openAI).buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }
            HStack {
                Text("番茄小记 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("退出应用") { NSApp.terminate(nil) }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
            }.padding(.horizontal, 3)
        }
    }
}

extension AppState {
    func settingBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in
            var next = self.settings
            next[keyPath: keyPath] = value
            _ = self.updateSettings(next)
        })
    }
}
