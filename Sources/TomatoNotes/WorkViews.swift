import AppKit
import SwiftUI
import TomatoCore
import UniformTypeIdentifiers

struct WorkReportView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var state: AppState
    let scope: WorkScope
    var configureAI: () -> Void

    private var record: WorkRecord? { state.workRecord(for: scope) }
    private var busy: Bool { state.generatingScopes.contains(scope.key) }
    private var title: String {
        switch scope {
        case .session: "这一轮，做了什么"
        case .day(let day): "\(day) · 每日回顾"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 24, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("补充工作和成果", systemImage: "square.and.pencil").font(.system(size: 14, weight: .semibold))
                        Text("可以写几句，也可以直接添加成果截图、作业或文档图片。")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        TextEditor(text: Binding(get: { record?.userText ?? "" }, set: { state.updateWorkText($0, for: scope) }))
                            .font(.system(size: 14)).scrollContentBackground(.hidden)
                            .padding(9).frame(minHeight: 105, maxHeight: 180)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityLabel("工作和成果描述")
                        if let images = record?.images, !images.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(images) { image in
                                        VStack(alignment: .leading, spacing: 5) {
                                            WorkImagePreview(url: state.workImages.url(for: image))
                                                .frame(width: 126, height: 94).clipped()
                                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            HStack(spacing: 4) {
                                                Text(image.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                                Button { state.removeWorkImage(image.id, from: scope) } label: { Image(systemName: "xmark.circle.fill") }
                                                    .buttonStyle(.plain).accessibilityLabel("移除图片：\(image.name)").disabled(busy)
                                            }.font(.system(size: 10)).foregroundStyle(Theme.secondary).frame(width: 126)
                                        }
                                    }
                                }
                            }
                        }
                        HStack {
                            Button(action: chooseImages) { Label("添加图片", systemImage: "photo.badge.plus") }
                                .buttonStyle(SubtleButtonStyle()).disabled(busy || (record?.images.count ?? 0) >= 6)
                            Text("\(record?.images.count ?? 0) / 6 张").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text("文字自动保存").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button { state.generateReview(for: scope) } label: {
                        HStack {
                            if busy { ProgressView().controlSize(.small).tint(.white) }
                            Text(busy ? "AI 正在整理文字与图片…" : (record?.summary == nil ? "让 AI 总结工作与成果" : "重新生成 AI 总结"))
                            if !busy { Image(systemName: "sparkles") }
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(busy || !state.canWrite)
                    Text("生成时会将本轮或当天的记录、补充文字及所选图片发送给 DeepSeek。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if !state.hasAPIKey {
                        Button("先配置 DeepSeek API Key", action: configureAI).buttonStyle(.plain)
                            .font(.system(size: 12)).foregroundStyle(Theme.accent)
                    }
                    if let error = state.reviewErrors[scope.key] {
                        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let summary = record?.summary {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 17) {
                            HStack {
                                Label("AI 成果总结", systemImage: "sparkles").font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Button("复制") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(summary.content.markdown, forType: .string)
                                }.buttonStyle(SubtleButtonStyle())
                            }
                            Text("生成于 \(summary.generatedAt.formatted(date: .omitted, time: .shortened)) · \(summary.model)")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            if summary.contextDigest != ReviewContextBuilder.build(for: scope, from: state.data).digest {
                                Text("生成后有新记录或修改，可以重新生成。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
                            }
                            SummarySections(content: summary.content)
                            Text("AI 可能理解有误，请结合原始文字和图片核对。")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                } else {
                    Text("AI 会把有依据的工作、成果、待继续事项和需要确认的信息分开整理。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                }
            }.padding(25)
        }.background(Theme.background.opacity(reduceTransparency ? 1 : 0.22)).foregroundStyle(Theme.primary).preferredColorScheme(.light)
            .frame(minWidth: 540, minHeight: 500)
            .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private var subtitle: String {
        switch scope {
        case .session(let id):
            let seconds = state.data.intervals.filter { $0.sessionID == id }.reduce(0) { $0 + $1.seconds }
            return "本轮实际投入 \(durationLabel(seconds))。补充做过的事，让 AI 整理出更具体的成果。"
        case .day: return "结合当天各轮专注、成果图片、待办和你的补充，整理今天一整天的进展。"
        }
    }

    private func chooseImages() {
        let picker = NSOpenPanel()
        picker.title = "选择工作或成果图片"
        picker.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.begin { result in
            guard result == .OK else { return }
            let urls = picker.urls
            Task { @MainActor in state.importWorkImages(urls, for: scope) }
        }
    }
}

private struct WorkImagePreview: View {
    let url: URL
    @ViewState private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(Theme.secondary) }
        }.onAppear { image = NSImage(contentsOf: url) }
    }
}

struct SummarySections: View {
    let content: WorkSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("做了什么", lines: content.activities, symbol: "checklist")
            section("取得的成果", lines: content.outcomes, symbol: "checkmark.seal")
            section("待继续", lines: content.nextSteps, symbol: "arrow.right.circle")
            section("待确认", lines: content.uncertainties, symbol: "questionmark.circle")
        }.textSelection(.enabled)
    }
    @ViewBuilder private func section(_ title: String, lines: [String], symbol: String) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 7) {
                        Text("•").foregroundStyle(Theme.secondary)
                        Text(line).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ReviewSettingsSection: View {
    @ObservedObject var state: AppState
    var requestNotifications: () -> Void
    @ViewState private var apiKey = ""
    @ViewState private var hour = "21"
    @ViewState private var minute = "30"
    @ViewState private var validation: String?

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("AI 工作与成果回顾", systemImage: "sparkles").font(.system(size: 14, weight: .semibold))
                Text("DeepSeek · 支持文字与图片理解")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                SecureField(state.hasAPIKey ? "已配置，输入可更换" : "填写 DeepSeek API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("DeepSeek API Key")
                HStack(spacing: 8) {
                    Button("保存密钥") { state.saveAPIKey(apiKey); apiKey = "" }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(state.testingAI ? "连接中…" : "测试连接", action: state.testAIConnection).disabled(state.testingAI)
                    Button("刷新", action: state.refreshCredentialStatus)
                }.buttonStyle(SubtleButtonStyle())
                Text(state.aiStatus).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("密钥保存在本机钥匙串；支持导入 deepseek / DEEPSEEK_API_KEY 环境变量。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle("每天定时生成 AI 回顾", isOn: Binding(get: { state.settings.review.scheduleEnabled }, set: { value in
                    var settings = state.settings
                    settings.review.scheduleEnabled = value
                    if state.updateSettings(settings), value { requestNotifications() }
                })).font(.system(size: 12))
                HStack(spacing: 8) {
                    Text("每天").font(.system(size: 12))
                    timeField($hour, label: "回顾小时")
                    Text(":")
                    timeField($minute, label: "回顾分钟")
                    Spacer()
                    Button("保存时间", action: saveTime).buttonStyle(SubtleButtonStyle())
                }
                if let validation { Text(validation).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                Text("应用运行时，每天 \(state.settings.review.timeLabel) 汇总当天所有专注成果。当天错过时间，启动或解锁后补生成；生成失败可手动重试。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("定时汇总会将当天的记录、补充文字和待解析图片发送给 DeepSeek。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if state.hasAPIKey {
                    Button("移除已保存的密钥", action: state.removeAPIKey).buttonStyle(.plain)
                        .font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
            }
        }.onAppear {
            hour = String(format: "%02d", state.settings.review.hour)
            minute = String(format: "%02d", state.settings.review.minute)
            state.refreshCredentialStatus()
        }
    }

    private func timeField(_ value: Binding<String>, label: String) -> some View {
        TextField("00", text: value).textFieldStyle(.plain).multilineTextAlignment(.center)
            .font(.system(size: 13).monospacedDigit()).frame(width: 30).padding(7)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel(label)
    }

    private func saveTime() {
        guard let h = Int(hour), (0...23).contains(h), let m = Int(minute), (0...59).contains(m) else {
            validation = "请填写 00–23 的小时和 00–59 的分钟。"; return
        }
        var settings = state.settings
        settings.review.hour = h
        settings.review.minute = m
        if state.updateSettings(settings) { validation = nil }
    }
}

@MainActor
final class WorkWindows {
    private let state: AppState
    private var windows: [WorkScope: WorkWindowController] = [:]
    var onConfigureAI: (() -> Void)?
    init(state: AppState) { self.state = state }
    func open(_ scope: WorkScope) {
        guard state.canWrite else { return }
        state.ensureWorkRecord(for: scope)
        let controller: WorkWindowController
        if let existing = windows[scope] { controller = existing }
        else {
            controller = WorkWindowController(state: state, scope: scope, configureAI: { [weak self] in self?.onConfigureAI?() })
            windows[scope] = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class WorkWindowController: NSWindowController, NSWindowDelegate {
    let state: AppState
    init(state: AppState, scope: WorkScope, configureAI: @escaping () -> Void) {
        self.state = state
        let height = min(730, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: height),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = { if case .day = scope { return "每日 AI 回顾" }; return "本轮 AI 成果" }()
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.contentView = makeGlassHostingView(rootView: WorkReportView(state: state, scope: scope, configureAI: configureAI),
                                                  size: NSSize(width: 630, height: height))
        window.minSize = NSSize(width: 560, height: 540)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { state.flushWorkChanges() }
}
