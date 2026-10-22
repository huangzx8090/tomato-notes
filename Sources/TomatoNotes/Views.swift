import AppKit
import SwiftUI
import TomatoCore

struct MainPanel: View {
    @ObservedObject var state: AppState
    var createNote: () -> Void
    var openNote: (UUID) -> Void
    var continueNote: (UUID) -> Void
    var deleteNote: (UUID) -> Void
    var openWork: (WorkScope) -> Void
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    var panelHeight: CGFloat = 660
    @ViewState private var tab: PanelTab = .focus
    @ViewState private var todoDraft = ""
    @ViewState private var showsNoteHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            PanelNavigation(selection: $tab)
            .padding(.horizontal, 22).padding(.bottom, 12)

            if let error = state.errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    Label("本地数据需要检查", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 16, weight: .semibold))
                    Text(error).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Button("在 Finder 中显示数据文件") {
                        NSWorkspace.shared.activateFileViewerSelecting([state.repository.fileURL])
                    }.buttonStyle(SubtleButtonStyle())
                }.padding(24)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        switch tab {
                        case .focus: focus
                        case .todos:
                            TodoPage(todos: state.summary(for: state.todayKey).todos, day: state.todayKey,
                                     draft: $todoDraft, addTodo: state.addTodo, toggleTodo: state.toggleTodo,
                                     updateTodo: state.updateTodo, deleteTodo: state.deleteTodo)
                        case .today: TodayView(state: state, startFocus: { tab = .focus }, openWork: openWork)
                        case .notes:
                            NotesListView(notes: state.data.notes, today: state.todayKey,
                                          showsHistory: $showsNoteHistory, createNote: createNote,
                                          openNote: openNote, continueNote: continueNote, deleteNote: deleteNote)
                        case .settings:
                            SettingsView(state: state, testReminder: testReminder,
                                         requestNotifications: requestNotifications)
                        }
                    }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 22)
                }.scrollIndicators(.hidden).id(tab == .notes && showsNoteHistory ? "notes.history" : tab.rawValue)
            }
            if let message = state.lastDeletedTodo.map({ "已删除：\($0.text)" }) ?? state.feedback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: state.lastDeletedTodo == nil ? "info.circle" : "trash")
                    Text(message).lineLimit(state.lastDeletedTodo == nil ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let deleted = state.lastDeletedTodo {
                        Button("撤销", action: state.undoTodoDeletion)
                            .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(Theme.accent)
                            .help("撤销删除：\(deleted.text)")
                            .accessibilityLabel("撤销删除：\(deleted.text)")
                            .accessibilityIdentifier("todos.undoDelete")
                    }
                    Button(action: state.dismissFeedback) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("关闭提示")
                }
                .font(.system(size: 11)).foregroundStyle(Theme.primary)
                .padding(12).background(Theme.accentSoft.opacity(0.8))
            }
        }
        .frame(width: 420, height: panelHeight)
        .background(Theme.background)
        .foregroundStyle(Theme.primary)
        .preferredColorScheme(state.settings.appearance.colorScheme)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.glassControlsEnabled, state.settings.glassControlsEnabled)
        .onChange(of: tab) { _, newTab in
            if newTab == .notes { showsNoteHistory = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TomatoNotes.showAISettings"))) { _ in tab = .settings }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TomatoNotes.showFocus"))) { _ in tab = .focus }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("番茄小记").font(.system(size: 16, weight: .semibold))
                Text("把时间留给在意的事").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(Date(), format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.secondary)
        }.padding(.horizontal, 23).padding(.top, 20).padding(.bottom, 18)
    }

    private var focus: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(state.timer.stage == .focus ? Theme.accent : Theme.green).frame(width: 5, height: 5)
                    Text(state.statusText).font(.system(size: 12, weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.center)
                }.foregroundStyle(Theme.secondary)
                Text(state.remainingText)
                    .font(.system(size: 60, weight: .regular, design: .rounded).monospacedDigit())
                    .tracking(-2).contentTransition(.identity)
                    .accessibilityLabel("剩余 \(state.remainingText)")
                HStack(spacing: 6) {
                    ForEach(0..<state.settings.longBreakEvery, id: \.self) { index in
                        Capsule().fill(index < state.timer.completedInSet ? Theme.accent : Theme.border)
                            .frame(width: 14, height: 4)
                    }
                    Text("本组 \(state.timer.completedInSet) / \(state.settings.longBreakEvery) 轮")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).padding(.leading, 4)
                }
                Text(timerCaption).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
                if (state.timer.phase == .idle && state.timer.stage == .focus) ||
                    (state.timer.phase == .completed && state.timer.nextStage == .focus) {
                    FocusGoalPicker(state: state).padding(.top, 6)
                } else if let id = state.timer.sessionID, let goal = state.data.sessions.first(where: { $0.id == id })?.goal {
                    Text(goal).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        .multilineTextAlignment(.center).padding(.top, 4)
                }
                Button(action: state.startOrPause) {
                    Label(state.primaryAction, systemImage: state.timer.phase == .running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(green: state.timer.stage != .focus))
                .padding(.horizontal, 46).padding(.top, 5)
                if state.timer.phase == .running || state.timer.phase == .paused {
                    Button(state.timer.stage == .focus ? "提前结束这一轮" : "跳过剩余休息", action: state.endEarlyOrSkip)
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.top, 1)
                } else if state.timer.phase == .completed && state.timer.nextStage != .focus {
                    Button("跳过这次休息", action: state.endEarlyOrSkip)
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 14)

            if let id = state.timer.sessionID ?? state.data.sessions.last?.id,
               let progress = SessionProgress.build(sessionID: id, from: state.data), progress.focusSeconds > 0 {
                SessionProgressCard(state: state, progress: progress, openDetails: { openWork(.session(id)) })
            }

            HStack(spacing: 0) {
                MetricView(value: "\(Int(state.summary(for: state.todayKey).focusSeconds / 60))", label: "今日专注 / 分钟")
                Rectangle().fill(Theme.border).frame(width: 1, height: 30)
                MetricView(value: "\(state.summary(for: state.todayKey).completedSessions)", label: "完整番茄 / 轮")
            }.padding(.vertical, 15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))

            FocusGuardCard(state: state, controller: state.guardController)
        }
    }

    private var timerCaption: String {
        switch state.timer.phase {
        case .idle: "留一点时间，专心做一件事。"
        case .running: state.timer.stage == .focus ? "慢慢来，把注意力放在眼前。" : "离开屏幕，给自己一点空白。"
        case .paused: "刚才已暂停，准备好后继续。"
        case .completed: state.timer.nextStage == .focus ? "休息结束了，准备好再开始。" : "这一轮完成了，休息一下吧。"
        }
    }
}

private struct MetricView: View {
    var value: String
    var label: String
    var body: some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 25, weight: .medium, design: .rounded).monospacedDigit())
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct TodayView: View {
    @ObservedObject var state: AppState
    var startFocus: () -> Void
    var openWork: (WorkScope) -> Void
    @ViewState private var selectedDate = Date()
    @ViewState private var showAllApps = false

    var body: some View {
        let day = LocalTime.dayKey(selectedDate)
        let summary = state.summary(for: day)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { moveDay(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 26).contentShape(Rectangle())
                }.accessibilityLabel("前一天")
                Spacer()
                Text(selectedDate, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button { moveDay(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 24, height: 26).contentShape(Rectangle())
                }.accessibilityLabel("后一天").help(Calendar.current.isDateInToday(selectedDate) ? "今天已是最近日期" : "查看后一天")
                    .disabled(Calendar.current.isDateInToday(selectedDate))
            }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            if !Calendar.current.isDateInToday(selectedDate) {
                Button("回到今天") { selectedDate = Date() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Theme.accent).frame(maxWidth: .infinity)
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("AI 每日回顾", systemImage: "sparkles").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if state.generatingScopes.contains(WorkScope.day(day).key) { ProgressView().controlSize(.small) }
                    }
                    if let review = state.workRecord(for: .day(day))?.summary {
                        Text((review.content.activities + review.content.outcomes).prefix(3).joined(separator: "\n"))
                            .font(.system(size: 12)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        Text("\(review.generatedAt.formatted(date: .omitted, time: .shortened)) 生成")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    } else {
                        Text("让 AI 把这一天做过的事、各轮成果和待继续事项整理出来。")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = state.reviewErrors[WorkScope.day(day).key] {
                        Text(error).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    Button { openWork(.day(day)) } label: {
                        Label(state.workRecord(for: .day(day))?.summary == nil ? "补充记录并让 AI 汇总" : "查看完整 AI 回顾", systemImage: "arrow.up.right")
                    }.buttonStyle(SubtleButtonStyle())
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(Calendar.current.isDateInToday(selectedDate) ? "今天留下的进展" : "这一天留下的进展")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "sun.max").foregroundStyle(Theme.accent)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(summary.focusSeconds / 60))").font(.system(size: 42, weight: .medium, design: .rounded))
                        Text("分钟专注").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    HStack(spacing: 18) {
                        Label("完整 \(summary.completedSessions) 轮", systemImage: "checkmark.seal")
                        Label("待办 \(summary.completedTodos.count) / \(summary.todos.count)", systemImage: "checklist")
                    }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if summary.earlySessions > 0 {
                        Text("另有 \(summary.earlySessions) 轮提前结束，投入时长已计入。")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Text(summary.sentence).font(.system(size: 12)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Theme.greenSoft, in: RoundedRectangle(cornerRadius: 10))
                    if summary.focusSeconds == 0 && Calendar.current.isDateInToday(selectedDate) {
                        Button("去开始第一轮", action: startFocus).buttonStyle(SubtleButtonStyle())
                    }
                }
            }
            if !summary.sessions.isEmpty {
                ProgressTimeline(state: state, day: day, sessions: summary.sessions, openWork: openWork)
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("专注时使用的 App").font(.system(size: 14, weight: .semibold))
                    Text("仅记录前台停留时长").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    if !state.settings.recordingEnabled && Calendar.current.isDateInToday(selectedDate) {
                        Label("App 使用记录已关闭", systemImage: "pause.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    if summary.apps.isEmpty && summary.focusSeconds == 0 {
                        Text("开始专注后，使用过的 App 会出现在这里。")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    ForEach(showAllApps ? summary.apps : Array(summary.apps.prefix(3))) { app in
                        AppUsageRow(app: app, total: summary.focusSeconds)
                    }
                    if summary.apps.count > 3 {
                        Button(showAllApps ? "收起明细" : "查看其余 \(summary.apps.count - 3) 个 App") { showAllApps.toggle() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    if summary.unattributedSeconds > 0 { supplemental("未归属时长", seconds: summary.unattributedSeconds) }
                    if summary.disabledSeconds > 0 { supplemental("未记录时长", seconds: summary.disabledSeconds) }
                }
            }
            if !summary.todos.isEmpty {
                PaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当天待办").font(.system(size: 14, weight: .semibold))
                        ForEach(summary.todos) { todo in
                            HStack(alignment: .top, spacing: 8) {
                                Text(todo.text).strikethrough(todo.isCompleted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isCompleted ? Theme.green : Theme.secondary)
                            }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("历史日期只读，待办不会自动结转。")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private func moveDay(_ amount: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: amount, to: selectedDate) {
            selectedDate = date
            showAllApps = false
        }
    }

    private func supplemental(_ title: String, seconds: Double) -> some View {
        HStack { Text(title); Spacer(); Text(durationLabel(seconds)) }
            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
    }
}

private struct AppUsageRow: View {
    let app: AppTotal
    let total: Double
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                } else { Image(systemName: "app").frame(width: 20).foregroundStyle(Theme.secondary) }
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text(durationLabel(app.seconds)).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            GeometryReader { geometry in
                Capsule().fill(Theme.border.opacity(0.5))
                Capsule().fill(Theme.green.opacity(0.7))
                    .frame(width: max(2, geometry.size.width * min(1, app.seconds / max(1, total))))
            }.frame(height: 3)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var state: AppState
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    @ViewState private var focus = 25
    @ViewState private var shortBreak = 5
    @ViewState private var longBreak = 15
    @ViewState private var every = 4
    @ViewState private var timerKey = Hotkey(letter: "P")
    @ViewState private var todoKey = Hotkey(letter: "T")
    @ViewState private var noteKey = Hotkey(letter: "N")
    @ViewState private var validation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaperCard {
                VStack(alignment: .leading, spacing: 11) {
                    Text("外观").font(.system(size: 14, weight: .semibold))
                    Picker("配色", selection: Binding(get: { state.settings.appearance }, set: { value in
                        var settings = state.settings; settings.appearance = value; _ = state.updateSettings(settings)
                    })) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityLabel("外观模式")
                    Text("浅色是暖纸，深色是夜色胡桃；跟随系统会自动切换。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Toggle("按钮玻璃效果", isOn: settingBinding(\.glassControlsEnabled))
                        .font(.system(size: 12)).tint(Theme.accent)
                    Text("让按钮与顶部切换栏呈现流动玻璃。背景始终保留暖色纸感，关闭后按钮也使用纸感样式。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ReviewSettingsSection(state: state, requestNotifications: requestNotifications)
            FocusGuardSettingsSection(state: state)
            PaperCard {
                VStack(alignment: .leading, spacing: 13) {
                    Text("专注的节奏").font(.system(size: 14, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        RotaryDial(title: "专注", unit: "分钟", bounds: 1...180, tint: Theme.accent, value: $focus)
                        RotaryDial(title: "短休息", unit: "分钟", bounds: 1...60, tint: Theme.green, value: $shortBreak)
                        RotaryDial(title: "长休息", unit: "分钟", bounds: 1...120, tint: Theme.green, value: $longBreak)
                        RotaryDial(title: "长休息间隔", unit: "轮", bounds: 2...8, tint: Color(hex: 0x9A7D54), value: $every)
                    }.padding(.vertical, 6)
                    Text("转动旋钮调节，− / ＋ 精确微调。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    if let validation { Text(validation).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    Button("保存计时参数", action: saveDurations).buttonStyle(SubtleButtonStyle())
                    Text("当前阶段保持原时长，新参数从后续阶段生效。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("温和地提醒").font(.system(size: 14, weight: .semibold))
                    Toggle("一次提示音", isOn: settingBinding(\.soundEnabled)).font(.system(size: 12))
                    Toggle("macOS 系统通知", isOn: settingBinding(\.notificationsEnabled)).font(.system(size: 12))
                    Text(state.notificationStatus).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("测试提醒", action: testReminder).buttonStyle(SubtleButtonStyle())
                        Button("通知权限", action: requestNotifications).buttonStyle(SubtleButtonStyle())
                    }
                    Button("打开系统通知设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("打开番茄小记").font(.system(size: 14, weight: .semibold))
                    Toggle("在 Dock 中显示图标", isOn: settingBinding(\.showDockIcon)).font(.system(size: 12))
                    Text("菜单栏始终可用；开启后也可点击 Dock 图标打开面板。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("合盖与外接屏").font(.system(size: 14, weight: .semibold))
                    Toggle("合盖外接屏时继续计时", isOn: settingBinding(\.allowClamshellWithExternalDisplay))
                        .font(.system(size: 12))
                    Text("外接显示器工作时可继续；锁屏或系统睡眠仍会暂停，唤醒后需主动继续。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("前台 App 记录").font(.system(size: 14, weight: .semibold))
                    Toggle("仅在专注运行时记录", isOn: settingBinding(\.recordingEnabled)).font(.system(size: 12))
                    Text("只保存 App 名称和停留时长。关闭后对应专注时间标记为“未记录”。所有数据保存在本机。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("随手可用的快捷键").font(.system(size: 14, weight: .semibold))
                    HotkeyRow(title: "开始 / 暂停", value: $timerKey)
                    HotkeyRow(title: "快速待办", value: $todoKey)
                    HotkeyRow(title: "呼出便签", value: $noteKey)
                    Button("保存快捷键", action: saveHotkeys).buttonStyle(SubtleButtonStyle())
                    Text("使用 A–Z 字母键。在其他 App 中也可使用；检测到占用或重复时会提示。部分应用监听的组合无法由系统查询，冲突时请手动换键。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("番茄小记 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")) · macOS 14+")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                Text("锁屏与睡眠时暂停，回来后由你继续。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                HStack {
                    Button("查看本地数据") { NSWorkspace.shared.activateFileViewerSelecting([state.repository.fileURL]) }
                    Button("备份数据") {
                        if let url = state.backupData() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Spacer()
                    Button("退出番茄小记") { NSApp.terminate(nil) }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }.padding(.horizontal, 3).padding(.bottom, 6)
        }
        .toggleStyle(.switch).tint(Theme.green)
        .onAppear {
            focus = state.settings.focusMinutes
            shortBreak = state.settings.shortBreakMinutes
            longBreak = state.settings.longBreakMinutes
            every = state.settings.longBreakEvery
            timerKey = state.settings.timerHotkey
            todoKey = state.settings.todoHotkey
            noteKey = state.settings.noteHotkey
        }
    }

    private func settingBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.settings[keyPath: keyPath] }, set: { value in
            var settings = state.settings
            settings[keyPath: keyPath] = value
            _ = state.updateSettings(settings)
        })
    }

    private func saveDurations() {
        var settings = state.settings
        settings.focusMinutes = focus
        settings.shortBreakMinutes = shortBreak
        settings.longBreakMinutes = longBreak
        settings.longBreakEvery = every
        if state.updateSettings(settings) { validation = nil }
    }

    private func saveHotkeys() {
        var settings = state.settings
        settings.timerHotkey = timerKey
        settings.todoHotkey = todoKey
        settings.noteHotkey = noteKey
        _ = state.updateSettings(settings)
    }
}

private struct HotkeyRow: View {
    let title: String
    @Binding var value: Hotkey
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(title, isOn: $value.enabled).font(.system(size: 12))
            HStack(spacing: 8) {
                Picker("组合键", selection: $value.modifier) {
                    Text("⌃ Control + ⌥ Option").tag("controlOption")
                    Text("⌘ Command + ⇧ Shift").tag("commandShift")
                    Text("⌃ Control + ⌘ Command").tag("controlCommand")
                }.labelsHidden().frame(maxWidth: .infinity)
                TextField("P", text: $value.letter).textFieldStyle(.plain).multilineTextAlignment(.center)
                    .font(.system(size: 12, weight: .medium)).frame(width: 27).padding(6)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
            }.disabled(!value.enabled)
        }
    }
}

struct QuickTodoView: View {
    var onSave: (String) -> Void
    var onClose: () -> Void
    @ViewState private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("随手记一件小事", systemImage: "checklist")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
            TextField("今天想做什么？", text: $text).textFieldStyle(.plain).font(.system(size: 15))
                .focused($focused).padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(text)
                }
            Text("Enter 保存到今天 · Esc 返回")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.padding(22).frame(width: 380).background(Theme.background).foregroundStyle(Theme.primary)
            .onAppear { focused = true }.onExitCommand(perform: onClose)
    }
}
