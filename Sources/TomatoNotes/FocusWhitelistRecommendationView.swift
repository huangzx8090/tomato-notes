import SwiftUI
import TomatoCore
import TomatoSystem

struct FocusWhitelistRecommendationView: View {
    @ObservedObject var model: FocusWhitelistRecommender
    var providerName: String
    var hasKey: Bool
    var canRecommend: Bool
    var onRecommend: () -> Void
    @ViewState private var optionalExpanded = false
    @ViewState private var excludedExpanded = false

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("让 AI 帮你选白名单", systemImage: "sparkles").font(.system(size: 13, weight: .semibold))
                Text("读取当前运行的 App 和 Chrome 所有普通窗口的网页，按本轮目标逐项推荐，由你确认。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if model.loading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("取消推荐") { model.cancel(message: "已取消推荐，可继续手动选择。") }
                            .buttonStyle(SubtleButtonStyle())
                    }
                } else {
                    Button(model.suggestions.isEmpty ? "读取当前 App 与网页并推荐" : "重新读取并推荐", action: onRecommend)
                        .buttonStyle(SubtleButtonStyle()).disabled(!hasKey || !canRecommend)
                        .accessibilityLabel("AI 推荐本轮白名单")
                    Text("将目标、App 名称、网页标题与网站发送给 \(providerName)。网页仅放行勾选的页面。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if !hasKey {
                        Text("先在设置 → AI 助手中保存 API Key 并选择模型。")
                            .font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    if !model.status.isEmpty { Text(model.status).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                }
                if let error = model.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                }
                if !model.suggestions.isEmpty {
                    HStack {
                        Text("待确认 · 已勾选 \(model.selectedIDs.count) 项").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("只选推荐项") {
                            model.selectedIDs = Set(model.suggestions.filter { $0.disposition == .recommended }.map(\.id))
                        }.buttonStyle(SubtleButtonStyle())
                        Button("全不选") { model.selectedIDs = [] }.buttonStyle(SubtleButtonStyle())
                    }
                    if count(.recommended) > 0 {
                        Text("推荐使用（\(count(.recommended))）").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.green)
                        rows(.recommended)
                    }
                    if count(.optional) > 0 {
                        DisclosureGroup("可能需要（\(count(.optional))）", isExpanded: $optionalExpanded) { rows(.optional).padding(.top, 8) }
                            .font(.system(size: 11)).tint(Theme.secondary)
                    }
                    if count(.excluded) > 0 {
                        DisclosureGroup("不推荐（\(count(.excluded))）", isExpanded: $excludedExpanded) { rows(.excluded).padding(.top, 8) }
                            .font(.system(size: 11)).tint(Theme.secondary)
                    }
                    Text("勾选的建议将在下方确认本轮时加入白名单，已手选的项目保留。")
                        .font(.system(size: 11)).foregroundStyle(Theme.green).fixedSize(horizontal: false, vertical: true)
                    Text("推荐用量：输入 \(model.inputTokens) / 输出 \(model.outputTokens) Tokens")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func count(_ disposition: FocusWhitelistDisposition) -> Int {
        model.suggestions.filter { $0.disposition == disposition }.count
    }

    private func rows(_ disposition: FocusWhitelistDisposition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.suggestions.filter { $0.disposition == disposition }) { suggestion in
                if let item = model.snapshot?.items.first(where: { $0.id == suggestion.id }) {
                    Toggle(isOn: Binding(get: { model.selectedIDs.contains(item.id) }, set: { value in
                        if value { model.selectedIDs.insert(item.id) } else { model.selectedIDs.remove(item.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(item.candidate.name, systemImage: item.pageRule == nil ? "app" : "globe")
                                .font(.system(size: 12, weight: .medium)).lineLimit(2)
                            if item.pageRule != nil {
                                Text(item.candidate.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                if let rule = item.pageRule {
                                    Text(rule.value).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                        .lineLimit(1).truncationMode(.middle).help(rule.value)
                                }
                            }
                            Text(suggestion.reason).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.toggleStyle(.checkbox)
                }
            }
        }
    }
}
