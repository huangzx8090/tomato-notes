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
                    Label("先选白名单，再开始这一轮", systemImage: "list.bullet.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                    SettingsHelpText("在「专注 → 设置并开始专注」中，选择本轮允许使用的 App 和 Chrome 网页。离开后会提醒；结束时，在进展中查看白名单外 App 停留时长。")
                    Button("前往专注设置白名单", action: openFocus).buttonStyle(SettingsButtonStyle())
                    Text("计时和时长统计在本机完成，AI 关闭由你在每轮单独授权。")
                        .font(.system(size: 10)).foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                    SettingsNumberRow(title: "停留多久后提醒", unit: "秒", bounds: 5...1800,
                                      value: integer(\.remindAfterSeconds, bounds: 5...1800))
                    SettingsHelpText("连续离开 \(state.settings.focusGuard.remindAfterSeconds) 秒时提醒你回来。返回白名单后重新计算；暂停时不检查。")
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 13) {
                            SettingsHelpText("下面两项只在本轮允许 AI 关闭网页时生效。AI 检查 Chrome，其他 App 只提醒。")
                            SettingsNumberRow(title: "提醒后再等待", unit: "秒", bounds: 5...600,
                                              value: integer(\.graceSeconds, bounds: 5...600))
                            SettingsNumberRow(title: "每轮最多判断", unit: "次", bounds: 1...5,
                                              value: integer(\.maxChecks, bounds: 1...5))
                            SettingsHelpText("先提醒 → 再等待 \(state.settings.focusGuard.graceSeconds) 秒 → 按本轮授权判断。无法确定或调用失败时，保留页面。")
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
                        SettingsHelpText("在每轮名单弹窗中点击「存为常用」，下次可手动导入本轮。应用名单可通过「沿用上轮」复用。")
                        if state.settings.focusGuard.favoritePages.isEmpty {
                            SettingsHelpText("还没有常用网页规则。先在一轮专注中选好网页并保存。")
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
            SettingsHelpText("这里的开关和数值会自动保存。本轮白名单在「专注」中调整。")
                .padding(.horizontal, 3)
        }
    }

    private var reuseDescription: String {
        let settings = state.settings.focusGuard
        if settings.reuseLastPlan && settings.hasLastPlan {
            return "已保存 \(settings.lastAppIDs.count) 个 App、\(settings.lastPages.count) 条网页规则；下轮会直接使用。"
        }
        return "开启后，保存一次本轮名单；之后使用相同目标和名单，减少重复选择。"
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
