import AppKit
import SwiftUI
import TomatoCore

struct FocusHeatmapCompactView: View {
    @ObservedObject var state: AppState
    let selectedDay: String?
    let onSelectDay: (String) -> Void
    let onShowAll: () -> Void

    @ViewState private var range: FocusHeatmapRange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: AppState, selectedDay: String?, onSelectDay: @escaping (String) -> Void,
         onShowAll: @escaping () -> Void) {
        self.state = state
        self.selectedDay = selectedDay
        self.onSelectDay = onSelectDay
        self.onShowAll = onShowAll
        _range = ViewState(initialValue: FocusHeatmapRange.build(intervals: state.data.intervals,
                                                                 weekCount: 13, today: Date(), calendar: .current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("专注热力图").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(heatmapDuration(range.totalSeconds)) · \(range.activeDays) 天")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Button("查看全部", action: onShowAll)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("heatmap.showAll")
            }
            FocusHeatmapGrid(range: range, selectedDay: selectedDay, compact: true, onSelectDay: onSelectDay)
                .transaction { if reduceMotion { $0.animation = nil } }
            FocusHeatmapLegend(compact: true)
            if range.activeDays == 0 {
                Text("完成第一段专注后，这里会留下记录")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border.opacity(0.65), lineWidth: 0.7))
        .onChange(of: state.focusHeatmapRevision) { _, _ in rebuildRange() }
        .preferredColorScheme(state.settings.appearance.colorScheme)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private func rebuildRange() {
        range = FocusHeatmapRange.build(intervals: state.data.intervals, weekCount: 13,
                                        today: Date(), calendar: .current)
    }
}

@MainActor
final class FocusHeatmapWindowController: NSWindowController {
    private let state: AppState
    private let onOpenDay: (String) -> Void

    init(state: AppState, onOpenDay: @escaping (String) -> Void) {
        self.state = state
        self.onOpenDay = onOpenDay
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        let height = min(430, max(350, visibleHeight - 80))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: height),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "专注热力图"
        window.minSize = NSSize(width: 620, height: 350)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.backgroundNS
        window.contentView = makePaperHostingView(
            rootView: FocusHeatmapWindowView(state: state, onOpenDay: onOpenDay),
            size: NSSize(width: 900, height: height), cornerRadius: 0
        )
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}

private struct FocusHeatmapWindowView: View {
    @ObservedObject var state: AppState
    let onOpenDay: (String) -> Void
    @ViewState private var range: FocusHeatmapRange
    @ViewState private var pageOffset = 0
    @ViewState private var selectedDay: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: AppState, onOpenDay: @escaping (String) -> Void) {
        self.state = state
        self.onOpenDay = onOpenDay
        _range = ViewState(initialValue: FocusHeatmapRange.build(intervals: state.data.intervals,
                                                                 weekCount: 53, today: Date(), calendar: .current))
        _selectedDay = ViewState(initialValue: LocalTime.dayKey(Date()))
    }

    private var selected: FocusHeatmapDay? {
        range.weeks.lazy.flatMap(\.days).first { $0.day == selectedDay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            FocusHeatmapGrid(range: range, selectedDay: selectedDay, compact: false) { day in
                selectedDay = day
            }
            .transaction { if reduceMotion { $0.animation = nil } }
            FocusHeatmapLegend(compact: false)
            detail
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .foregroundStyle(Theme.primary)
        .preferredColorScheme(state.settings.appearance.colorScheme)
        .environment(\.glassControlsEnabled, state.settings.glassControlsEnabled)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onChange(of: state.focusHeatmapRevision) { _, _ in rebuildRange() }
        .onChange(of: range.startDay) { _, _ in
            if selected == nil {
                selectedDay = range.weeks.lazy.flatMap(\.days).last(where: { !$0.isFuture })?.day ?? range.startDay
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("专注热力图").font(.system(size: 20, weight: .semibold))
                Text("\(range.startDay) 至 \(range.endDay)")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button { movePage(1) } label: { Label("上一段", systemImage: "chevron.left") }
                .buttonStyle(SubtleButtonStyle()).accessibilityIdentifier("heatmap.previousPage")
            Button { movePage(-1) } label: { Label("下一段", systemImage: "chevron.right") }
                .buttonStyle(SubtleButtonStyle()).disabled(pageOffset == 0)
                .accessibilityIdentifier("heatmap.nextPage")
            Button("回到最近") { moveToRecent() }
                .buttonStyle(SubtleButtonStyle()).disabled(pageOffset == 0)
                .accessibilityIdentifier("heatmap.recentPage")
        }
    }

    private var detail: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("当前范围").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text("\(heatmapDuration(range.totalSeconds)) · 有记录 \(range.activeDays) 天")
                    .font(.system(size: 14, weight: .semibold))
                if range.activeDays == 0 {
                    Text("完成第一段专注后，这里会留下记录")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            Rectangle().fill(Theme.border).frame(width: 1, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                if let selected {
                    Text(heatmapDateLabel(selected.date))
                        .font(.system(size: 12, weight: .semibold))
                    Text(heatmapExactDuration(selected.seconds))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if !selected.isFuture {
                        Button("查看当天记录") { onOpenDay(selected.day) }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("heatmap.openSelectedDay")
                    }
                } else {
                    Text("选择一天查看摘要").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border.opacity(0.55), lineWidth: 0.7))
    }

    private func movePage(_ delta: Int) {
        pageOffset = max(0, pageOffset + delta)
        rebuildRange()
        selectedDay = range.weeks.lazy.flatMap(\.days).last(where: { !$0.isFuture })?.day ?? range.startDay
    }

    private func moveToRecent() {
        pageOffset = 0
        rebuildRange()
        selectedDay = LocalTime.dayKey(Date())
    }

    private func rebuildRange() {
        range = FocusHeatmapRange.build(intervals: state.data.intervals, weekCount: 53,
                                        pageOffset: pageOffset, today: Date(), calendar: .current)
    }
}

private struct FocusHeatmapGrid: View {
    let range: FocusHeatmapRange
    let selectedDay: String?
    let compact: Bool
    let onSelectDay: (String) -> Void

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    @ViewState private var hoveredDay: String?
    @ViewState private var hoverTask: Task<Void, Never>?
    private var cellSide: CGFloat { compact ? 9 : 12 }
    private var cellPitch: CGFloat { compact ? 13 : 19 }
    private var weekHeader: CGFloat { compact ? 11 : 16 }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 5 : 8) {
            VStack(spacing: compact ? 3 : 5) {
                Color.clear.frame(height: weekHeader)
                ForEach(Array(weekdays.enumerated()), id: \.offset) { item in
                    Text(item.element).font(.system(size: compact ? 8 : 10))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: compact ? 10 : 16, height: cellPitch - (compact ? 0 : 1))
                        .accessibilityLabel("星期\(item.element)")
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(range.weeks.enumerated()), id: \.element.id) { item in
                            let index = item.offset
                            let week = item.element
                            VStack(alignment: .leading, spacing: 0) {
                                let month = monthLabel(for: week, previous: index > 0 ? range.weeks[index - 1] : nil)
                                Text(month)
                                    .font(.system(size: compact ? 8 : 10, weight: .medium))
                                    .foregroundStyle(Theme.secondary)
                                    .fixedSize()
                                    .frame(width: cellPitch, height: weekHeader, alignment: .leading)
                                    .accessibilityLabel(compact ? "\(month)月" : month)
                                VStack(spacing: compact ? 3 : 5) {
                                    ForEach(week.days) { day in
                                        dayButton(day)
                                    }
                                }
                            }
                            .frame(width: cellPitch, alignment: .leading)
                            .id(week.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(compact ? .hidden : .visible)
                .onAppear {
                    if let latestWeek = range.weeks.last?.id {
                        DispatchQueue.main.async { proxy.scrollTo(latestWeek, anchor: .trailing) }
                    }
                }
                .onChange(of: range.weeks.last?.id) { _, latestWeek in
                    guard let latestWeek else { return }
                    proxy.scrollTo(latestWeek, anchor: .trailing)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按周排列的每日专注热力图，周一至周日")
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            hoverTask?.cancel()
            hoveredDay = nil
        }
    }

    @ViewBuilder private func dayButton(_ day: FocusHeatmapDay) -> some View {
        let label = heatmapAccessibilityLabel(day)
        Button {
            if !day.isFuture { onSelectDay(day.day) }
        } label: {
            RoundedRectangle(cornerRadius: compact ? 2 : 3)
                .fill(heatmapColor(day))
                .frame(width: cellSide, height: cellSide)
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 2 : 3)
                        .stroke(day.isToday ? Theme.accent : .clear, lineWidth: compact ? 1 : 1.4)
                        .padding(-1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 2 : 3)
                        .stroke(day.id == selectedDay ? Theme.primary : .clear, lineWidth: compact ? 1.5 : 2)
                        .padding(-3)
                }
                .frame(width: cellPitch, height: cellPitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(day.isFuture ? "未来日期" : "专注时长：\(heatmapExactDuration(day.seconds))")
        .accessibilityAddTraits(day.id == selectedDay ? .isSelected : [])
        .accessibilityIdentifier("heatmap.day.\(day.day)")
        .popover(isPresented: Binding(
            get: { hoveredDay == day.day },
            set: { isPresented in
                if !isPresented && hoveredDay == day.day { hoveredDay = nil }
            }
        ), arrowEdge: .bottom) {
            heatmapHoverDetail(day)
        }
        .onHover { isHovering in
            hoverTask?.cancel()
            guard isHovering, !day.isFuture else {
                if hoveredDay == day.day { hoveredDay = nil }
                return
            }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                hoveredDay = day.day
            }
        }
        .zIndex(hoveredDay == day.day ? 2 : 0)
    }

    private func monthLabel(for week: FocusHeatmapWeek, previous: FocusHeatmapWeek?) -> String {
        let calendar = Calendar.current
        // 固定用周四作为每周月份锚点，避免某周含月初、下一周仍落在同月时重复标记。
        guard let anchor = week.days.dropFirst(3).first?.date else { return "" }
        let month = calendar.component(.month, from: anchor)
        let year = calendar.component(.year, from: anchor)
        if let previous, let previousAnchor = previous.days.dropFirst(3).first?.date {
            let previousMonth = calendar.component(.month, from: previousAnchor)
            let previousYear = calendar.component(.year, from: previousAnchor)
            guard month != previousMonth || year != previousYear else { return "" }
        }
        return compact ? "\(month)" : "\(month)月"
    }
}

private func heatmapHoverDetail(_ day: FocusHeatmapDay) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(heatmapDateLabel(day.date))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.primary)
        Text("专注 \(heatmapExactDuration(day.seconds))")
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 9)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 0.8))
    .fixedSize()
}

private func heatmapColor(_ day: FocusHeatmapDay) -> Color {
    guard !day.isFuture else { return .clear }
    switch day.intensity {
    case 0: return Theme.border.opacity(0.28)
    case 1: return Theme.accentSoft
    case 2: return Theme.accent.opacity(0.52)
    case 3: return Theme.accent.opacity(0.76)
    default: return Theme.accent
    }
}

private func heatmapDuration(_ seconds: Double) -> String {
    if seconds > 0 && seconds < 60 { return "少于 1 分钟" }
    let value = max(0, Int(seconds.rounded()))
    if value < 3_600 { return "\(value / 60) 分钟" }
    return "\(value / 3_600) 小时 \(value % 3_600 / 60) 分钟"
}

private func heatmapExactDuration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.rounded()))
    if value == 0 { return "0 秒" }
    if value < 60 { return "少于 1 分钟（\(value) 秒）" }
    if value < 3_600 { return "\(value / 60) 分 \(value % 60) 秒" }
    return "\(value / 3_600) 小时 \(value % 3_600 / 60) 分 \(value % 60) 秒"
}

private func heatmapDateLabel(_ date: Date) -> String {
    let dateText = LocalTime.dayKey(date)
    let weekday = ["", "日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: date)]
    return "\(dateText) 星期\(weekday)"
}

private func heatmapAccessibilityLabel(_ day: FocusHeatmapDay) -> String {
    let state = day.isFuture ? "未来日期" : "专注 \(heatmapExactDuration(day.seconds))"
    return "\(heatmapDateLabel(day.date))，\(state)\(day.isToday ? "，今天" : "")"
}

private struct FocusHeatmapLegend: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            item(color: Theme.border.opacity(0.28), label: "0")
            item(color: Theme.accentSoft, label: "<30分")
            item(color: Theme.accent.opacity(0.52), label: "30–<60分")
            item(color: Theme.accent.opacity(0.76), label: "60–<120分")
            item(color: Theme.accent, label: "≥120分")
            Spacer(minLength: 0)
        }
        .font(.system(size: compact ? 8 : 10))
        .foregroundStyle(Theme.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("每日颜色等级：0 分钟、少于 30 分钟、30 至不足 60 分钟、60 至不足 120 分钟、120 分钟及以上")
    }

    private func item(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.border.opacity(0.55), lineWidth: 0.5))
                .accessibilityHidden(true)
            Text(label).fixedSize()
        }
        .fixedSize()
    }
}
