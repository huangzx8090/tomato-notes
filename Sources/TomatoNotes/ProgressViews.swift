import SwiftUI
import TomatoCore

struct FocusGoalPicker: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("这轮想推进什么").font(.system(size: 12, weight: .medium))
                Spacer()
                Menu {
                    ForEach(state.summary(for: state.todayKey).todos.filter { !$0.isCompleted }) { todo in
                        Button(todo.text) { state.focusGoalDraft = String(todo.text.prefix(300)) }
                    }
                } label: { Label("从待办选择", systemImage: "checklist") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
                    .disabled(state.summary(for: state.todayKey).todos.allSatisfy(\.isCompleted))
            }
            TextField("可选，直接开始也会留下投入记录", text: $state.focusGoalDraft)
                .textFieldStyle(.plain).font(.system(size: 12))
                .accessibilityLabel("本轮专注目标（可选）")
                .padding(11).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 0.7))
                .onChange(of: state.focusGoalDraft) { _, value in
                    if value.count > 300 { state.focusGoalDraft = String(value.prefix(300)) }
                }
            if state.settings.focusGuard.enabled, state.settings.focusGuard.reuseLastPlan,
               state.settings.focusGuard.hasLastPlan, state.focusGoalDraft.isEmpty {
                Text("本轮将沿用：\(state.settings.focusGuard.lastGoal)")
                    .font(.system(size: 10)).lineLimit(2)
            }
        }.frame(maxWidth: .infinity).foregroundStyle(Theme.secondary)
    }
}

struct SessionProgressCard: View {
    @ObservedObject var state: AppState
    let progress: SessionProgress
    var showSummaryPreview = true
    var openDetails: (() -> Void)?

    var body: some View {
        let scope = WorkScope.session(progress.session.id)
        let record = state.workRecord(for: scope)
        let summaryIsCurrent = record?.summary?.contextDigest == ReviewContextBuilder.build(for: scope, from: state.data).digest
        let outcomes = showSummaryPreview && summaryIsCurrent ? (record?.summary?.content.outcomes ?? []) : []
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(progress.session.endedAt == nil ? "正在留下进展" : "这一轮，留下了进展", systemImage: "leaf")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                    Spacer()
                    Text(progress.session.startedAt, style: .time)
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.secondary)
                }
                Text(progress.title).font(.system(size: 17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label("投入 \(durationLabel(progress.focusSeconds))", systemImage: "clock")
                    if !progress.completedTodos.isEmpty {
                        Label("完成 \(progress.completedTodos.count) 项待办", systemImage: "checkmark.circle")
                    }
                }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if !outcomes.isEmpty {
                    ForEach(Array(outcomes.prefix(2).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(progress.completedTodos.prefix(3)) { todo in
                        Label(todo.text, systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(Theme.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if state.generatingScopes.contains(scope.key) {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("AI 正在后台整理，可以先休息。")
                    }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                } else if let error = state.reviewErrors[scope.key] {
                    Text("投入已保存，AI 暂未整理好：\(error)")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(summaryIsCurrent ? "AI 已整理 · 可查看原始记录核对" : "投入已自动记录，文字与图片随时补充。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                if let openDetails {
                    Button(action: openDetails) { Label("查看进展 / 补充图片", systemImage: "arrow.up.right") }
                        .buttonStyle(SubtleButtonStyle())
                }
            }
        }
    }
}

struct ProgressTimeline: View {
    @ObservedObject var state: AppState
    let day: String
    let sessions: [FocusSession]
    var openWork: (WorkScope) -> Void

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("时间都变成了什么", systemImage: "leaf").font(.system(size: 14, weight: .semibold))
                ForEach(sessions) { session in
                    if let progress = SessionProgress.build(sessionID: session.id, from: state.data, day: day) {
                        Button { openWork(.session(session.id)) } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Circle().fill(session.completed ? Theme.green : Theme.accent)
                                    .frame(width: 7, height: 7).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(progress.title).font(.system(size: 13, weight: .medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · 本日投入 \(durationLabel(progress.focusSeconds)) · \(session.endedAt == nil ? "进行中" : (session.completed ? "完整番茄" : "提前结束"))")
                                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                    if !progress.completedTodos.isEmpty {
                                        Text("勾选完成：" + progress.completedTodos.map(\.text).joined(separator: "、"))
                                            .font(.system(size: 11)).foregroundStyle(Theme.green).lineLimit(2)
                                    }
                                    if state.generatingScopes.contains(WorkScope.session(session.id).key) {
                                        Text("AI 整理中…").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel("查看进展：\(progress.title)")
                    }
                }
                Text("每一段投入都自动留下；点击可看详情或补充图片。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
