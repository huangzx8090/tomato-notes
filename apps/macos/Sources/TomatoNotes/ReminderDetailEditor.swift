import AppKit
import SwiftUI
import TomatoCore
import TomatoSystem

struct ReminderDetailEditor: View {
    @ObservedObject var controller: ReminderTasksController
    let plan: PlannedReminder
    let original: ReminderDetails
    @Environment(\.dismiss) private var dismiss
    @ViewState private var title: String
    @ViewState private var notes: String
    @ViewState private var hasStart: Bool
    @ViewState private var start: Date
    @ViewState private var startHasTime: Bool
    @ViewState private var hasDue: Bool
    @ViewState private var due: Date
    @ViewState private var dueHasTime: Bool
    @ViewState private var priority: Int
    @ViewState private var location: String
    @ViewState private var url: String
    @ViewState private var repeatFrequency: ReminderRepeatFrequency
    @ViewState private var repeatInterval: Int
    @ViewState private var hasAlarm: Bool
    @ViewState private var alarmDate: Date
    @ViewState private var confirming = false
    @ViewState private var error: String?

    init(controller: ReminderTasksController, plan: PlannedReminder, original: ReminderDetails) {
        self.controller = controller; self.plan = plan; self.original = original
        _title = ViewState(initialValue: original.title); _notes = ViewState(initialValue: original.notes)
        _hasStart = ViewState(initialValue: original.startDate != nil)
        _start = ViewState(initialValue: Self.date(original.startDate))
        _startHasTime = ViewState(initialValue: Self.hasTime(original.startDate))
        _hasDue = ViewState(initialValue: original.dueDate != nil)
        _due = ViewState(initialValue: Self.date(original.dueDate))
        _dueHasTime = ViewState(initialValue: Self.hasTime(original.dueDate))
        _priority = ViewState(initialValue: Self.priorityChoice(original.priority))
        _location = ViewState(initialValue: original.location ?? "")
        _url = ViewState(initialValue: original.url ?? "")
        _repeatFrequency = ViewState(initialValue: original.simpleRepeat?.frequency ?? .none)
        _repeatInterval = ViewState(initialValue: original.simpleRepeat?.interval ?? 1)
        _hasAlarm = ViewState(initialValue: original.simpleTimeAlarm != nil)
        _alarmDate = ViewState(initialValue: original.simpleTimeAlarm ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("提醒详情").font(.system(size: 19, weight: .semibold, design: .serif))
                    Text(original.writable ? "修改后需确认同步到 Apple 提醒事项" : "此清单为只读")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("关闭详情")
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    section("标题") {
                        TextField("提醒事项", text: $title).textFieldStyle(.plain).font(.system(size: 13))
                            .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                    section("备注") {
                        TextEditor(text: $notes).font(.system(size: 12)).scrollContentBackground(.hidden)
                            .padding(7).frame(minHeight: 80, maxHeight: 130)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                    section("日期与优先级") {
                        VStack(alignment: .leading, spacing: 10) {
                            dateRow("开始日期", enabled: $hasStart, value: $start, hasTime: $startHasTime,
                                    zone: original.startDate?.timeZone)
                            dateRow("截止日期", enabled: $hasDue, value: $due, hasTime: $dueHasTime,
                                    zone: original.dueDate?.timeZone)
                            HStack {
                                Text("优先级").font(.system(size: 12))
                                Spacer()
                                Picker("优先级", selection: $priority) {
                                    Text("无").tag(0); Text("低").tag(9); Text("中").tag(5); Text("高").tag(1)
                                }.labelsHidden().frame(width: 100)
                            }
                        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    section("位置与链接") {
                        VStack(spacing: 10) {
                            TextField("位置描述（不设置到达或离开提醒）", text: $location)
                            TextField("链接，例如 https://", text: $url)
                        }.textFieldStyle(.plain).font(.system(size: 12)).padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    section("重复与提醒") {
                        VStack(alignment: .leading, spacing: 10) {
                            if original.simpleRepeat != nil {
                                HStack {
                                    Text("重复").font(.system(size: 12)); Spacer()
                                    Picker("重复", selection: $repeatFrequency) {
                                        ForEach(ReminderRepeatFrequency.allCases, id: \.self) { value in
                                            Text(value.label).tag(value)
                                        }
                                    }.labelsHidden().frame(width: 110)
                                }
                                if repeatFrequency != .none {
                                    Stepper("间隔 \(repeatInterval)", value: $repeatInterval, in: 1...99)
                                        .font(.system(size: 11))
                                    Text("重复提醒需要设置截止日期。")
                                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                }
                            } else {
                                ForEach(original.recurrenceSummary, id: \.self) { value in
                                    Text(value).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                }
                                Text("复杂重复规则会保留，请在系统提醒事项中修改。")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            if original.canEditTimeAlarm {
                                Toggle("时间提醒", isOn: $hasAlarm).toggleStyle(.checkbox).font(.system(size: 12))
                                if hasAlarm {
                                    if hasDue && dueHasTime {
                                        HStack(spacing: 8) {
                                            quickButton("截止时", action: { alarmDate = due })
                                            quickButton("提前 10 分钟", action: { alarmDate = due.addingTimeInterval(-600) })
                                        }
                                    }
                                    DatePicker("提醒时间", selection: $alarmDate, displayedComponents: [.date, .hourAndMinute])
                                        .labelsHidden()
                                }
                            } else {
                                ForEach(original.alarmSummary, id: \.self) { value in
                                    Text(value).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                }
                                Text("现有提醒设置会保留，可在系统提醒事项中修改。")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text("标签、分栏、旗标和图片等信息，请在系统提醒事项中查看或编辑。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("打开 Apple 提醒事项") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true) }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            Divider().opacity(0.35)
            HStack {
                Text("安排到今天不会修改截止日期").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SubtleButtonStyle())
                Button("保存修改") { confirming = true }.buttonStyle(SubtleButtonStyle())
                    .disabled(!original.writable || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)
        }
        .frame(width: 430, height: 600)
        .background(Theme.background).foregroundStyle(Theme.primary)
        .alert("确认同步修改？", isPresented: $confirming) {
            Button("确认保存") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只修改你编辑过的字段；复杂的重复和提醒设置会保留。保存前会检查已同步到本机的变更。")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            content()
        }
    }

    private func dateRow(_ label: String, enabled: Binding<Bool>, value: Binding<Date>, hasTime: Binding<Bool>, zone: TimeZone?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(label, isOn: enabled).toggleStyle(.checkbox).font(.system(size: 12))
            if enabled.wrappedValue {
                HStack(spacing: 8) {
                    quickButton("今天") { chooseDate(offset: 0, value: value, timed: hasTime.wrappedValue, zone: zone) }
                    quickButton("明天") { chooseDate(offset: 1, value: value, timed: hasTime.wrappedValue, zone: zone) }
                    quickButton("下周") { chooseDate(offset: 7, value: value, timed: hasTime.wrappedValue, zone: zone) }
                }
                HStack {
                    DatePicker(label, selection: value, displayedComponents: hasTime.wrappedValue ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden().environment(\.timeZone, zone ?? .current)
                    Spacer()
                    Toggle("时间", isOn: hasTime).toggleStyle(.checkbox).font(.system(size: 11))
                }
            }
        }
    }

    private func quickButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.plain).font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.accent).padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.accentSoft.opacity(0.65), in: Capsule())
    }

    private func chooseDate(offset: Int, value: Binding<Date>, timed: Bool, zone: TimeZone?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? .current
        guard let target = calendar.date(byAdding: .day, value: offset, to: Date()) else { return }
        var parts = calendar.dateComponents([.year, .month, .day], from: target)
        if timed {
            parts.hour = calendar.component(.hour, from: value.wrappedValue)
            parts.minute = calendar.component(.minute, from: value.wrappedValue)
        }
        if let result = calendar.date(from: parts) { value.wrappedValue = result }
    }

    private func save() {
        var edits = ReminderDetailEdits(original)
        edits.title = title; edits.notes = notes
        edits.startDate = changedDate(enabled: hasStart, date: start, timed: startHasTime, original: original.startDate)
        edits.dueDate = changedDate(enabled: hasDue, date: due, timed: dueHasTime, original: original.dueDate)
        if priority != Self.priorityChoice(original.priority) { edits.priority = priority }
        if location != (original.location ?? "") { edits.location = location.isEmpty ? nil : location }
        if url != (original.url ?? "") { edits.url = url.isEmpty ? nil : url }
        if original.simpleRepeat != nil { edits.simpleRepeat = .init(frequency: repeatFrequency, interval: repeatFrequency == .none ? 1 : repeatInterval) }
        if original.canEditTimeAlarm {
            if hasAlarm, alarmDate != original.simpleTimeAlarm { edits.timeAlarm = .set(alarmDate) }
            else if !hasAlarm, original.simpleTimeAlarm != nil { edits.timeAlarm = .remove }
        }
        if repeatFrequency != .none && !hasDue { error = "重复提醒需要设置截止日期。"; return }
        do { try controller.updateDetails(edits, plan: plan, expected: original); dismiss() }
        catch { self.error = error.localizedDescription }
    }

    private func changedDate(enabled: Bool, date: Date, timed: Bool, original: DateComponents?) -> DateComponents? {
        guard enabled else { return nil }
        if original != nil, date == Self.date(original), timed == Self.hasTime(original) { return original }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = original?.timeZone ?? .current
        var fields: Set<Calendar.Component> = [.year, .month, .day]
        if timed { fields.formUnion([.hour, .minute]) }
        var components = calendar.dateComponents(fields, from: date)
        components.calendar = calendar
        components.timeZone = original?.timeZone
        return components
    }

    private static func date(_ components: DateComponents?) -> Date {
        guard let components else { return Date() }
        var calendar = Calendar(identifier: .gregorian)
        if let zone = components.timeZone { calendar.timeZone = zone }
        return calendar.date(from: components) ?? Date()
    }
    private static func hasTime(_ components: DateComponents?) -> Bool { components?.hour != nil || components?.minute != nil }
    private static func priorityChoice(_ value: Int) -> Int {
        if (1...4).contains(value) { return 1 }
        if value == 5 { return 5 }
        if (6...9).contains(value) { return 9 }
        return 0
    }
}
