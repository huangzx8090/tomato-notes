import AppKit
import ImageIO
import SwiftUI
import TomatoCore
import UniformTypeIdentifiers

/// 个人头像始终保留清晰的离线回退；网络图片只保存在本次内存中。
struct ProfileAvatar: View {
    let data: Data?
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accentSoft)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(Theme.border.opacity(0.8), lineWidth: 0.7))
        .accessibilityHidden(true)
    }
}

struct TodayProfileHeader: View {
    @ObservedObject var state: AppState
    @ObservedObject var account: LeaderboardController
    @Binding var showsAccount: Bool

    var body: some View {
        let seconds = state.data.intervals.reduce(0) { $0 + $1.seconds }
        let days = Set(state.data.intervals.filter { $0.seconds > 0 }.map(\.localDay)).count
        let completed = state.data.sessions.filter(\.completed).count
        PaperCard {
            VStack(spacing: 15) {
                HStack(spacing: 12) {
                    ProfileAvatar(data: account.profileAvatar, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.loggedIn ? (account.nickname.isEmpty ? "我的专注" : account.nickname) : "我的专注")
                            .font(AppTypography.heading(16)).lineLimit(1)
                        if account.loggedIn, let username = account.profile?.username {
                            Text("@\(username)").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Button(account.loggedIn ? "编辑资料" : "登录") { showsAccount = true }
                        .buttonStyle(SubtleButtonStyle())
                        .accessibilityIdentifier("profile.open")
                }
                HStack(spacing: 0) {
                    metric(profileDuration(seconds), "累计专注")
                    separator
                    metric("\(days) 天", "专注天数")
                    separator
                    metric("\(completed) 轮", "完成番茄")
                }
                .padding(.vertical, 10)
                .background(Theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("本机累计专注 \(profileDuration(seconds))，专注 \(days) 天，完成 \(completed) 轮")
            }
        }
        .sheet(isPresented: $showsAccount) { AccountSheet(controller: account) }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity)
    }
    private var separator: some View { Rectangle().fill(Theme.border).frame(width: 1, height: 24) }
}

func profileDuration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    if value < 60 { return "\(value) 秒" }
    let minutes = value / 60
    if minutes < 60 { return "\(minutes) 分钟" }
    return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
}

private struct AccountSheet: View {
    @ObservedObject var controller: LeaderboardController
    @Environment(\.dismiss) private var dismiss
    @ViewState private var username = ""
    @ViewState private var password = ""
    @ViewState private var nicknameDraft = ""
    @ViewState private var selectingAvatar = false
    @ViewState private var removingAvatar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(controller.loggedIn ? "个人资料" : "登录番茄小记")
                    .font(AppTypography.heading(19))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("关闭")
            }.padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if controller.loggedIn { profile } else { login }
                    if let message = controller.message {
                        Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
        }
        .padding(20).frame(width: 370, height: 430)
        .background(Theme.background).foregroundStyle(Theme.primary)
        .onAppear { nicknameDraft = controller.nickname }
        .onChange(of: controller.nickname) { old, new in
            if nicknameDraft == old || nicknameDraft.isEmpty { nicknameDraft = new }
        }
        .fileImporter(isPresented: $selectingAvatar, allowedContentTypes: [.png, .jpeg, .gif]) { result in
            switch result {
            case .success(let url): readAvatar(url)
            case .failure(let error): controller.message = "无法选择头像：\(error.localizedDescription)"
            }
        }
        .alert("移除头像？", isPresented: $removingAvatar) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) { controller.removeAvatar() }
        } message: { Text("移除后将显示默认头像。") }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Spacer(); ProfileAvatar(data: nil, size: 64); Spacer() }
            Text("请使用邀请注册的账号登录。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            TextField("用户名", text: $username).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account.username")
            SecureField("密码", text: $password).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account.password")
            Text("已参加排行榜的账号将同步授权后的本机专注时段。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("登录") {
                let secret = password; password = ""
                controller.login(username: username, password: secret)
            }.buttonStyle(PrimaryButtonStyle())
                .disabled(controller.busy || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                .accessibilityIdentifier("account.login")
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProfileAvatar(data: controller.profileAvatar, size: 62)
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.nickname.isEmpty ? "我的账号" : controller.nickname)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if let username = controller.profile?.username {
                        Text("@\(username)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    HStack(spacing: 12) {
                        Button("更换头像") { selectingAvatar = true }.help("PNG、JPG 或 GIF，最大 5 MiB；显示首帧")
                        if controller.profile?.avatarUrl != nil {
                            Button("移除") { removingAvatar = true }
                        }
                    }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent).disabled(controller.busy)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("昵称").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                HStack(spacing: 8) {
                    TextField("输入昵称", text: $nicknameDraft).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("account.nickname")
                    Button("保存") { controller.updateNickname(nicknameDraft) }
                        .buttonStyle(SubtleButtonStyle())
                        .disabled(controller.busy || nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nicknameDraft == controller.nickname)
                }
            }
            Divider()
            HStack {
                Spacer(minLength: 4)
                Button("退出登录") { controller.logout() }.buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    .disabled(controller.busy)
            }
        }
    }

    private func readAvatar(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 5 * 1024 * 1024 else {
                controller.message = "请选择不超过 5 MiB 的图片。"; return
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source) as String?,
                  let type = UTType(identifier),
                  let mime = type.preferredMIMEType,
                  ["image/png", "image/jpeg", "image/gif"].contains(mime) else {
                controller.message = "请选择有效的 PNG、JPG 或 GIF 图片。"; return
            }
            controller.uploadAvatar(data, mime: mime)
        } catch { controller.message = "读取头像失败：\(error.localizedDescription)" }
    }
}
