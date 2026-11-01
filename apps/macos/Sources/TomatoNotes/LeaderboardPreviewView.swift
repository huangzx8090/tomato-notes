import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var controller: LeaderboardController
    var openAccount: () -> Void
    @ViewState private var requestedMode = "anonymous"
    @ViewState private var confirmingParticipation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                Text("专注排行榜").font(AppTypography.heading())
                Spacer()
                if controller.loggedIn {
                    Menu {
                        if controller.privacy?.participating == true {
                            Button("匿名展示") { controller.setParticipation(true, mode: "anonymous") }
                            Button("公开昵称和头像") { controller.setParticipation(true, mode: "public") }
                            Divider()
                            Button("停止参加") { controller.setParticipation(false, mode: controller.privacy?.displayMode ?? "anonymous") }
                        } else if controller.privacy != nil {
                            Button("匿名参加") { requestParticipation("anonymous") }
                            Button("公开昵称和头像参加") { requestParticipation("public") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30).background(Theme.surface, in: Circle())
                    }.menuStyle(.borderlessButton).fixedSize().disabled(controller.busy || controller.privacy == nil)
                        .accessibilityLabel("排行榜设置")
                }
            }
            if controller.loggedIn { boardCard } else { signedOutCard }
            if let message = controller.message {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("参加排行榜？", isPresented: $confirmingParticipation) {
            Button("取消", role: .cancel) {}
            Button("同意并参加") { controller.setParticipation(true, mode: requestedMode) }
        } message: {
            Text("开启后将上传授权后的实际专注时间区间和完成状态，用于计算每日排名；不上传待办、便签、专注目标或活动内容。关闭参与后将隐藏排名并停止上传，但已上传的记录不会自动删除。")
        }
    }

    private func requestParticipation(_ mode: String) {
        requestedMode = mode; confirmingParticipation = true
    }

    private var signedOutCard: some View {
        PaperCard {
            VStack(spacing: 11) {
                Image(systemName: "trophy")
                    .font(.system(size: 24)).foregroundStyle(Theme.accent)
                    .frame(width: 50, height: 50).background(Theme.accentSoft, in: Circle())
                Text("登录后查看排行榜").font(.system(size: 14, weight: .semibold))
                Button("前往登录", action: openAccount).buttonStyle(SubtleButtonStyle())
                    .accessibilityIdentifier("leaderboard.openAccount")
            }.frame(maxWidth: .infinity).padding(.vertical, 16)
        }
    }

    private var boardCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Button { controller.changeDay(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 26, height: 28).contentShape(Rectangle())
                    }.accessibilityLabel("前一天")
                    Text(controller.board?.date ?? "每日榜单")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(maxWidth: .infinity)
                    Button { controller.changeDay(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 26, height: 28).contentShape(Rectangle())
                    }.accessibilityLabel("后一天")
                        .disabled(controller.busy || controller.selectedDay == nil)
                    Button { controller.refresh() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 26, height: 28).contentShape(Rectangle())
                    }.accessibilityLabel("刷新排行榜").disabled(controller.busy)
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary)

                if let board = controller.board {
                    if board.items.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: "chart.bar.xaxis").font(.system(size: 21)).foregroundStyle(Theme.accent.opacity(0.7))
                            Text("还没有上榜记录").font(.system(size: 12, weight: .semibold))
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(board.items) { entry in
                                row(entry)
                                if entry.id != board.items.last?.id { Divider().opacity(0.5) }
                            }
                        }
                    }
                    if board.total > board.pageSize {
                        HStack {
                            Button("上一页") { controller.showPage(board.page - 1) }.disabled(controller.busy || board.page <= 1)
                            Spacer()
                            Text("\(board.page) / \((board.total + board.pageSize - 1) / board.pageSize)")
                                .monospacedDigit().foregroundStyle(Theme.secondary)
                            Spacer()
                            Button("下一页") { controller.showPage(board.page + 1) }
                                .disabled(controller.busy || board.page * board.pageSize >= board.total)
                        }.buttonStyle(.plain).font(.system(size: 11))
                    }
                    if let own = controller.own {
                        HStack(spacing: 9) {
                            ProfileAvatar(data: controller.profileAvatar, size: 28)
                            Text("我的排名").font(.system(size: 11, weight: .semibold))
                            Spacer(minLength: 0)
                            Text(ownText(own)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            if controller.privacy?.participating == false {
                                Button("参加") { requestParticipation("anonymous") }
                                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.accent).disabled(controller.busy)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else if controller.busy {
                    ProgressView("正在加载榜单…").controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    Text("暂时无法加载榜单，点右上角刷新。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
        }
    }

    private func row(_ entry: BoardEntry) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(entry.rank <= 3 ? Theme.accent : Theme.secondary).frame(width: 20)
            ProfileAvatar(data: controller.boardAvatars[entry.entryKey], size: 34)
            Text(entry.nickname + (entry.isMe ? " · 我" : ""))
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(profileDuration(entry.focusSeconds))
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(entry.rank) 名，\(entry.nickname)，专注 \(profileDuration(entry.focusSeconds))，完成 \(entry.completedSessions) 轮")
    }

    private func ownText(_ own: OwnRank) -> String {
        if let entry = own.entry { return "第 \(entry.rank) 名 · \(profileDuration(entry.focusSeconds))" }
        return own.status == "not_participating" ? "尚未参加排行榜" : "这一天暂无成绩"
    }
}
