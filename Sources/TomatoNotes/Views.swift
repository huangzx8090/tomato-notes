import AppKit
import SwiftUI
import TomatoCore

enum PanelTab: String, CaseIterable {
    case focus = "专注", today = "今日", notes = "便签", settings = "设置"
    var symbol: String {
        switch self {
        case .focus: "timer"
        case .today: "sun.max"
        case .notes: "note.text"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct MainPanel: View {
    @ObservedObject var state: AppState
    var createNote: () -> Void
    var openNote: (UUID) -> Void
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    var panelHeight: CGFloat = 660
    @ViewState private var tab: PanelTab = .focus
    @ViewState private var todoDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 4) {
                ForEach(PanelTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 11, weight: .medium))
                            Text(item.rawValue).font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(tab == item ? Theme.accent : Theme.secondary)
                        .background(tab == item ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(4).background(Theme.border.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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
                        case .today: TodayView(state: state, startFocus: { tab = .focus })
                        case .notes: NotesListView(state: state, createNote: createNote, openNote: openNote)
                        case .settings:
                            SettingsView(state: state, testReminder: testReminder,
                                         requestNotifications: requestNotifications)
                        }
                    }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 22)
                }.scrollIndicators(.hidden)
            }
            if let message = state.feedback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { state.feedback = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("关闭提示")
                }
                .font(.system(size: 11)).foregroundStyle(Theme.primary)
                .padding(12).background(Theme.accentSoft.opacity(0.8))
            }
        }
        .frame(width: 420, height: panelHeight)
        .background(Theme.background)
        .foregroundStyle(Theme.primary)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "zh_CN"))
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

            HStack(spacing: 0) {
                MetricView(value: "\(Int(state.summary(for: state.todayKey).focusSeconds / 60))", label: "今日专注 / 分钟")
                Rectangle().fill(Theme.border).frame(width: 1, height: 30)
                MetricView(value: "\(state.summary(for: state.todayKey).completedSessions)", label: "完整番茄 / 轮")
            }.padding(.vertical, 15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))

            TodoSection(state: state, draft: $todoDraft)
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

private struct TodoSection: View {
    @ObservedObject var state: AppState
    @Binding var draft: String

    var body: some View {
        let todos = state.summary(for: state.todayKey).todos
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日待办").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(todos.filter(\.isCompleted).count) / \(todos.count)")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            if todos.isEmpty {
                Text("随手记一件小事。")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 6)
            }
            ForEach(todos) { todo in TodoRow(todo: todo, state: state) }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(Theme.accent).font(.system(size: 12))
                TextField("输入一件小事，按回车保存", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 12)).onSubmit(save)
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: save) { Image(systemName: "arrow.turn.down.left") }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityLabel("保存待办")
                }
            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 0.7))
        }
    }

    private func save() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.addTodo(draft)
        draft = ""
    }
}

private struct TodoRow: View {
    let todo: TodoItem
    @ObservedObject var state: AppState
    @ViewState private var editing = false
    @ViewState private var draft = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if editing {
                TextField("待办文字", text: $draft).textFieldStyle(.plain).font(.system(size: 13))
                    .onSubmit { state.updateTodo(todo.id, text: draft); editing = false }
                    .onExitCommand { editing = false }
            } else {
                Text(todo.text).font(.system(size: 13))
                    .strikethrough(todo.isCompleted, color: Theme.secondary)
                    .foregroundStyle(todo.isCompleted ? Theme.secondary : Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) { draft = todo.text; editing = true }
            }
            Spacer(minLength: 0)
            Button { state.toggleTodo(todo.id) } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(todo.isCompleted ? Theme.green : Theme.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(todo.isCompleted ? "取消完成：\(todo.text)" : "完成：\(todo.text)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("修改文字") { draft = todo.text; editing = true }
        }
    }
}

private struct TodayView: View {
    @ObservedObject var state: AppState
    var startFocus: () -> Void
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
            if !summary.sessions.isEmpty {
                PaperCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("专注记录").font(.system(size: 14, weight: .semibold))
                        ForEach(summary.sessions) { session in
                            let seconds = state.data.intervals.filter { $0.sessionID == session.id && $0.localDay == day }
                                .reduce(0) { $0 + $1.seconds }
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(session.completed ? Theme.green : Theme.accentSoft)
                                    .frame(width: 7, height: 7).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(session.startedAt, style: .time)
                                        Text("—")
                                        if let end = session.endedAt { Text(end, style: .time) }
                                        else { Text("进行中") }
                                    }.font(.system(size: 12).monospacedDigit())
                                    Text(session.endedAt == nil ? "进行中 · 本日 \(durationLabel(seconds))" :
                                            "\(session.completed ? "完整番茄" : "提前结束") · 本日 \(durationLabel(seconds))")
                                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
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

private struct NotesListView: View {
    @ObservedObject var state: AppState
    var createNote: () -> Void
    var openNote: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("桌边的便签").font(.system(size: 19, weight: .semibold))
                    Text("记下想法，让它留在眼前。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button(action: createNote) { Image(systemName: "plus").frame(width: 28, height: 28) }
                    .buttonStyle(SubtleButtonStyle()).accessibilityLabel("新建便签")
            }
            if state.data.notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Theme.accent)
                    Text("给零散的想法，一张小小的纸。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Button("新建第一张便签", action: createNote).buttonStyle(SubtleButtonStyle())
                }.frame(maxWidth: .infinity).padding(.vertical, 50)
            }
            ForEach(state.data.notes.sorted { $0.updatedAt > $1.updatedAt }) { note in
                Button { openNote(note.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(note.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Spacer()
                            Image(systemName: note.isOpen ? "pin.fill" : "arrow.up.right")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                        Text(note.text.isEmpty ? "一张等待落笔的纸。" : note.text)
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Text(note.isOpen ? "已在桌面打开" : "已收起 · 点击恢复")
                            Spacer()
                            Text(note.updatedAt, format: .dateTime.month().day())
                        }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }.padding(17).background(Color(nsColor: Theme.notePaper), in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
            Text("便签自动保存、跨日保留。关闭窗口后可在这里重新打开；选中文字或全文可按行转为今天的待办。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var state: AppState
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    @ViewState private var focus = ""
    @ViewState private var shortBreak = ""
    @ViewState private var longBreak = ""
    @ViewState private var every = ""
    @ViewState private var timerKey = Hotkey(letter: "P")
    @ViewState private var todoKey = Hotkey(letter: "T")
    @ViewState private var noteKey = Hotkey(letter: "N")
    @ViewState private var validation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaperCard {
                VStack(alignment: .leading, spacing: 13) {
                    Text("专注的节奏").font(.system(size: 14, weight: .semibold))
                    numberRow("专注", value: $focus, hint: "1–180 分钟")
                    numberRow("短休息", value: $shortBreak, hint: "1–60 分钟")
                    numberRow("长休息", value: $longBreak, hint: "1–120 分钟")
                    numberRow("长休息间隔", value: $every, hint: "2–8 轮")
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
                    Text("使用 A–Z 字母键。在其他 App 中也可使用；占用或重复时会提示换键。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("番茄小记 1.0 · macOS 14+")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                Text("锁屏与睡眠时暂停，回来后由你继续。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                HStack {
                    Button("查看本地数据") { NSWorkspace.shared.activateFileViewerSelecting([state.repository.fileURL]) }
                    Spacer()
                    Button("退出番茄小记") { NSApp.terminate(nil) }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }.padding(.horizontal, 3).padding(.bottom, 6)
        }
        .toggleStyle(.switch).tint(Theme.green)
        .onAppear {
            focus = String(state.settings.focusMinutes)
            shortBreak = String(state.settings.shortBreakMinutes)
            longBreak = String(state.settings.longBreakMinutes)
            every = String(state.settings.longBreakEvery)
            timerKey = state.settings.timerHotkey
            todoKey = state.settings.todoHotkey
            noteKey = state.settings.noteHotkey
        }
    }

    private func numberRow(_ title: String, value: Binding<String>, hint: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            TextField("", text: value).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .font(.system(size: 12).monospacedDigit()).frame(width: 39).padding(7)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 7))
            Text(hint).font(.system(size: 10)).foregroundStyle(Theme.secondary).frame(width: 85, alignment: .leading)
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
        guard let focusValue = Int(focus), (1...180).contains(focusValue),
              let shortValue = Int(shortBreak), (1...60).contains(shortValue),
              let longValue = Int(longBreak), (1...120).contains(longValue),
              let everyValue = Int(every), (2...8).contains(everyValue) else {
            validation = "请填写范围内的整数，不能留空。"
            return
        }
        var settings = state.settings
        settings.focusMinutes = focusValue
        settings.shortBreakMinutes = shortValue
        settings.longBreakMinutes = longValue
        settings.longBreakEvery = everyValue
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
        }.padding(22).frame(width: 380).background(Theme.background).preferredColorScheme(.light)
            .onAppear { focused = true }.onExitCommand(perform: onClose)
    }
}
