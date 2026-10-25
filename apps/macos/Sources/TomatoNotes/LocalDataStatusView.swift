import AppKit
import SwiftUI

struct LocalDataStatusView: View {
    @ObservedObject var state: AppState
    @ViewState private var showingDetails = false

    private var shared: Bool { state.repository.isSharedLibrary }

    var body: some View {
        Button { showingDetails = true } label: {
            HStack(spacing: 6) {
                Image(systemName: shared ? "internaldrive" : "testtube.2")
                Text(shared ? "本机共用资料" : "独立测试资料 · 与日常记录分开保存")
                Spacer()
                Image(systemName: "info.circle")
            }.font(.system(size: 10)).foregroundStyle(shared ? Theme.secondary : Theme.accent)
                .padding(.horizontal, 23).padding(.bottom, 12)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("data.libraryStatus")
            .sheet(isPresented: $showingDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(shared ? "本机共用资料库" : "当前使用独立测试资料")
                        .font(.system(size: 17, weight: .semibold))
                    Text(shared ? "所有日常打开的版本使用这里的计时、历史、待办和便签。重复打开会唤出正在运行的番茄小记。" : "这里的记录独立保存，不会出现在日常资料库。日常使用请打开本机共用资料库。")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text(state.repository.fileURL.path)
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).foregroundStyle(Theme.secondary)
                    Text("操作后自动保存；计时中约每 2 秒保存检查点。备份同时保留文字和关联图片。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    HStack {
                        Button("查看资料") { NSWorkspace.shared.activateFileViewerSelecting([state.repository.fileURL]) }
                        Button("备份资料") {
                            if let url = state.backupData() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }.disabled(!state.canWrite)
                    }.buttonStyle(SubtleButtonStyle())
                    if !shared {
                        Text("切换会保存并关闭当前实例。原测试资料保留在原目录，不会自动导入测试记录。")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Button("打开本机共用资料库") {
                            showingDetails = false
                            DispatchQueue.main.async { state.onOpenSharedLibrary?() }
                        }
                            .buttonStyle(PrimaryButtonStyle()).disabled(!state.canWrite)
                            .accessibilityIdentifier("data.openSharedLibrary")
                    }
                    HStack { Spacer(); Button("完成") { showingDetails = false }.keyboardShortcut(.cancelAction) }
                }.padding(24).frame(width: 370)
                    .background(Theme.background).foregroundStyle(Theme.primary)
            }
    }
}
