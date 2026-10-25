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
    var exportNote: (UUID) -> Void
    @ViewState private var pendingDeletion: StickyNote?

    private var todaysNotes: [StickyNote] { NoteLibrary.notes(on: today, in: notes) }
    private var history: [NoteDayGroup] { NoteLibrary.history(excluding: today, in: notes) }
    private var historyCount: Int { history.reduce(0) { $0 + $1.notes.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 10) {
                Text(showsHistory ? "翻翻旧便签" : "今天的便签")
                    .font(NoteTypography.font(size: 21, weight: .semibold))
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
                        Text(note.title).font(NoteTypography.font(size: 15, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: note.isOpen ? "pin.fill" : "arrow.up.right")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Text(previewText(note))
                        .font(NoteTypography.font(size: 14)).lineSpacing(4).foregroundStyle(Theme.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(historical ? "查看历史便签：\(note.title)" : "打开便签：\(note.title)")
                .accessibilityValue(note.isOpen ? "已在桌面打开" : "已收起")

            Rectangle().fill(Color(nsColor: Theme.noteRule).opacity(0.6)).frame(height: 0.5)

            HStack(spacing: 10) {
                if historical {
                    Button { continueNote(note.id) } label: {
                        Label("继续使用", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .medium))
                    }.buttonStyle(SubtleButtonStyle())
                        .accessibilityLabel("继续使用便签：\(note.title)")
                        .accessibilityIdentifier("notes.continue.\(note.id)")
                        .help("复制到今天继续编辑，保留历史原稿")
                }
                Spacer(minLength: 0)
                Button { exportNote(note.id) } label: {
                    Label("导出 TXT", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.vertical, 6)
                }.buttonStyle(.plain).foregroundStyle(Theme.primary)
                    .help("选择保存位置，导出这张便签的原文")
                    .accessibilityLabel("导出便签为 TXT：\(note.title)")
                    .accessibilityIdentifier("notes.export.\(note.id)")
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
            Text(history ? "还没有历史便签" : "还没有便签")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            if !history { Button("写一张便签", action: createNote).buttonStyle(SubtleButtonStyle()) }
        }.frame(maxWidth: .infinity).padding(.vertical, 35)
    }

    private func previewText(_ note: StickyNote) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "空白便签" }
        let body = note.text.components(separatedBy: .newlines).dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? text : body
    }
}
