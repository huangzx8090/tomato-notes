import AppKit
import SwiftUI
import TomatoCore

@MainActor
final class HistorySearchWindowController: NSWindowController {
    init(state: AppState, onOpenTarget: @escaping (HistorySearchTarget) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "搜索历史"
        window.backgroundColor = Theme.backgroundNS
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 460)
        let hosting = NSHostingView(rootView: HistorySearchWindow(state: state, onOpenTarget: onOpenTarget))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 760, height: 650))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private struct HistorySearchWindow: View {
    @ObservedObject private var state: AppState
    private let onOpenTarget: (HistorySearchTarget) -> Void

    // AppState 的计时 tick 不会改变此缓存；主代理只在历史文字变化时递增 historySearchRevision。
    @ViewState private var index: HistorySearchIndex
    @ViewState private var query = ""
    @ViewState private var selectedKinds = Set(HistorySearchKind.allCases)
    @ViewState private var enablesFromDay = false
    @ViewState private var enablesThroughDay = false
    @ViewState private var fromDate = Date()
    @ViewState private var throughDate = Date()
    @ViewState private var results: [HistorySearchResult] = []
    @ViewState private var canLoadMore = false
    @ViewState private var isSearching = false
    @ViewState private var requestGeneration = 0
    @ViewState private var pendingSearch: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

    init(state: AppState, onOpenTarget: @escaping (HistorySearchTarget) -> Void) {
        self.state = state
        self.onOpenTarget = onOpenTarget
        _index = ViewState(initialValue: HistorySearchIndex(data: state.data))
    }

    private var filters: HistorySearchFilters {
        HistorySearchFilters(kinds: selectedKinds,
                             fromDay: enablesFromDay ? LocalTime.dayKey(fromDate) : nil,
                             throughDay: enablesThroughDay ? LocalTime.dayKey(throughDate) : nil)
    }

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索待办、便签、专注目标和成果", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($searchFieldFocused)
                .onSubmit { startSearch(immediately: true) }
                .accessibilityLabel("搜索本地历史")

            filtersView

            Divider().overlay(Theme.border)

            if !hasQuery {
                emptyMessage("输入关键词搜索本地历史；多个关键词需要全部命中。")
            } else if isSearching && results.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在搜索…").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                emptyMessage("没有找到匹配记录。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(results) { result in resultRow(result) }
                        if canLoadMore {
                            Button("加载更多") { loadMore() }
                                .buttonStyle(.bordered).tint(Theme.accent)
                                .padding(.vertical, 6)
                        }
                    }.padding(.vertical, 3)
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 460)
        .background(Theme.background)
        .foregroundStyle(Theme.primary)
        .preferredColorScheme(state.settings.appearance.colorScheme)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onAppear { searchFieldFocused = true }
        .onDisappear { pendingSearch?.cancel() }
        .onChange(of: query) { _, _ in startSearch() }
        .onChange(of: selectedKinds) { _, _ in startSearch() }
        .onChange(of: enablesFromDay) { _, _ in startSearch() }
        .onChange(of: enablesThroughDay) { _, _ in startSearch() }
        .onChange(of: fromDate) { _, _ in if enablesFromDay { startSearch() } }
        .onChange(of: throughDate) { _, _ in if enablesThroughDay { startSearch() } }
        .onChange(of: state.historySearchRevision) { _, _ in
            index = HistorySearchIndex(data: state.data)
            startSearch()
        }
    }

    private var filtersView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                ForEach(HistorySearchKind.allCases, id: \.self) { kind in
                    Toggle(kind.label, isOn: Binding(
                        get: { selectedKinds.contains(kind) },
                        set: { enabled in
                            if enabled { selectedKinds.insert(kind) }
                            else { selectedKinds.remove(kind) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                }
            }
            HStack(spacing: 12) {
                Toggle("从", isOn: $enablesFromDay).toggleStyle(.checkbox)
                DatePicker("起始日期", selection: $fromDate, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).disabled(!enablesFromDay)
                Toggle("至", isOn: $enablesThroughDay).toggleStyle(.checkbox)
                DatePicker("结束日期", selection: $throughDate, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).disabled(!enablesThroughDay)
                Spacer(minLength: 0)
            }.font(.system(size: 11))
        }
    }

    private func resultRow(_ result: HistorySearchResult) -> some View {
        Button { onOpenTarget(result.target) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(result.kind.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(result.day)
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                    ForEach(result.sources, id: \.self) { source in
                        Text(source.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(source == .aiSummary ? Theme.green : Theme.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(source == .aiSummary ? Theme.greenSoft : Theme.surface,
                                        in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                Text(result.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(result.excerpt).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border.opacity(0.7), lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.kind.label)，\(result.day)，\(result.title)。\(result.excerpt)")
        .accessibilityHint("打开对应的历史记录")
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    private func startSearch(immediately: Bool = false) {
        requestGeneration &+= 1
        let generation = requestGeneration
        pendingSearch?.cancel()
        results = []
        canLoadMore = false
        guard hasQuery else {
            isSearching = false
            return
        }

        isSearching = true
        let indexSnapshot = index
        let querySnapshot = query
        let filtersSnapshot = filters
        pendingSearch = Task {
            if !immediately { try? await Task.sleep(nanoseconds: 200_000_000) }
            guard !Task.isCancelled else { return }
            let page = await Task.detached(priority: .userInitiated) {
                indexSnapshot.search(query: querySnapshot, filters: filtersSnapshot, offset: 0, limit: 51)
            }.value
            guard !Task.isCancelled, generation == requestGeneration else { return }
            results = Array(page.prefix(50))
            canLoadMore = page.count > 50
            isSearching = false
        }
    }

    private func loadMore() {
        guard canLoadMore, !isSearching else { return }
        let generation = requestGeneration
        let offset = results.count
        let indexSnapshot = index
        let querySnapshot = query
        let filtersSnapshot = filters
        isSearching = true
        Task {
            let page = await Task.detached(priority: .userInitiated) {
                indexSnapshot.search(query: querySnapshot, filters: filtersSnapshot, offset: offset, limit: 51)
            }.value
            guard generation == requestGeneration else { return }
            results.append(contentsOf: page.prefix(50))
            canLoadMore = page.count > 50
            isSearching = false
        }
    }
}

private extension HistorySearchKind {
    var label: String {
        switch self {
        case .todo: "待办"
        case .note: "便签"
        case .focus: "专注"
        case .outcome: "成果"
        }
    }
}

private extension HistorySearchSource {
    var label: String { self == .userRecord ? "用户记录" : "AI 总结" }
}
