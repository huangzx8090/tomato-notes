import SwiftUI
import TomatoCore

struct FocusWhitelistPickerHeader: View {
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("这轮允许用什么").font(.system(size: 20, weight: .semibold))
                Text("勾选这轮需要的应用和网页，离开它们太久时提醒你。")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).accessibilityLabel("取消选择")
        }.padding(22)
    }
}

struct FocusWhitelistGoalCard: View {
    @Binding var goal: String
    let todos: [TodoItem]
    let canGenerate: Bool
    let isGenerating: Bool
    let hasGenerated: Bool
    let status: String
    let providerName: String
    let hasKey: Bool
    var onGenerate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("这轮做什么").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if isGenerating {
                        ProgressView().controlSize(.small)
                        Button("取消生成", action: onCancel).buttonStyle(SubtleButtonStyle())
                    } else {
                        Button(action: onGenerate) {
                            Label(hasGenerated ? "重新生成" : "AI 起名", systemImage: "sparkles")
                        }.buttonStyle(SubtleButtonStyle())
                            .disabled(!canGenerate)
                            .accessibilityLabel("根据本轮白名单生成学习名称")
                    }
                    if !todos.isEmpty {
                        Menu("从待办选择") {
                            ForEach(todos) { todo in Button(todo.text) { goal = todo.text } }
                        }.font(.system(size: 11))
                    }
                }
                TextField("可先勾选下方白名单，让 AI 自动起名，也可手动填写", text: $goal)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("本轮目标")
                    .accessibilityIdentifier("guard.goal")
                if goal.count > 300 {
                    Text("目标请控制在 300 字内").font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                Text("AI 会在名称为空时，根据已选白名单补全；手写名称会保留。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text("起名仅将已选 App 名称、网页标题与网站发送给 \(providerName)。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if !status.isEmpty {
                    Text(status).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if !hasKey {
                    Text("自动起名需先在设置 → AI 助手中保存 API Key 并选择模型，也可直接手动填写。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

struct FocusWhitelistAppChecklist: View {
    let apps: [AppIdentity]
    let selectedIDs: Set<String>
    var onSet: (String, Bool) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(apps, id: \.bundleID) { app in
                Toggle(isOn: Binding(get: { selectedIDs.contains(app.bundleID) }, set: { onSet(app.bundleID, $0) })) {
                    Text(app.name).font(.system(size: 12)).lineLimit(2)
                }.toggleStyle(.checkbox)
                    .help(app.name).accessibilityLabel("允许使用应用：\(app.name)")
                    .accessibilityIdentifier("guard.app.\(app.bundleID)")
            }
        }
    }
}

struct FocusWhitelistPageChecklist: View {
    let pages: [GuardPage]
    let rules: [FocusPageRule]
    @Binding var filter: String
    var onSet: (GuardPage, Bool) -> Void
    var onSetVisible: ([GuardPage], Bool) -> Void
    var onRemoveRule: (FocusPageRule) -> Void

    private var eligible: [GuardPage] { FocusWhitelistSelection.uniquePages(pages) }
    private var visible: [GuardPage] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return eligible.filter { query.isEmpty || ($0.title + " " + $0.host).localizedCaseInsensitiveContains(query) }
    }
    private struct PageGroup: Identifiable {
        let host: String
        let pages: [GuardPage]
        var id: String { host }
    }
    private var groups: [PageGroup] {
        Dictionary(grouping: visible, by: \.host).map { PageGroup(host: $0.key, pages: $0.value) }
            .sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
    }
    private var unlistedRules: [FocusPageRule] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let openedKeys = Set(eligible.compactMap { FocusPageRule.pageKey($0.url) })
        return rules.filter { rule in
            rule.kind == .page && !openedKeys.contains(rule.value) &&
                (query.isEmpty || (rule.title + " " + rule.value).localizedCaseInsensitiveContains(query))
        }
    }
    private var visibleAllSelected: Bool { !visible.isEmpty && visible.allSatisfy { FocusWhitelistSelection.isAllowed($0, rules: rules) } }
    private var repeatedTitles: Set<String> {
        Set(Dictionary(grouping: eligible, by: \.title).filter { $0.value.count > 1 }.map(\.key))
    }

    var body: some View {
        let duplicates = repeatedTitles
        VStack(alignment: .leading, spacing: 12) {
            if !eligible.isEmpty {
                HStack(spacing: 12) {
                    TextField("搜索网页标题或网站", text: $filter).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("搜索待勾选的网页")
                    Toggle("全选", isOn: Binding(get: { visibleAllSelected }, set: { onSetVisible(visible, $0) }))
                        .toggleStyle(.checkbox).font(.system(size: 11)).fixedSize()
                        .disabled(visible.isEmpty)
                        .help("仅勾选或取消搜索结果中当前打开的网页")
                        .accessibilityLabel("全选搜索结果中当前打开的网页")
                }
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.host).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                    ForEach(group.pages) { page in
                        Toggle(isOn: Binding(get: { FocusWhitelistSelection.isAllowed(page, rules: rules) }, set: { onSet(page, $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(page.title.isEmpty ? page.host : page.title)
                                    .font(.system(size: 12)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                if duplicates.contains(page.title) {
                                    Text(FocusPageRule.pageKey(page.url) ?? page.host)
                                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.toggleStyle(.checkbox).padding(.vertical, 5)
                            .accessibilityLabel("允许使用网页：\(page.title.isEmpty ? page.host : page.title)")
                            .accessibilityIdentifier("guard.page.\(page.windowID).\(page.tabID)")
                    }
                }
            }
            if !filter.isEmpty && visible.isEmpty && !eligible.isEmpty {
                Text("没有匹配的网页").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            if !unlistedRules.isEmpty {
                Divider()
                Text("已勾选，当前未打开").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                ForEach(unlistedRules) { rule in
                    Toggle(isOn: Binding(get: { rules.contains { $0.id == rule.id } }, set: { if !$0 { onRemoveRule(rule) } })) {
                        Text(rule.title).font(.system(size: 12)).lineLimit(2)
                    }.toggleStyle(.checkbox)
                }
            }
        }
    }
}
