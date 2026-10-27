import AppKit
import SwiftUI
import TomatoCore

struct MainPanel: View {
    @ObservedObject var state: AppState
    var createNote: () -> Void
    var openNote: (UUID) -> Void
    var continueNote: (UUID) -> Void
    var deleteNote: (UUID) -> Void
    var exportNote: (UUID) -> Void
    var openWork: (WorkScope) -> Void
    var openHistorySearch: () -> Void
    var openFocusHeatmap: () -> Void
    var testReminder: () -> Void
    var requestNotifications: () -> Void
    var panelHeight: CGFloat = 660
    @ViewState private var tab: PanelTab = .focus
    @ViewState private var todoDraft = ""
    @ViewState private var todayDate = Date()
    @ViewState private var highlightedTodoID: UUID?
    @ViewState private var showsNoteHistory = false
    @ViewState private var settingsPage: SettingsPage = .overview
    @ViewState private var settingsHaveUnsavedChanges = false
    @ViewState private var showingDiscardSettings = false
    @ViewState private var pendingTab: PanelTab?
    @ViewState private var pendingSettingsPage: SettingsPage?

    var body: some View {
        VStack(spacing: 0) {
            AppBrandHeader(settingsSelected: tab == .settings, openSettings: { requestTab(.settings) })
            if !state.repository.isSharedLibrary { LocalDataStatusView(state: state) }
            PanelNavigation(selection: Binding(get: { tab }, set: requestTab))
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
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(spacing: 18) {
                            switch tab {
                            case .focus: focus
                            case .todos:
                                TodoPage(todos: state.data.todos.filter { $0.effectiveScheduledDay == state.todayKey },
                                         allTodos: state.data.todos, day: state.todayKey,
                                         draft: $todoDraft, addTodo: state.addTodo, toggleTodo: state.toggleTodo,
                                         updateTodo: state.updateTodo, deleteTodo: state.deleteTodo,
                                         scheduleCarryover: { _ = state.scheduleTodosForToday($0) },
                                         undoCarryover: state.undoTodoSchedule)
                            case .today:
                                TodayView(state: state, selectedDate: $todayDate, highlightedTodoID: $highlightedTodoID,
                                          startFocus: { tab = .focus }, openWork: openWork,
                                          openHistorySearch: openHistorySearch, openFocusHeatmap: openFocusHeatmap)
                            case .notes:
                                NotesListView(notes: state.data.notes, today: state.todayKey,
                                              showsHistory: $showsNoteHistory, createNote: createNote,
                                              openNote: openNote, continueNote: continueNote, deleteNote: deleteNote,
                                              exportNote: exportNote)
                            case .ranking:
                                LeaderboardPreviewView()
                            case .settings:
                                SettingsView(state: state, page: $settingsPage, hasUnsavedChanges: $settingsHaveUnsavedChanges,
                                             openFocus: { navigate(to: .focus) }, testReminder: testReminder,
                                             requestNotifications: requestNotifications)
                            }
                        }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 22).id("mainPanel.top")
                    }.scrollIndicators(.hidden).id(tab == .notes && showsNoteHistory ? "notes.history" : tab.rawValue)
                        .onChange(of: settingsPage) { _, _ in scroll.scrollTo("mainPanel.top", anchor: .top) }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TomatoNotes.showAISettings"))) { _ in
            navigate(to: .settings, settings: .ai)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TomatoNotes.showSettings"))) { _ in
            navigate(to: .settings, settings: .overview)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TomatoNotes.showFocus"))) { _ in navigate(to: .focus) }
        .onChange(of: state.historyNavigationRequest) { _, request in
            guard let request, let date = LocalTime.date(forDayKey: request.day) else { return }
            highlightedTodoID = request.todoID
            todayDate = date
            navigate(to: .today)
        }
        .confirmationDialog("还有未保存的修改", isPresented: $showingDiscardSettings, titleVisibility: .visible) {
            Button("放弃修改并离开", role: .destructive) {
                settingsHaveUnsavedChanges = false
                if let pendingSettingsPage { settingsPage = pendingSettingsPage }
                if let pendingTab { tab = pendingTab }
                pendingTab = nil; pendingSettingsPage = nil
            }
            Button("继续编辑", role: .cancel) { pendingTab = nil; pendingSettingsPage = nil }
        } message: {
            Text("保存后再离开，可以保留刚才填写的内容。")
        }
    }

    private func requestTab(_ destination: PanelTab) {
        navigate(to: destination, settings: destination == .settings ? .overview : nil)
    }

    private func navigate(to destination: PanelTab, settings destinationPage: SettingsPage? = nil) {
        if tab == .settings && settingsHaveUnsavedChanges {
            pendingTab = destination; pendingSettingsPage = destinationPage; showingDiscardSettings = true
        } else {
            if let destinationPage { settingsPage = destinationPage }
            tab = destination
        }
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
    @Binding var selectedDate: Date
    @Binding var highlightedTodoID: UUID?
    var startFocus: () -> Void
    var openWork: (WorkScope) -> Void
    var openHistorySearch: () -> Void
    var openFocusHeatmap: () -> Void
    @ViewState private var showAllApps = false

    var body: some View {
        let day = LocalTime.dayKey(selectedDate)
        let summary = state.summary(for: day)
        VStack(alignment: .leading, spacing: 18) {
            FocusHeatmapCompactView(
                state: state,
                selectedDay: day,
                onSelectDay: { selected in
                    if let date = LocalTime.date(forDayKey: selected) {
                        selectedDate = date
                        highlightedTodoID = nil
                    }
                },
                onShowAll: openFocusHeatmap
            )
            HStack {
                Button { moveDay(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 26).contentShape(Rectangle())
                }.accessibilityLabel("前一天")
                Spacer()
                Text(selectedDate, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: openHistorySearch) {
                    Image(systemName: "magnifyingglass").frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("搜索历史").help("搜索历史记录")
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
                            let status = todo.completionDay.map { $0 == day ? "当日完成" : "于 \($0) 完成" }
                                ?? (todo.effectiveScheduledDay > day ? "后续已结转到 \(todo.effectiveScheduledDay)" : "当日未完成")
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(todo.text).strikethrough(todo.completionDay == day)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: todo.completionDay == day ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(todo.completionDay == day ? Theme.green : Theme.secondary)
                                }
                                Text("原始日期 \(todo.localDay) · \(status)")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .background(todo.id == highlightedTodoID ? Theme.accentSoft : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(todo.id == highlightedTodoID ? Theme.accent.opacity(0.8) : .clear, lineWidth: 1.2))
                        }
                        Text("保留当天安排；结转和完成日期会单独标注。")
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
            highlightedTodoID = nil
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
