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
        if let note = state.data.notes.max(by: { $0.updatedAt < $1.updatedAt }) { open(note.id) }
        else { create() }
    }

    func open(_ id: UUID, activate: Bool = true) {
        guard let note = state.note(id) else { return }
        let controller: NoteWindowController
        if let existing = controllers[id] { controller = existing }
        else {
            controller = NoteWindowController(note: note, state: state)
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
    private let editor = LinedTextView(frame: .zero)
    private let feedbackLabel = NSTextField(labelWithString: "自动保存 · 始终置顶")
    private var saveTask: DispatchWorkItem?
    private var frameTask: DispatchWorkItem?

    init(note: StickyNote, state: AppState) {
        self.id = note.id
        self.state = state
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
        feedbackLabel.font = .systemFont(ofSize: 10)
        feedbackLabel.textColor = .secondaryLabelColor

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
        editor.font = .systemFont(ofSize: 15)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 200)
        editor.frame = NSRect(x: 0, y: 0, width: size.width, height: max(200, size.height - 60))
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 15, height: 7)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 26
        paragraph.maximumLineHeight = 26
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
        editor.string = note.text
        editor.textStorage?.addAttributes([.paragraphStyle: paragraph], range: NSRange(location: 0, length: (note.text as NSString).length))
        editor.delegate = self
        scroll.documentView = editor

        content.addSubview(toolbar)
        content.addSubview(scroll)
        toolbar.addSubview(feedbackLabel)
        toolbar.addSubview(convert)
        for view in [toolbar, scroll, feedbackLabel, convert] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 30),
            feedbackLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 19),
            feedbackLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            convert.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            convert.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            convert.leadingAnchor.constraint(greaterThanOrEqualTo: feedbackLabel.trailingAnchor, constant: 6),
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
        feedbackLabel.stringValue = "正在保存…"
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
        state.updateNoteText(id, text: editor.string)
        window?.title = state.note(id)?.title ?? "新便签"
        feedbackLabel.stringValue = "已保存 · 始终置顶"
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
        feedbackLabel.stringValue = count > 0 ? "已添加 \(count) 条待办" : "没有新增待办"
    }
}

private final class LinedTextView: NSTextView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        Theme.noteRule.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5
        let first = floor(rect.minY / 26) * 26 + 29
        var y = first
        while y < rect.maxY + 26 {
            path.move(to: NSPoint(x: 19, y: y))
            path.line(to: NSPoint(x: bounds.width - 19, y: y))
            y += 26
        }
        path.stroke()
    }
}

private extension NSSize {
    var area: CGFloat { max(0, width) * max(0, height) }
}
