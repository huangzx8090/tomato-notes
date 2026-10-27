import SwiftUI

struct LeaderboardPreviewView: View {
    @ViewState private var period: PreviewPeriod = .week

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("专注时长排行").font(.system(size: 21, weight: .semibold))
                        Text("样式预览")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                    Text("每一份专注，都值得被看见。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13))
            }

            HStack(spacing: 4) {
                ForEach(PreviewPeriod.allCases, id: \.self) { option in
                    Button { period = option } label: {
                        Text(option.rawValue).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(period == option ? Theme.accent : Theme.secondary)
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background {
                                if period == option {
                                    RoundedRectangle(cornerRadius: 9).fill(Theme.surface)
                                        .shadow(color: Theme.primary.opacity(0.05), radius: 3, y: 1)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(period == option ? .isSelected : [])
                    .accessibilityIdentifier("leaderboard.period.\(option.rawValue)")
                }
            }
            .padding(4)
            .background(Theme.border.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))

            PaperCard {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(period.rawValue)榜单").font(.system(size: 15, weight: .semibold))
                            Text("按专注时长排序").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text("示例数据").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }

                    ForEach(Array(period.entries.enumerated()), id: \.offset) { index, entry in
                        leaderboardRow(entry, rank: index + 1, maximumMinutes: period.entries[0].minutes)
                    }
                }
            }

            Label("排行榜功能筹备中，当前仅展示示例样式。", systemImage: "sparkles")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func leaderboardRow(_ entry: PreviewEntry, rank: Int, maximumMinutes: Int) -> some View {
        HStack(spacing: 11) {
            Text(String(format: "%02d", rank))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(rank == 1 ? Theme.accent : Theme.secondary)
                .frame(width: 20)
            Text(entry.avatar)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(rank == 1 ? Theme.accent : Theme.green)
                .frame(width: 35, height: 35)
                .background(rank == 1 ? Theme.accentSoft : Theme.greenSoft, in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 5)
                    Text(entry.duration).font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(Theme.border.opacity(0.45))
                    Capsule().fill(rank == 1 ? Theme.accent : Theme.green.opacity(0.65))
                        .frame(width: geometry.size.width * CGFloat(entry.minutes) / CGFloat(maximumMinutes))
                }.frame(height: 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("示例，第 \(rank) 名，\(entry.name)，\(entry.duration)")
    }
}

private struct PreviewEntry {
    let name: String
    let avatar: String
    let minutes: Int

    var duration: String { "\(minutes / 60) 小时 \(minutes % 60) 分" }
}

private enum PreviewPeriod: String, CaseIterable {
    case day = "今日", week = "本周", month = "本月"

    var entries: [PreviewEntry] {
        let minutes: [Int]
        switch self {
        case .day: minutes = [175, 130, 85]
        case .week: minutes = [520, 380, 275]
        case .month: minutes = [1860, 1480, 1090]
        }
        return [
            PreviewEntry(name: "山间来信", avatar: "山", minutes: minutes[0]),
            PreviewEntry(name: "慢慢发芽", avatar: "芽", minutes: minutes[1]),
            PreviewEntry(name: "橘子汽水", avatar: "橘", minutes: minutes[2])
        ]
    }
}
