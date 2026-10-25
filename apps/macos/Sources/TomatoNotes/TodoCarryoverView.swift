import SwiftUI
import TomatoCore

struct TodoCarryoverView: View {
    let todos: [TodoItem]
    let today: String
    let schedule: (Set<UUID>) -> Void
    let undoSchedule: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var isExpanded = false
    @ViewState private var selectedIDs: Set<UUID> = []

    private var candidates: [TodoItem] {
        TodoCarryover.candidates(in: todos, today: today)
    }

    private var candidateIDSet: Set<UUID> {
        Set(candidates.map(\.id))
    }

    private var selectedCandidateCount: Int {
        selectedIDs.intersection(candidateIDSet).count
    }

    private var arrangedToday: [TodoItem] {
        todos
            .filter { todo in
                todo.effectiveScheduledDay == today && todo.scheduledDays.contains(where: { $0 < today })
            }
            .sorted(by: stableOrder)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded, content: { disclosureContent }, label: { headerLabel })
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border.opacity(0.75), lineWidth: 0.7))
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isExpanded)
        .onChange(of: candidateIDs) { _, ids in
            selectedIDs.formIntersection(Set(ids))
        }
        .onChange(of: today) { _, _ in selectedIDs.removeAll() }
    }

    private var disclosureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            candidateContent
            arrangedSection
        }
        .padding(.top, 12)
    }

    @ViewBuilder private var candidateContent: some View {
        if candidates.isEmpty {
            Text("目前没有待结转事项。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(candidates) { todo in candidateRow(todo) }
            }
            batchActions
        }
    }

    private var batchActions: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectedCandidateCount) 项")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 4)
            Button("安排所选到今天") { scheduleSelected() }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill)
                .disabled(selectedIDs.isDisjoint(with: candidateIDSet))
        }
    }

    @ViewBuilder private var arrangedSection: some View {
        if !arrangedToday.isEmpty {
            Rectangle().fill(Theme.border).frame(height: 0.8).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text("已安排到今天")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                ForEach(arrangedToday) { todo in arrangedRow(todo) }
            }
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.uturn.forward.circle")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("之前还有 \(candidates.count) 项未完成")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var candidateIDs: [UUID] { candidates.map(\.id) }

    private func candidateRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: selectionBinding(for: todo.id)) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("选择待办：\(todo.text)")
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(todo.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("原始日期 \(displayDay(todo.localDay)) · 最近安排 \(displayDay(todo.effectiveScheduledDay))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("安排到今天") { schedule([todo.id]) }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .fixedSize()
                .accessibilityLabel("安排到今天：\(todo.text)")
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 0.6)
        }
    }

    private func arrangedRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(todo.text)
                    .font(.system(size: 12))
                    .foregroundStyle(todo.isCompleted ? Theme.secondary : Theme.primary)
                    .strikethrough(todo.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("原始日期 \(displayDay(todo.localDay)) · 最近安排 \(displayDay(todo.effectiveScheduledDay))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("撤销安排") { undoSchedule(todo.id) }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .tint(Theme.secondary)
                .fixedSize()
                .accessibilityLabel("撤销今天的安排：\(todo.text)")
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected { selectedIDs.insert(id) }
                else { selectedIDs.remove(id) }
            }
        )
    }

    private func scheduleSelected() {
        let ids = candidates.map(\.id).filter { selectedIDs.contains($0) }
        schedule(Set(ids))
        selectedIDs.subtract(ids)
    }

    private func displayDay(_ day: String) -> String {
        day.replacingOccurrences(of: "-", with: ".")
    }

    private func stableOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.effectiveScheduledDay != rhs.effectiveScheduledDay {
            return lhs.effectiveScheduledDay < rhs.effectiveScheduledDay
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
