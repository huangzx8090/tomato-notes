import SwiftUI
import TomatoCore

struct FocusGuardSettingsSection: View {
    @ObservedObject var state: AppState
    var openFocus: () -> Void
    var openAI: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("AI 建议优先，按需调整", systemImage: "list.bullet.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                    SettingsHelpText("开始专注时自动建议学习范围，手动勾选和标题关键词统一在默认折叠的「自己调整」中。")
                    Button("前往专注", action: openFocus).buttonStyle(SettingsButtonStyle())
                    Text("计时和时长统计在本机完成，AI 关闭由你在每轮单独授权。")
                        .font(.system(size: 10)).foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup("启动与提醒设置") {
                PaperCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("每轮怎样开始").font(.system(size: 13, weight: .semibold))
                        SettingsToggleRow(title: "开始前先选择白名单", detail: "开启后，点击「开始专注」会先让你确认本轮名单。",
                                          value: guardToggle(\.enabled))
                        Divider()
                        SettingsToggleRow(title: "沿用上轮目标与白名单", detail: reuseDescription,
                                          value: Binding(get: { state.settings.focusGuard.reuseLastPlan }, set: { value in
                            var next = state.settings
                            next.focusGuard.reuseLastPlan = value
                            next.focusGuard.rememberDraft(value ? state.guardController.plan : nil)
                            _ = state.updateSettings(next)
                        })).disabled(!state.settings.focusGuard.enabled)
                        SettingsHelpText("AI 关闭授权始终需要在当前轮次确认，不会沿用。")
                    }
                }
                PaperCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("离开白名单时").font(.system(size: 13, weight: .semibold))
                        SettingsToggleRow(title: "让 AI 判断当前页面是否与学习相关",
                                          detail: "开启后，离开目标超时会交给 AI 核对：判定相关就自动放行本轮，无关或无法确定时只提醒、不动窗口。需要已配置 AI 密钥，判定仍受每轮次数限制。",
                                          value: guardToggle(\.aiRelevance)).disabled(!state.settings.focusGuard.enabled)
                        Divider()
                        SettingsNumberRow(title: "停留多久后提醒", unit: "秒", bounds: 5...1800,
                                          value: integer(\.remindAfterSeconds, bounds: 5...1800))
                        SettingsHelpText("连续离开 \(state.settings.focusGuard.remindAfterSeconds) 秒时提醒你回来。返回白名单后重新计算；暂停时不检查。")
                        Divider()
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 13) {
                                SettingsHelpText("AI 检查 Chrome，其他 App 只提醒。自动判断相关性只放行不关闭，关闭前核对需在本轮单独授权。")
                                SettingsNumberRow(title: "提醒后再等待", unit: "秒", bounds: 5...600,
                                                  value: integer(\.graceSeconds, bounds: 5...600))
                                SettingsNumberRow(title: "每轮最多判断", unit: "次", bounds: 1...5,
                                                  value: integer(\.maxChecks, bounds: 1...5))
                                SettingsHelpText("先提醒 → 再等待 \(state.settings.focusGuard.graceSeconds) 秒 → 交给 AI 判断。无法确定或调用失败时，保留页面。")
                                if !state.hasAPIKey {
                                    Button("先配置 AI 助手", action: openAI).buttonStyle(SettingsButtonStyle())
                                }
                            }.padding(.top, 10)
                        } label: {
                            Text("AI 检查的等待与次数").font(.system(size: 12, weight: .medium))
                        }.tint(Theme.secondary)
                    }
                }
                PaperCard {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 11) {
                            SettingsHelpText("旧版常用网页仍保留，可在「自己调整」中勾选。新网页建议使用标题关键词归类。")
                            if state.settings.focusGuard.favoritePages.isEmpty {
                                SettingsHelpText("尚无旧版常用网页。请在专注窗口添加标题关键词。")
                            } else {
                                RuleChipsView(pages: state.settings.focusGuard.favoritePages, emptyHint: "") { rule in
                                    var next = state.settings
                                    next.focusGuard.favoritePages.removeAll { $0.id == rule.id }
                                    _ = state.updateSettings(next)
                                }
                            SettingsHelpText("点击 × 移除规则，更改自动保存。")
                            }
                        }.padding(.top, 10)
                    } label: {
                        HStack {
                            Label("常用网页白名单", systemImage: "star").font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(state.settings.focusGuard.favoritePages.count) 条")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }.tint(Theme.secondary)
                }
            }.tint(Theme.secondary)
            SettingsHelpText("这里的开关和数值会自动保存。本轮白名单在「专注」中调整。")
                .padding(.horizontal, 3)
        }
    }

    private var reuseDescription: String {
        let settings = state.settings.focusGuard
        if settings.reuseLastPlan && settings.hasLastPlan {
            return "已保存 \(settings.lastAppIDs.count) 个 App、\(settings.lastPages.count) 条网页规则；下轮优先获取新的 AI 建议。"
        }
        return "开启后，保存一次本轮名单；作为手动候选保留；AI 成功时优先使用新建议。"
    }

    private func guardToggle(_ key: WritableKeyPath<FocusGuardSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.settings.focusGuard[keyPath: key] }, set: { value in
            var next = state.settings; next.focusGuard[keyPath: key] = value; _ = state.updateSettings(next)
        })
    }

    private func integer(_ key: WritableKeyPath<FocusGuardSettings, Int>, bounds: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { state.settings.focusGuard[keyPath: key] }, set: { value in
            var next = state.settings
            next.focusGuard[keyPath: key] = min(bounds.upperBound, max(bounds.lowerBound, value))
            _ = state.updateSettings(next)
        })
    }
}
