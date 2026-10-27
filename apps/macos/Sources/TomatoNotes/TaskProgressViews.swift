import SwiftUI
import TomatoCore
import TomatoSystem

private enum ProgressChoice: String, CaseIterable {
    case started = "刚开始", progressing = "有进展", finished = "已完成", blocked = "遇到问题"
    var sentence: String {
        switch self {
        case .started: "这轮刚开始推进。"
        case .progressing: "这轮取得了一些进展。"
        case .finished: "这轮已完成这项待办。"
        case .blocked: "这轮推进时遇到问题。"
        }
    }
}

private enum NextStepChoice: String, CaseIterable {
    case continueWork = "继续推进", review = "检查成果", help = "寻求帮助", undecided = "待确认"
    var sentence: String { "下一步：" + rawValue + "。" }
}

struct TaskProgressCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var reminders: ReminderTasksController
    let sessionID: UUID
    let task: TaskReference
    let focusSeconds: Double
    let ended: Bool
    var configureAI: () -> Void
    @ViewState private var draft = ""
    @ViewState private var progressChoice: ProgressChoice?
    @ViewState private var nextChoice: NextStepChoice?
    @ViewState private var detailsExpanded = false
    @ViewState private var generating = false
    @ViewState private var message: String?
    @ViewState private var pendingSnapshot: ReminderNoteSnapshot?
    @ViewState private var pendingText = ""
    @ViewState private var pendingDate = Date()
    @ViewState private var showingWrite = false
    @ViewState private var showingComplete = false

    private var title: String? {
        switch task.source {
        case .local: state.data.todos.first(where: { $0.id == task.id })?.text
        case .reminder: reminders.plannedItems[task.id]?.title
        }
    }
    private var composedText: String {
        [progressChoice?.sentence, nextChoice?.sentence, draft.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private var usableText: Bool {
        !composedText.isEmpty && composedText.count <= 2000 && composedText.utf8.count <= 12000
    }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("推进关联待办", systemImage: "checklist")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.green)
                if let title {
                    Text(title).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    if ended {
                        Text("选一选，这一轮推进到哪里了？")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        HStack(spacing: 6) {
                            ForEach(ProgressChoice.allCases, id: \.self) { choice in
                                choiceButton(choice.rawValue, selected: progressChoice == choice) {
                                    progressChoice = progressChoice == choice ? nil : choice
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach(NextStepChoice.allCases, id: \.self) { choice in
                                choiceButton(choice.rawValue, selected: nextChoice == choice) {
                                    nextChoice = nextChoice == choice ? nil : choice
                                }
                            }
                        }
                        DisclosureGroup("补充细节（可选）", isExpanded: $detailsExpanded) {
                            TextEditor(text: $draft).font(.system(size: 13)).scrollContentBackground(.hidden)
                                .padding(8).frame(minHeight: 80, maxHeight: 150)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                                .accessibilityLabel("本轮待办进展补充")
                        }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        if !composedText.isEmpty {
                            Text(composedText).font(.system(size: 12)).foregroundStyle(Theme.primary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                                .textSelection(.enabled)
                        }
                        HStack {
                            Button(generating ? "AI 整理中…" : "AI 整理进展") { generate(title: title) }
                                .buttonStyle(SubtleButtonStyle()).disabled(!usableText || generating || !state.hasAPIKey)
                            if !state.hasAPIKey { Button("配置 AI", action: configureAI).buttonStyle(.plain).foregroundStyle(Theme.accent) }
                            Spacer()
                            Button(task.source == .reminder ? "预览并回写" : "保存进展") { prepareSave() }
                                .buttonStyle(SubtleButtonStyle()).disabled(!usableText || generating || !state.canWrite)
                        }.font(.system(size: 11))
                        Text("点击 AI 整理时，仅发送此待办标题、上方选择或填写的进展和本轮专注时长给当前 AI 服务商；不发送提醒备注、其他待办或图片。AI 内容请核对后再保存。")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        if task.source == .reminder, let item = reminders.plannedItems[task.id], !item.isCompleted, item.writable {
                            Button("标记提醒事项完成") { showingComplete = true }
                                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                        } else if task.source == .local,
                                  let todo = state.data.todos.first(where: { $0.id == task.id }),
                                  !todo.isCompleted, todo.effectiveScheduledDay == state.todayKey {
                            Button("标记待办完成") { showingComplete = true }
                                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                        }
                    } else {
                        Text("结束本轮后，可在这里记录进展。")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Text(task.source == .reminder ? "关联的提醒暂不可用。请检查权限和已选清单，原有记录仍保留。" : "关联的本地待办已不可用。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(Theme.accent) }
            }
        }
        .task { await reminders.refresh() }
        .alert("确认追加进展？", isPresented: $showingWrite) {
            Button("追加到提醒事项") {
                guard let snapshot = pendingSnapshot else { return }
                do {
                    try reminders.appendProgress(pendingText, id: task.id, expected: snapshot, date: pendingDate)
                    clearDraft(); message = "已追加到 Apple 提醒事项的备注。"
                } catch { message = error.localizedDescription }
                pendingSnapshot = nil
            }
            Button("取消", role: .cancel) { pendingSnapshot = nil }
        } message: {
            Text("将向“\(pendingSnapshot?.title ?? "")”的原备注末尾追加：\n\n\(pendingText)\n\n原备注会保留；写入前会检查已同步到本机的标题和备注。")
        }
        .alert("确认标记完成？", isPresented: $showingComplete) {
            Button("确认完成") {
                if task.source == .local {
                    if let todo = state.data.todos.first(where: { $0.id == task.id }), !todo.isCompleted, todo.effectiveScheduledDay == state.todayKey {
                        _ = state.toggleTodo(task.id)
                    } else { message = "待办状态已变化，本次未更改。" }
                }
                else { Task { await reminders.setCompleted(task.id, expected: false) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(task.source == .reminder ? "会同步到 Apple 提醒事项。重复提醒或关联的子任务可能受到系统影响。" : "将此本地待办标记为完成。")
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Theme.accentSoft : Theme.background, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.accent.opacity(0.35) : Theme.border.opacity(0.5), lineWidth: 0.6))
        }.buttonStyle(.plain).accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func clearDraft() { draft = ""; progressChoice = nil; nextChoice = nil }

    private func generate(title: String) {
        guard usableText, !generating else { return }
        let input = composedText
        generating = true; message = nil
        Task {
            defer { generating = false }
            do {
                let result = try await state.suggestTaskProgress(title: title, evidence: input, focusSeconds: focusSeconds)
                guard composedText == input, self.title == title else { message = "内容已变化，AI 草稿未覆盖你的修改。"; return }
                progressChoice = nil; nextChoice = nil; draft = result; detailsExpanded = true
                message = "AI 草稿已填入，请核对后再保存。"
            } catch { message = error.localizedDescription }
        }
    }

    private func prepareSave() {
        guard usableText else { return }
        if task.source == .local {
            if state.saveLocalTaskProgress(todoID: task.id, sessionID: sessionID, text: composedText) {
                clearDraft(); message = "进展已保存到本地待办。"
            } else { message = "待办或关联已变化，进展未保存。" }
        } else {
            do {
                pendingSnapshot = try reminders.noteSnapshot(task.id)
                pendingText = composedText
                pendingDate = Date()
                showingWrite = true
            } catch { message = error.localizedDescription }
        }
    }
}
