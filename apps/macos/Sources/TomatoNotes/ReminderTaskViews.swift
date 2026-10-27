import AppKit
import SwiftUI
import TomatoCore
import TomatoSystem

struct ReminderTasksSection: View {
    @ObservedObject var state: AppState
    @ObservedObject var controller: ReminderTasksController
    var openFocus: () -> Void
    @ViewState private var showingLists = false
    @ViewState private var showingAvailable = false
    @ViewState private var showingPermission = false
    @ViewState private var search = ""
    @ViewState private var pendingCompletion: CompletionRequest?
    @ViewState private var detailTarget: DetailTarget?
    @ViewState private var detailError: String?

    private struct CompletionRequest: Identifiable { let id: UUID; let title: String; let completed: Bool }
    private struct DetailTarget: Identifiable {
        let id = UUID()
        let plan: PlannedReminder
        let details: ReminderDetails
    }
    private var plans: [PlannedReminder] {
        (state.taskWorkflow?.plannedReminders ?? []).filter { $0.scheduledDays.contains(state.todayKey) && controller.selectedListIDs.contains($0.listID) }
    }
    private var available: [ReminderItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return controller.availableItems.filter { item in
            !plans.contains { $0.listID == item.listID && ($0.reminderID == item.id || controller.plannedItems[$0.id]?.id == item.id) } &&
                (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }
    private var availableLists: [String] {
        Array(Set(available.map(\.listID))).sorted { left, right in
            let a = available.first(where: { $0.listID == left })?.listTitle ?? ""
            let b = available.first(where: { $0.listID == right })?.listTitle ?? ""
            return a == b ? left < right : a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checklist").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent).frame(width: 31, height: 31)
                    .background(Theme.accentSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("提醒事项").font(.system(size: 14, weight: .semibold))
                    Text(controller.enabled ? "Apple · 已选 \(controller.selectedListIDs.count) 个清单" : "把想做的事安排到今天")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 4)
                if controller.loading { ProgressView().controlSize(.small) }
                if controller.enabled {
                    Button { showingAvailable.toggle() } label: {
                        Image(systemName: showingAvailable ? "xmark" : "plus").font(.system(size: 13, weight: .medium))
                            .frame(width: 29, height: 29)
                            .background(Theme.accentSoft.opacity(0.65), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                        .help(showingAvailable ? "收起待安排事项" : "安排提醒到今天")
                        .accessibilityLabel(showingAvailable ? "收起待安排事项" : "安排提醒到今天")
                    Button { showingLists.toggle() } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                            .frame(width: 29, height: 29).contentShape(Circle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.secondary).help("管理提醒清单")
                        .accessibilityLabel("管理提醒清单")
                        .popover(isPresented: $showingLists, arrowEdge: .top) { listSettings }
                } else {
                    Button("连接") { showingPermission = true }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                        .disabled(!state.canWrite || state.taskWorkflow == nil)
                }
            }
            #if DEBUG
            if Bundle.main.bundleIdentifier == "com.zixuan.TomatoNotes.QA" && ProcessInfo.processInfo.arguments.contains("--ui-test") && ProcessInfo.processInfo.arguments.contains("--synthetic-reminders") {
                Text("隔离测试 · 模拟提醒").font(.system(size: 10)).foregroundStyle(Theme.accent).padding(.top, 8)
            }
            #endif
            if controller.enabled {
                if !controller.hasAccess {
                    Text("提醒事项权限不可用，请在系统设置中允许访问。")
                        .font(.system(size: 11)).foregroundStyle(Theme.accent).padding(.top, 12)
                    Button("重新连接") { showingPermission = true }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Theme.accent).padding(.top, 6)
                } else if controller.selectedListIDs.isEmpty {
                    Button("选择要同步的清单") { showingLists = true }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Theme.accent).padding(.top, 12)
                } else if plans.isEmpty {
                    Text("今天还没有安排提醒，点 + 选择。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.top, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(plans) { plan in
                            if let item = controller.plannedItems[plan.id] { plannedRow(plan, item: item) }
                            else {
                                Text("已安排的提醒暂不可用，记录仍保留。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                            }
                        }
                    }.padding(.top, 10)
                }
                if showingAvailable && controller.hasAccess && !controller.selectedListIDs.isEmpty { availableList }
            }
            if let message = detailError ?? controller.message {
                Text(message).font(.system(size: 10)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 9)
            }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.border.opacity(0.6), lineWidth: 0.6))
        .task { await controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh() }
        }
        .alert("连接 Apple 提醒事项", isPresented: $showingPermission) {
            Button("继续") { Task { await controller.connect(); if controller.enabled { showingLists = true } } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("macOS 会授予应用所有提醒事项的读写权限。应用会显示清单名称供选择，只读取所选清单内的提醒；修改完成状态和内容前需要你确认。")
        }
        .alert(item: $pendingCompletion) { request in
            Alert(title: Text(request.completed ? "取消完成提醒事项？" : "完成提醒事项？"),
                  message: Text("“\(request.title)”将在 Apple 提醒事项中同步更改。重复提醒或关联的子任务可能受到系统影响。"),
                  primaryButton: .default(Text("确认更改"), action: { Task { await controller.setCompleted(request.id, expected: request.completed) } }),
                  secondaryButton: .cancel())
        }
        .sheet(item: $detailTarget) { target in
            ReminderDetailEditor(controller: controller, plan: target.plan, original: target.details)
        }
    }

    private var listSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("同步清单").font(.system(size: 14, weight: .semibold))
            Text("只读取选中清单的提醒。安排到今天不会改变原截止日期。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if controller.lists.isEmpty { Text("暂无可用清单").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            ForEach(controller.lists) { list in
                Button { controller.setList(list.id, selected: !controller.selectedListIDs.contains(list.id)) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: controller.selectedListIDs.contains(list.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(controller.selectedListIDs.contains(list.id) ? Theme.accent : Theme.secondary)
                        Text(list.title).lineLimit(1)
                        Spacer()
                        if !list.writable { Text("只读").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).font(.system(size: 12))
                    .accessibilityLabel("清单：\(list.title)")
                    .accessibilityValue(controller.selectedListIDs.contains(list.id) ? "已选择" : "未选择")
            }
            Divider().opacity(0.35)
            HStack {
                Button("刷新") { Task { await controller.refresh() } }
                Spacer()
                Button("断开连接") { controller.disconnect(); showingLists = false; showingAvailable = false }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.padding(16).frame(width: 260).background(Theme.surface).foregroundStyle(Theme.primary)
    }

    private func plannedRow(_ plan: PlannedReminder, item: ReminderItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { pendingCompletion = CompletionRequest(id: plan.id, title: item.title, completed: item.isCompleted) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(item.isCompleted ? Theme.green : Theme.secondary.opacity(0.75))
            }.buttonStyle(.plain).disabled(!item.writable)
                .accessibilityLabel(item.isCompleted ? "取消完成：\(item.title)" : "完成：\(item.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 12, weight: .medium)).strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Theme.secondary : Theme.primary).fixedSize(horizontal: false, vertical: true)
                Text(subtitle(item)).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !item.isCompleted {
                Button {
                    state.selectFocusTask(TaskReference(source: .reminder, id: plan.id), title: item.title)
                    openFocus()
                } label: { Image(systemName: "timer").frame(width: 23, height: 23) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).help("关联本轮专注")
                    .accessibilityLabel("专注：\(item.title)")
            }
            itemActions(item, remove: { controller.unschedule(plan.id) })
        }
        .padding(.vertical, 10)
        .background(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.45)).frame(height: 0.5) }
    }

    private var availableList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 0.5).padding(.vertical, 4)
            HStack {
                Text("从清单安排").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("不改变截止日期").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            TextField("搜索提醒", text: $search).textFieldStyle(.plain).font(.system(size: 11))
                .padding(8).background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            if available.isEmpty {
                Text("没有其他符合条件的提醒。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.vertical, 6)
            }
            ForEach(availableLists, id: \.self) { list in
                Text(available.first(where: { $0.listID == list })?.listTitle ?? "清单")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).padding(.top, 4)
                ForEach(available.filter { $0.listID == list }) { item in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            let metadata = subtitle(item, includeList: false)
                            if !metadata.isEmpty { Text(metadata).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        itemActions(item)
                        Button { controller.schedule(item) } label: {
                            Image(systemName: "plus.circle").font(.system(size: 15)).frame(width: 24, height: 24)
                        }.buttonStyle(.plain).foregroundStyle(Theme.accent).help("安排到今天")
                            .accessibilityLabel("安排今天：\(item.title)")
                    }.padding(.vertical, 4)
                }
            }
        }.padding(.top, 10)
    }

    private func itemActions(_ item: ReminderItem, remove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 3) {
            Button { openDetails(item) } label: {
                Image(systemName: "info.circle").font(.system(size: 13)).frame(width: 23, height: 23)
            }.buttonStyle(.plain).foregroundStyle(Theme.secondary).help("查看和编辑提醒详情")
                .accessibilityLabel("提醒详情：\(item.title)")
            if let remove {
                Button(action: remove) {
                    Image(systemName: "minus.circle").font(.system(size: 13)).frame(width: 23, height: 23)
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary).help("从今天移除，不删除系统提醒")
                    .accessibilityLabel("从今天移除：\(item.title)")
            }
        }
    }

    private func openDetails(_ item: ReminderItem) {
        do {
            let (plan, details) = try controller.details(for: item)
            detailError = nil; detailTarget = DetailTarget(plan: plan, details: details)
        } catch { detailError = error.localizedDescription }
    }

    private func subtitle(_ item: ReminderItem, includeList: Bool = true) -> String {
        var parts: [String] = includeList ? [item.listTitle] : []
        if let components = item.dueDate {
            var calendar = Calendar(identifier: .gregorian)
            if let zone = components.timeZone { calendar.timeZone = zone }
            if let date = calendar.date(from: components) {
                let hasTime = components.hour != nil || components.minute != nil
                parts.append("截止 " + date.formatted(date: .numeric, time: hasTime ? .shortened : .omitted))
            }
        }
        if (1...4).contains(item.priority) { parts.append("高优先级") }
        else if item.priority == 5 { parts.append("中优先级") }
        else if (6...9).contains(item.priority) { parts.append("低优先级") }
        if item.isRecurring { parts.append("重复") }
        if item.hasAlarms { parts.append("有提醒") }
        return parts.joined(separator: " · ")
    }
}
