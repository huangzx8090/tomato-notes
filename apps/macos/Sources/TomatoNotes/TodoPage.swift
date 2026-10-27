import AppKit
import SwiftUI
import TomatoCore

struct TodoPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var reminderTasks: ReminderTasksController
    var openFocus: () -> Void
    let todos: [TodoItem]
    let allTodos: [TodoItem]
    let day: String
    @Binding var draft: String
    var addTodo: (String) -> Void
    var toggleTodo: (UUID) -> Bool
    var updateTodo: (UUID, String) -> Void
    var deleteTodo: (UUID) -> Void
    var scheduleCarryover: (Set<UUID>) -> Void
    var undoCarryover: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var lastCompletedID: UUID?
    @ViewState private var feedbackGeneration = 0

    private var todayPlans: [PlannedReminder] {
        guard reminderTasks.enabled else { return [] }
        return (state.taskWorkflow?.plannedReminders ?? []).filter { $0.scheduledDays.contains(day) && reminderTasks.selectedListIDs.contains($0.listID) }
    }
    private var completed: Int { todos.filter(\.isCompleted).count + todayPlans.filter { reminderTasks.plannedItems[$0.id]?.isCompleted == true }.count }
    private var total: Int { todos.count + todayPlans.count }
    private var allDone: Bool { total > 0 && completed == total }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TodoCarryoverView(todos: allTodos, today: day,
                              schedule: scheduleCarryover,
                              undoSchedule: undoCarryover)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日待办").font(.system(size: 21, weight: .semibold, design: .serif))
                    Text("把想做的事，变成做过的事。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                TodoProgressRing(completed: completed, total: total)
            }

            HStack(spacing: 10) {
                Image(systemName: "pencil.tip").foregroundStyle(Theme.accent)
                TextField("添一件小事，回车记下", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13)).onSubmit(save)
                    .accessibilityIdentifier("todos.new")
                Button(action: save) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("添加待办")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border.opacity(0.8), lineWidth: 0.7))

            ReminderTasksSection(state: state, controller: reminderTasks, openFocus: openFocus)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("本 地 待 办").font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text(day.replacingOccurrences(of: "-", with: "."))
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                }.foregroundStyle(Theme.secondary).padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 12)

                if todos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "leaf").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Theme.green)
                        Text(total == 0 ? "从一件小事开始" : "本地待办还是空白").font(.system(size: 15, weight: .medium, design: .serif))
                        Text("不必排满今天，留一点从容。")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    ForEach(todos) { todo in
                        NotebookTodoRow(todo: todo, progress: state.taskWorkflow?.localProgress.last(where: { $0.todoID == todo.id })?.text, update: updateTodo, remove: { remove(todo) }) { complete(todo) }
                            .transition(.opacity)
                    }
                }

                completionFooter.padding(.horizontal, 22).padding(.vertical, 18)
            }
            .background { NotebookPaper() }
            .padding(.bottom, 5)

            Text("轻点勾选 · 双击改字 · 右侧删除可撤销")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: completed)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: todos.map(\.id))
        .onChange(of: day) { _, _ in lastCompletedID = nil }
        .task(id: feedbackGeneration) {
            guard lastCompletedID != nil else { return }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            lastCompletedID = nil
        }
    }

    @ViewBuilder private var completionFooter: some View {
        if allDone {
            HStack(spacing: 12) {
                CompletionSeal().rotationEffect(.degrees(-9))
                VStack(alignment: .leading, spacing: 4) {
                    Text("清单完成，给自己一个肯定。")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.green)
                    Text("这 \(completed) 件小事，都留下了进展。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }.transition(reduceMotion ? .opacity : .scale(scale: 1.08).combined(with: .opacity))
                .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 7) {
                Image(systemName: lastCompletedID == nil ? "leaf" : "sparkle")
                Text(lastCompletedID == nil ? (completed == 0 ? "慢慢来，一件一件就很好。" : "已经完成 \(completed) 件，进展看得见。") : "又完成一件小事，真好。")
            }
            .font(.system(size: 11)).foregroundStyle(lastCompletedID == nil ? Theme.secondary : Theme.green)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        addTodo(value)
        draft = ""
    }

    private func complete(_ todo: TodoItem) {
        let isCompleted = toggleTodo(todo.id)
        if isCompleted {
            lastCompletedID = todo.id
            feedbackGeneration += 1
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } else if lastCompletedID == todo.id { lastCompletedID = nil }
    }

    private func remove(_ todo: TodoItem) {
        deleteTodo(todo.id)
        if lastCompletedID == todo.id { lastCompletedID = nil }
    }
}

private struct TodoProgressRing: View {
    let completed: Int
    let total: Int
    var body: some View {
        ZStack {
            Circle().stroke(Theme.border.opacity(0.65), lineWidth: 3)
            Circle().trim(from: 0, to: total == 0 ? 0 : CGFloat(completed) / CGFloat(total))
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(completed)").font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("/ \(total)").font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.secondary)
            }
        }.frame(width: 55, height: 55)
            .accessibilityElement(children: .ignore).accessibilityLabel("已完成 \(completed) 项，共 \(total) 项待办")
    }
}

private struct NotebookTodoRow: View {
    let todo: TodoItem
    let progress: String?
    var update: (UUID, String) -> Void
    var remove: () -> Void
    var toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var editing = false
    @ViewState private var draft = ""
    @ViewState private var deleteHovered = false
    @FocusState private var editingFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Button(action: toggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(todo.isCompleted ? Theme.greenFill : Theme.todoPaperTop)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(todo.isCompleted ? Theme.green : Theme.border, lineWidth: 0.8)
                    Path { path in
                        path.move(to: CGPoint(x: 6, y: 12))
                        path.addLine(to: CGPoint(x: 10, y: 16))
                        path.addLine(to: CGPoint(x: 18, y: 7))
                    }.trim(from: 0, to: todo.isCompleted ? 1 : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 24, height: 24)
                .shadow(color: Theme.paperShadow.opacity(todo.isCompleted ? 0.05 : 0.12), radius: 1, y: 1)
                .padding(4).contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: todo.isCompleted)
            }
            .buttonStyle(PaperCheckStyle())
            .accessibilityLabel(todo.isCompleted ? "取消完成：\(todo.text)" : "完成：\(todo.text)")
            .accessibilityValue(todo.isCompleted ? "已完成" : "未完成")
            .accessibilityIdentifier("todos.check.\(todo.id)")

            if editing {
                TextField("待办文字", text: $draft).textFieldStyle(.plain).font(.system(size: 13))
                    .focused($editingFocused).onSubmit(finishEditing)
                    .onExitCommand { editing = false }
                    .onChange(of: editingFocused) { _, focused in if !focused && editing { finishEditing() } }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.text).font(.system(size: 13))
                        .strikethrough(todo.isCompleted, color: Theme.green.opacity(0.7))
                        .foregroundStyle(todo.isCompleted ? Theme.secondary : Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if todo.localDay != todo.effectiveScheduledDay {
                        Text("来源 \(todo.localDay) · 最近安排 \(todo.effectiveScheduledDay)")
                            .font(.system(size: 9)).foregroundStyle(Theme.secondary)
                    }
                    if let progress, !progress.isEmpty {
                        Text("进展：\(progress)").font(.system(size: 10)).foregroundStyle(Theme.green)
                            .lineLimit(3)
                    }
                    if let date = todo.completedAt {
                        Text("已完成 · \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 9)).foregroundStyle(Theme.green)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).onTapGesture(count: 2, perform: beginEditing)
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: removeTodo) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(deleteHovered ? Theme.accent : Theme.secondary)
                    .frame(width: 30, height: 30)
                    .background(deleteHovered ? Theme.accentSoft.opacity(0.5) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PaperCheckStyle())
            .onHover { deleteHovered = $0 }
            .help("删除待办，删除后可在底部撤销")
            .accessibilityLabel("删除待办：\(todo.text)")
            .accessibilityIdentifier("todos.delete.\(todo.id)")
        }
        .padding(.leading, 18).padding(.trailing, 22).padding(.vertical, 11)
        .frame(minHeight: 60)
        .background(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.55)).frame(height: 0.5).padding(.horizontal, 20) }
        .contextMenu {
            Button("修改文字", action: beginEditing)
            Divider()
            Button("删除待办", role: .destructive, action: removeTodo)
        }
        .onChange(of: editing) { _, value in editingFocused = value }
    }

    private func beginEditing() { draft = todo.text; editing = true }
    private func finishEditing() { update(todo.id, draft); editing = false }
    private func removeTodo() {
        if editing { finishEditing() }
        remove()
    }
}

private struct PaperCheckStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct NotebookPaper: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14).fill(Theme.todoPaperBottom)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.6))
            .padding(.horizontal, 6).offset(y: 5)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Theme.todoPaperTop, Theme.todoPaperBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.paperHighlight.opacity(0.8), lineWidth: 0.7))
                    .shadow(color: Theme.paperShadow.opacity(0.12), radius: 9, x: 0, y: 4)
            }
            .overlay(alignment: .top) {
                HStack(spacing: 38) {
                    ForEach(0..<5) { _ in
                        Capsule().fill(Theme.paperShadow.opacity(0.22)).frame(width: 16, height: 4)
                            .overlay(Capsule().stroke(Theme.paperHighlight.opacity(0.6), lineWidth: 0.5).offset(y: 1))
                    }
                }.padding(.top, 10)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct CompletionSeal: View {
    var body: some View {
        ZStack {
            Circle().stroke(Theme.green.opacity(0.8), lineWidth: 1.2)
            Circle().stroke(Theme.green.opacity(0.5), style: StrokeStyle(lineWidth: 0.6, dash: [1, 2])).padding(4)
            VStack(spacing: 2) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                Text("完成").font(.system(size: 9, weight: .semibold, design: .serif))
            }.foregroundStyle(Theme.green)
        }.frame(width: 50, height: 50).accessibilityHidden(true)
    }
}
