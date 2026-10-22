import SwiftUI
import TomatoCore

struct NotesListView: View {
    let notes: [StickyNote]
    let today: String
    @Binding var showsHistory: Bool
    var createNote: () -> Void
    var openNote: (UUID) -> Void
    var continueNote: (UUID) -> Void
    var deleteNote: (UUID) -> Void
    @ViewState private var pendingDeletion: StickyNote?

    private var todaysNotes: [StickyNote] { NoteLibrary.notes(on: today, in: notes) }
    private var history: [NoteDayGroup] { NoteLibrary.history(excluding: today, in: notes) }
    private var historyCount: Int { history.reduce(0) { $0 + $1.notes.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(showsHistory ? "翻翻旧便签" : "今天的便签")
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                    Text(showsHistory ? "旧想法，也可以接着写。" : "记下想法，让它留在眼前。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Button(action: createNote) { Image(systemName: "plus").frame(width: 26, height: 26) }
                    .buttonStyle(SubtleButtonStyle()).accessibilityLabel("新建今天的便签")
                    .accessibilityIdentifier("notes.new")
            }

            Button { showsHistory.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: showsHistory ? "arrow.left" : "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .light)).foregroundStyle(Theme.accent)
                    Text(showsHistory ? "回到今天" : "历史便签").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(showsHistory ? "\(todaysNotes.count) 张" : "\(historyCount) 张")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.secondary)
                    if !showsHistory { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border.opacity(0.7), lineWidth: 0.6))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("notes.history")

            if showsHistory {
                if history.isEmpty { emptyState(history: true) }
                ForEach(history) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(group.day.replacingOccurrences(of: "-", with: "."))
                                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 0.5)
                            Text("\(group.notes.count) 张").font(.system(size: 10))
                        }.foregroundStyle(Theme.secondary)
                        ForEach(group.notes) { note in noteCard(note, historical: true) }
                    }
                }
            } else {
                if todaysNotes.isEmpty { emptyState(history: false) }
                ForEach(todaysNotes) { note in noteCard(note, historical: false) }
            }

            Text(showsHistory ? "“继续使用”会放一份副本到今天，历史原稿保留；再次点击会打开已有的今日副本。" : "便签自动保存。以前的便签收在历史里；选中文字或全文可按行转为今天的待办。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("删除这张便签？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
               presenting: pendingDeletion) { note in
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除便签", role: .destructive) { deleteNote(note.id); pendingDeletion = nil }
        } message: { note in
            Text("“\(note.title)”将被删除，已打开的便签窗口也会关闭。其他便签和已继续使用的副本会保留。")
        }
    }

    private func noteCard(_ note: StickyNote, historical: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { openNote(note.id) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(note.title).font(.system(size: 15, weight: .medium, design: .serif)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: note.isOpen ? "pin.fill" : "arrow.up.right")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Text(previewText(note))
                        .font(.system(size: 12)).lineSpacing(4).foregroundStyle(Theme.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(historical ? "查看历史便签：\(note.title)" : "打开便签：\(note.title)")

            Rectangle().fill(Color(nsColor: Theme.noteRule).opacity(0.6)).frame(height: 0.5)

            HStack(spacing: 10) {
                if historical {
                    Button { continueNote(note.id) } label: {
                        Label("继续使用", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .medium))
                    }.buttonStyle(SubtleButtonStyle())
                        .accessibilityLabel("继续使用便签：\(note.title)")
                        .accessibilityIdentifier("notes.continue.\(note.id)")
                } else {
                    Text(note.continuedFromNoteID == nil ? (note.isOpen ? "已在桌面打开" : "已收起 · 点击打开") : "接着上次的想法")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Button { pendingDeletion = note } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    .help("删除这张便签").accessibilityLabel("删除便签：\(note.title)")
                    .accessibilityIdentifier("notes.delete.\(note.id)")
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 13).fill(Color(nsColor: Theme.notePaper))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(nsColor: Theme.noteRule).opacity(0.45), lineWidth: 0.6))
                .shadow(color: Theme.paperShadow.opacity(0.08), radius: 6, y: 3)
        }
    }

    private func emptyState(history: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: history ? "tray" : "note.text").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text(history ? "还没有历史便签" : "给今天的想法，一张小小的纸。")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            if !history { Button("写一张便签", action: createNote).buttonStyle(SubtleButtonStyle()) }
        }.frame(maxWidth: .infinity).padding(.vertical, 35)
    }

    private func previewText(_ note: StickyNote) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "一张等待落笔的纸。" }
        let body = note.text.components(separatedBy: .newlines).dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? text : body
    }
}
