import AppKit
import SwiftUI
import TomatoCore

struct FocusHeatmapCompactView: View {
    @ObservedObject var state: AppState
    let selectedDay: String?
    let onSelectDay: (String) -> Void
    let onShowAll: () -> Void

    @ViewState private var range: FocusHeatmapRange

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
        FocusHeatmapCompactContent(range: range, selectedDay: selectedDay,
                                   onSelectDay: onSelectDay, onShowAll: onShowAll)
            .onChange(of: state.focusHeatmapRevision) { _, _ in rebuildRange() }
            .preferredColorScheme(state.settings.appearance.colorScheme)
            .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private func rebuildRange() {
        range = FocusHeatmapRange.build(intervals: state.data.intervals, weekCount: 13,
                                        today: Date(), calendar: .current)
    }
}

// 只依赖范围值，便于用合成资料离屏预览，不创建 AppState 或读取个人资料。
struct FocusHeatmapCompactContent: View {
    let range: FocusHeatmapRange
    let selectedDay: String?
    let onSelectDay: (String) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("专注热力图").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("查看全部", action: onShowAll)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("heatmap.showAll")
            }
            Text("\(heatmapDuration(range.totalSeconds)) · 有记录 \(range.activeDays) 天")
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
            FocusHeatmapGrid(range: range, selectedDay: selectedDay, compact: true, onSelectDay: onSelectDay)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    dateRange
                    Spacer(minLength: 0)
                    FocusHeatmapLegend(compact: true)
                }
                VStack(alignment: .leading, spacing: 7) {
                    dateRange
                    FocusHeatmapLegend(compact: true)
                }
            }
            if range.activeDays == 0 {
                Text("完成第一段专注后，这里会留下记录")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border.opacity(0.65), lineWidth: 0.7))
        .foregroundStyle(Theme.primary)
    }

    private var dateRange: some View {
        Text("\(range.startDay) — \(range.endDay)")
            .font(.system(size: 10)).monospacedDigit()
            .foregroundStyle(Theme.secondary)
            .fixedSize()
            .accessibilityLabel("日期范围：\(range.startDay) 至 \(range.endDay)")
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
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                Text(heatmapDuration(range.totalSeconds))
                    .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    .accessibilityLabel("当前范围累计专注 \(heatmapDuration(range.totalSeconds))")
                Text("有记录 \(range.activeDays) 天")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
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

struct FocusHeatmapGrid: View {
    let range: FocusHeatmapRange
    let selectedDay: String?
    let compact: Bool
    let onSelectDay: (String) -> Void

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    @ViewState private var hoveredDay: String?
    @ViewState private var hoverTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(range: FocusHeatmapRange, selectedDay: String?, compact: Bool,
         onSelectDay: @escaping (String) -> Void) {
        self.range = range
        self.selectedDay = selectedDay
        self.compact = compact
        self.onSelectDay = onSelectDay
    }

    var body: some View {
        FocusHeatmapSizingLayout(weekCount: range.weeks.count, compact: compact) {
            GeometryReader { geometry in
                let metrics = FocusHeatmapMetrics(width: geometry.size.width,
                                                   weekCount: range.weeks.count, compact: compact)
                HStack(alignment: .top, spacing: metrics.labelGap) {
                    weekdayLabels(metrics)
                    if metrics.needsScrolling {
                        scrollingWeeks(metrics)
                    } else {
                        weekColumns(metrics)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按周排列的每日专注热力图，周一至周日")
        .accessibilityHint("内框表示今天，外框表示选中的日期。选择日期可查看当天记录。")
        .transaction { if reduceMotion { $0.animation = nil } }
        .onChange(of: range.startDay) { _, _ in clearHover() }
        .onDisappear(perform: clearHover)
    }

    private func weekdayLabels(_ metrics: FocusHeatmapMetrics) -> some View {
        VStack(spacing: 0) {
            // 固定整列宽度，顶部占位不能参与 HStack 的横向扩张。
            Color.clear.frame(width: metrics.weekdayWidth, height: metrics.monthHeaderHeight)
            ForEach(Array(weekdays.enumerated()), id: \.offset) { item in
                Text(item.element).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: metrics.weekdayWidth, height: metrics.cellPitch)
                    .accessibilityLabel("星期\(item.element)")
            }
        }
        .frame(width: metrics.weekdayWidth)
        .fixedSize()
    }

    private func scrollingWeeks(_ metrics: FocusHeatmapMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                weekColumns(metrics)
            }
            .scrollIndicators(compact ? .hidden : .visible)
            .defaultScrollAnchor(.trailing)
            .frame(width: metrics.viewportWidth, height: metrics.height, alignment: .topLeading)
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

    private func weekColumns(_ metrics: FocusHeatmapMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(monthMarkers(metrics)) { marker in
                    Text(marker.text)
                        .font(.system(size: metrics.monthFontSize, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize()
                        .frame(width: marker.width, height: metrics.monthHeaderHeight, alignment: .leading)
                        .offset(x: marker.x)
                }
            }
            .frame(width: metrics.gridWidth, height: metrics.monthHeaderHeight, alignment: .topLeading)
            HStack(alignment: .top, spacing: 0) {
                ForEach(range.weeks) { week in
                    VStack(spacing: 0) {
                        ForEach(week.days) { day in
                            dayButton(day, metrics: metrics)
                        }
                    }
                    .id(week.id)
                }
            }
        }
        .frame(width: metrics.gridWidth, height: metrics.contentHeight, alignment: .topLeading)
    }

    private func dayButton(_ day: FocusHeatmapDay, metrics: FocusHeatmapMetrics) -> some View {
        let label = day.isFuture ? heatmapAccessibilityLabel(day)
            : "\(heatmapAccessibilityLabel(day))，颜色等级：\(heatmapLevelDescription(day.intensity))"
        return Button {
            if !day.isFuture { onSelectDay(day.day) }
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(heatmapLevelColor(day.intensity))
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 3))
                .frame(width: metrics.cellSide, height: metrics.cellSide)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(day.intensity == 0 ? Theme.border : Theme.accent.opacity(0.22), lineWidth: 0.6)
                }
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(day.intensity >= 3 ? Theme.surface : Theme.accent, lineWidth: 1.2)
                            .padding(1.5)
                    }
                }
                .overlay {
                    if day.id == selectedDay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.primary, lineWidth: 1.5)
                            .padding(-1.5)
                    }
                }
                .opacity(day.isFuture ? 0 : 1)
                // 四边各留半个间距，命中区域与整齐的行列使用相同尺寸。
                .frame(width: metrics.cellPitch, height: metrics.cellPitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .accessibilityLabel(label)
        .accessibilityValue(day.isFuture ? "未来日期" : "专注时长：\(heatmapExactDuration(day.seconds))")
        .accessibilityAddTraits(day.id == selectedDay ? .isSelected : [])
        .accessibilityIdentifier("heatmap.day.\(day.day)")
        .popover(isPresented: Binding(
            get: { hoveredDay == day.day },
            set: { isPresented in
                if !isPresented && hoveredDay == day.day { setHoveredDay(nil) }
            }
        ), arrowEdge: .bottom) {
            heatmapHoverDetail(day)
        }
        .onHover { isHovering in
            hoverTask?.cancel()
            hoverTask = nil
            guard isHovering, !day.isFuture else {
                if hoveredDay == day.day { setHoveredDay(nil) }
                return
            }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled else { return }
                setHoveredDay(day.day)
            }
        }
        .zIndex(hoveredDay == day.day ? 2 : 0)
    }

    private func monthMarkers(_ metrics: FocusHeatmapMetrics) -> [FocusHeatmapMonthMarker] {
        let calendar = Calendar.current
        let font = NSFont.systemFont(ofSize: metrics.monthFontSize, weight: .medium)
        var previousMonth: DateComponents?
        var candidates: [FocusHeatmapMonthMarker] = []
        for (index, week) in range.weeks.enumerated() {
            // 沿用周四作为月份锚点，每个自然月只生成一次标记。
            guard let anchor = week.days.dropFirst(3).first?.date else { continue }
            let month = calendar.dateComponents([.year, .month], from: anchor)
            guard month != previousMonth else { continue }
            previousMonth = month
            let text = "\(month.month ?? 1)月"
            let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            let x = min(CGFloat(index) * metrics.cellPitch + metrics.cellGap / 2,
                        max(0, metrics.gridWidth - width - metrics.cellGap / 2))
            candidates.append(FocusHeatmapMonthMarker(id: index, text: text, x: x, width: width))
        }
        var markers: [FocusHeatmapMonthMarker] = []
        for (index, marker) in candidates.enumerated() {
            // 首列可能仅有上个月的尾周；与下月相邻时优先保留下月，不挤成“7月8月”。
            if index == 0, candidates.count > 1,
               marker.x + marker.width + 8 > candidates[1].x { continue }
            if let last = markers.last, last.x + last.width + 8 > marker.x { continue }
            markers.append(marker)
        }
        return markers
    }

    private func setHoveredDay(_ day: String?) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hoveredDay = day
        }
    }

    private func clearHover() {
        hoverTask?.cancel()
        hoverTask = nil
        setHoveredDay(nil)
    }
}

private struct FocusHeatmapMonthMarker: Identifiable {
    let id: Int
    let text: String
    let x: CGFloat
    let width: CGFloat
}

private struct FocusHeatmapMetrics {
    let weekdayWidth: CGFloat = 18
    let labelGap: CGFloat = 8
    let cellGap: CGFloat = 4
    let monthHeaderHeight: CGFloat = 22
    let monthFontSize: CGFloat
    let viewportWidth: CGFloat
    let cellPitch: CGFloat
    let gridWidth: CGFloat
    let needsScrolling: Bool
    let scrollbarHeight: CGFloat

    var cellSide: CGFloat { cellPitch - cellGap }
    var contentHeight: CGFloat { monthHeaderHeight + 7 * cellPitch }
    var height: CGFloat { contentHeight + scrollbarHeight }

    init(width: CGFloat, weekCount: Int, compact: Bool) {
        let columns = CGFloat(max(1, weekCount))
        viewportWidth = max(0, width - weekdayWidth - labelGap)
        // compact 自适应填满宽度；full 保留至少 19pt 命中区域，窄窗滚动而不压缩色块。
        cellPitch = max(compact ? 20 : 19, viewportWidth / columns)
        gridWidth = columns * cellPitch
        needsScrolling = gridWidth > viewportWidth + 0.5
        scrollbarHeight = needsScrolling && !compact ? 12 : 0
        monthFontSize = compact ? 10 : 11
    }
}

// 提前按宽度确定高度，避免 GeometryReader 占满父容器或依赖异步测量才能离屏渲染。
private struct FocusHeatmapSizingLayout: Layout {
    let weekCount: Int
    let compact: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fallbackWidth: CGFloat = compact ? 320 : CGFloat(max(1, weekCount)) * 19 + 26
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fallbackWidth
        let metrics = FocusHeatmapMetrics(width: width, weekCount: weekCount, compact: compact)
        return CGSize(width: width, height: metrics.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
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
        Text("颜色等级：\(heatmapLevelDescription(day.intensity))")
            .font(.system(size: 10))
            .foregroundStyle(Theme.secondary)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 9)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 0.8))
    .fixedSize()
}

private func heatmapLevelColor(_ intensity: Int) -> Color {
    switch intensity {
    case 0: return Theme.border.opacity(0.65)
    case 1: return Theme.accent.opacity(0.28)
    case 2: return Theme.accent.opacity(0.50)
    case 3: return Theme.accent.opacity(0.74)
    default: return Theme.accent
    }
}

private func heatmapLevelDescription(_ intensity: Int) -> String {
    switch intensity {
    case 0: return "0 分钟"
    case 1: return "大于 0 且少于 30 分钟"
    case 2: return "30 至不足 60 分钟"
    case 3: return "60 至不足 120 分钟"
    default: return "120 分钟及以上"
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
        HStack(spacing: 6) {
            Text("少")
            HStack(spacing: 3) {
                ForEach(0..<5) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapLevelColor(intensity))
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 2))
                        .frame(width: compact ? 10 : 11, height: compact ? 10 : 11)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(intensity == 0 ? Theme.border : Theme.accent.opacity(0.22), lineWidth: 0.6)
                        }
                        .help(heatmapLevelDescription(intensity))
                }
            }
            Text("多")
        }
        .font(.system(size: compact ? 10 : 11))
        .foregroundStyle(Theme.secondary)
        .fixedSize()
        .help(thresholds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thresholds)
    }

    private var thresholds: String {
        "每日专注时长，固定颜色等级：" + (0..<5).map(heatmapLevelDescription).joined(separator: "、")
    }
}
