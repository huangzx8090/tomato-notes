import AppKit
import TomatoCore

@MainActor
final class NoteWindows {
    private let state: AppState
    private var controllers: [UUID: NoteWindowController] = [:]

    init(state: AppState) { self.state = state }

    func restore() {
        for note in state.data.notes where note.isOpen { open(note.id, activate: false) }
    }

    func create() {
        guard let id = state.createNote() else { return }
        open(id)
    }

    func openRecent() {
        if let note = NoteLibrary.notes(on: state.todayKey, in: state.data.notes).first { open(note.id) }
        else { create() }
    }

    func continueNote(_ id: UUID) {
        controllers[id]?.flush()
        guard let copyID = state.continueNote(id) else { return }
        open(copyID)
    }

    func delete(_ id: UUID) {
        guard state.deleteNote(id) else { return }
        // 先移除数据，再关闭窗口；关闭时的延迟保存只会忽略已删除的 ID。
        controllers.removeValue(forKey: id)?.close()
    }

    func export(_ id: UUID, from window: NSWindow?) {
        let snapshot = controllers[id]?.currentNoteForExport() ?? state.note(id)
        guard let snapshot else { state.feedback = "记录已不存在"; return }
        NoteTextExportPresenter.present(note: snapshot, from: window) { [weak self] result in
            guard let self else { return }
            let message: String
            switch result {
            case .success(nil): return
            case .success: message = "TXT 已导出"
            case .failure(let error): message = "导出失败：\(error.localizedDescription)"
            }
            if let controller = self.controllers[id], let window, window === controller.window {
                controller.showFeedback(message)
            } else { self.state.feedback = message }
        }
    }

    func open(_ id: UUID, activate: Bool = true) {
        guard let note = state.note(id) else { return }
        let controller: NoteWindowController
        if let existing = controllers[id] { controller = existing }
        else {
            controller = NoteWindowController(note: note, state: state) { [weak self] in
                guard let self else { return }
                self.export(id, from: self.controllers[id]?.window)
            }
            controllers[id] = controller
        }
        state.setNoteOpen(id, isOpen: true)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
        } else { controller.window?.orderFront(nil) }
    }

    func fitToScreens() {
        for controller in controllers.values { controller.fitToScreen() }
    }

    func flushAll() {
        for controller in controllers.values { controller.flush() }
    }
}

@MainActor
private final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let id: UUID
    private let state: AppState
    private let onExport: () -> Void
    private let editor = LinedTextView(frame: .zero)
    private let feedbackLabel = NSTextField(labelWithString: "")
    private var saveTask: DispatchWorkItem?
    private var frameTask: DispatchWorkItem?
    private var feedbackTask: DispatchWorkItem?

    init(note: StickyNote, state: AppState, onExport: @escaping () -> Void) {
        self.id = note.id
        self.state = state
        self.onExport = onExport
        let size = NSSize(width: note.width, height: note.height)
        let offset = Double(state.data.notes.filter { $0.isOpen }.count % 8) * 24
        let origin = NSPoint(x: note.x ?? (180 + offset), y: note.y ?? (240 + offset))
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = note.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = Theme.notePaper
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.minSize = NSSize(width: 240, height: 200)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setFrame(NSRect(origin: origin, size: size), display: false)

        let content = NSView()
        let toolbar = NSView()
        let convert = NSButton(title: "按行转待办", target: self, action: #selector(convertToTodos))
        convert.bezelStyle = .inline
        convert.font = .systemFont(ofSize: 11, weight: .medium)
        convert.contentTintColor = Theme.noteAction
        convert.toolTip = "将选中文字（没有选区时使用全文）的非空行添加为今天的待办"
        let export = NSButton(title: "导出 TXT", target: self, action: #selector(exportText))
        export.bezelStyle = .inline
        export.font = .systemFont(ofSize: 11, weight: .medium)
        export.contentTintColor = Theme.noteAction
        export.toolTip = "选择保存位置，导出完整原文"
        export.setAccessibilityIdentifier("note.exportTXT")
        feedbackLabel.font = .systemFont(ofSize: 10)
        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.lineBreakMode = .byTruncatingTail
        feedbackLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        feedbackLabel.isHidden = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = true
        editor.backgroundColor = Theme.notePaper
        editor.textColor = Theme.noteInk
        editor.insertionPointColor = Theme.noteInk
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 200)
        editor.frame = NSRect(x: 0, y: 0, width: size.width, height: max(200, size.height - 60))
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 15, height: 7)
        NoteTypography.apply(to: editor, text: note.text)
        editor.delegate = self
        scroll.documentView = editor

        content.addSubview(toolbar)
        content.addSubview(scroll)
        toolbar.addSubview(feedbackLabel)
        toolbar.addSubview(export)
        toolbar.addSubview(convert)
        for view in [toolbar, scroll, feedbackLabel, export, convert] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 34),
            feedbackLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 19),
            feedbackLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            convert.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            convert.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            export.trailingAnchor.constraint(equalTo: convert.leadingAnchor, constant: -10),
            export.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            export.leadingAnchor.constraint(greaterThanOrEqualTo: feedbackLabel.trailingAnchor, constant: 6),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        panel.contentView = content
        fitToScreen()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func textDidChange(_ notification: Notification) {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveText() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func windowDidMove(_ notification: Notification) { scheduleFrameSave() }
    func windowDidResize(_ notification: Notification) {
        if let scroll = editor.enclosingScrollView {
            editor.minSize = NSSize(width: 0, height: scroll.contentSize.height)
            editor.setFrameSize(NSSize(width: scroll.contentSize.width,
                                       height: max(editor.frame.height, scroll.contentSize.height)))
        }
        scheduleFrameSave()
    }

    func windowWillClose(_ notification: Notification) {
        flush()
        state.setNoteOpen(id, isOpen: false)
    }

    func flush() {
        saveTask?.cancel()
        frameTask?.cancel()
        saveText()
        if let window { state.updateNoteFrame(id, frame: window.frame) }
    }

    func currentNoteForExport() -> StickyNote? {
        saveTask?.cancel()
        saveText()
        guard var note = state.note(id) else { return nil }
        // 保存失败时仍可导出编辑器中尚未落盘的原文。
        note.text = editor.string
        return note
    }

    func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedbackLabel.stringValue = message
        feedbackLabel.toolTip = message
        feedbackLabel.isHidden = false
        let task = DispatchWorkItem { [weak self] in
            self?.feedbackLabel.stringValue = ""
            self?.feedbackLabel.isHidden = true
        }
        feedbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
    }

    func fitToScreen() {
        guard let window else { return }
        let screen = NSScreen.screens.max { a, b in
            a.visibleFrame.intersection(window.frame).size.area < b.visibleFrame.intersection(window.frame).size.area
        } ?? NSScreen.main
        guard let available = screen?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(max(240, frame.width), available.width)
        frame.size.height = min(max(200, frame.height), available.height)
        frame.origin.x = min(max(frame.minX, available.minX), available.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, available.minY), available.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    private func saveText() {
        if let note = state.note(id), note.text != editor.string {
            state.updateNoteText(id, text: editor.string)
            if !state.canWrite { showFeedback("保存失败，可导出 TXT 保留文字") }
        }
        window?.title = state.note(id)?.title ?? "新便签"
    }

    private func scheduleFrameSave() {
        frameTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            self.state.updateNoteFrame(self.id, frame: window.frame)
        }
        frameTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    @objc private func convertToTodos() {
        saveText()
        let range = editor.selectedRange()
        let text = range.length > 0 ? (editor.string as NSString).substring(with: range) : editor.string
        let count = state.convertNoteToTodos(id, text: text)
        showFeedback(count > 0 ? "已添加 \(count) 条待办" : "没有新增待办")
    }

    @objc private func exportText() { onExport() }
}

private extension NSSize {
    var area: CGFloat { max(0, width) * max(0, height) }
}
