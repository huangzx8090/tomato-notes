import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var controller: LeaderboardController
    @ViewState private var username = ""
    @ViewState private var password = ""
    @ViewState private var displayMode = "anonymous"
    @ViewState private var confirmingParticipation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("专注时长排行").font(.system(size: 21, weight: .semibold))
                    Text("每一份专注，都值得被看见。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13))
            }
            if controller.loggedIn { signedIn } else { login }
            if let message = controller.message {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("参加排行榜？", isPresented: $confirmingParticipation) {
            Button("取消", role: .cancel) {}
            Button("同意并参加") { controller.setParticipation(true, mode: displayMode) }
        } message: {
            Text("开启后将上传授权后的实际专注时间区间和完成状态，用于计算每日排名；不上传待办、便签、专注目标或活动内容。关闭参与后将隐藏排名并停止上传，但已上传的记录不会自动删除。")
        }
    }

    private var login: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("登录查看排行榜").font(.system(size: 15, weight: .semibold))
                Text("账号需通过管理员提供的邀请链接注册。新账号默认不参加；已参加的账号登录后会同步授权后的本机专注时段。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("用户名", text: $username).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("leaderboard.username")
                SecureField("密码", text: $password).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("leaderboard.password")
                Button("登录") {
                    let secret = password
                    password = ""
                    controller.login(username: username, password: secret)
                }
                .buttonStyle(SubtleButtonStyle())
                .disabled(controller.busy || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                .accessibilityIdentifier("leaderboard.login")
            }
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(controller.nickname.isEmpty ? "已登录" : "你好，\(controller.nickname)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("刷新") { controller.refresh() }.disabled(controller.busy)
                        Button("退出登录") { controller.logout() }.disabled(controller.busy)
                    }.font(.system(size: 11))
                    if let privacy = controller.privacy {
                        if privacy.participating {
                            Text("已参加 · \(privacy.displayMode == "anonymous" ? "匿名显示" : "公开昵称")")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            HStack {
                                Button(privacy.displayMode == "anonymous" ? "改为公开昵称" : "改为匿名") {
                                    controller.setParticipation(true, mode: privacy.displayMode == "anonymous" ? "public" : "anonymous")
                                }
                                Button("停止参加") { controller.setParticipation(false, mode: privacy.displayMode) }
                            }.font(.system(size: 11)).disabled(controller.busy)
                        } else {
                            Text("尚未参加；仍可查看他人公开的榜单。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            HStack {
                                Picker("显示方式", selection: $displayMode) {
                                    Text("匿名").tag("anonymous")
                                    Text("公开昵称").tag("public")
                                }.frame(width: 150)
                                Button("参加排行榜") { confirmingParticipation = true }.disabled(controller.busy)
                            }.font(.system(size: 11))
                        }
                    } else { Text("正在读取参与设置…").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                }
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("每日榜单").font(.system(size: 15, weight: .semibold))
                            Text("上海时间 · 按有效专注时长排序").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if controller.busy { ProgressView().controlSize(.small) }
                    }
                    if let board = controller.board {
                        HStack {
                            Button { controller.changeDay(-1) } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            Text(board.date).font(.system(size: 12, weight: .medium).monospacedDigit())
                            Spacer()
                            Button { controller.changeDay(1) } label: { Image(systemName: "chevron.right") }
                        }.buttonStyle(.plain).disabled(controller.busy)
                        Text(board.state == "live" ? "今日实时榜" : (board.state == "provisional" ? "暂定榜单" : "已结算"))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        if board.items.isEmpty {
                            Text("这一天暂时没有可显示的成绩。")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        } else {
                            ForEach(board.items) { entry in
                                row(entry, maxSeconds: board.items.first?.focusSeconds ?? 1)
                            }
                        }
                        HStack {
                            Button("上一页") { controller.showPage(board.page - 1) }.disabled(controller.busy || board.page <= 1)
                            Spacer()
                            Text("第 \(board.page) 页 · 共 \(board.total) 人")
                            Spacer()
                            Button("下一页") { controller.showPage(board.page + 1) }.disabled(controller.busy || board.page * board.pageSize >= board.total)
                        }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        if let own = controller.own {
                            Divider()
                            Text(ownText(own)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    } else if !controller.busy {
                        Text("榜单尚未加载，请点击刷新。")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private func row(_ entry: BoardEntry, maxSeconds: Double) -> some View {
        HStack(spacing: 11) {
            Text(String(format: "%02d", entry.rank))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(entry.rank == 1 ? Theme.accent : Theme.secondary).frame(width: 24)
            Text(String(entry.nickname.prefix(1)))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                .frame(width: 35, height: 35).background(Theme.greenSoft, in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(entry.nickname + (entry.isMe ? "（我）" : ""))
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 5)
                    Text(duration(entry.focusSeconds)).font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(Theme.border.opacity(0.45))
                    Capsule().fill(Theme.green.opacity(0.65))
                        .frame(width: geometry.size.width * CGFloat(min(1, max(0, entry.focusSeconds / max(1, maxSeconds)))))
                }.frame(height: 4)
            }
        }.accessibilityElement(children: .combine)
            .accessibilityLabel("第 \(entry.rank) 名，\(entry.nickname)，\(duration(entry.focusSeconds))")
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }
    private func ownText(_ own: OwnRank) -> String {
        if let entry = own.entry { return "我的排名：第 \(entry.rank) 名 · \(duration(entry.focusSeconds))" }
        return own.status == "not_participating" ? "我尚未参加排行榜。" : "我在这一天暂无成绩。"
    }
}
