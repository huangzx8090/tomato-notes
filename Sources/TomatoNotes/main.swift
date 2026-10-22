import AppKit
import SwiftUI
import TomatoCore
import TomatoSystem

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let state: AppState
    private let dataLock: RepositoryLock
    private lazy var shortcuts = HotkeyManager()
    private lazy var reminders = ReminderManager()
    private var notes: NoteWindows!
    private var work: WorkWindows!
    private var statusItem: NSStatusItem!
    private var mainPanel: MainPanelWindow?
    private var heartbeat: Timer?
    private var quickPanel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var didStart = false
    private var panelPresented = false
    private var localMouseMonitor: Any?
    private var showingDock: Bool?
    private var appliedAppearance: AppAppearance?
    private var timerActivity: NSObjectProtocol?
    private let guardNotices = GuardNoticePresenter()
    private var guardSetupWindow: FocusGuardSetupWindowController?
    private var terminating = false

    init(repository: LocalRepository, dataLock: RepositoryLock) {
        self.dataLock = dataLock
        state = AppState(repository: repository)
        super.init()
        notes = NoteWindows(state: state)
        work = WorkWindows(state: state)
        work.onConfigureAI = { [weak self] in
            self?.showPopover()
            NotificationCenter.default.post(name: Notification.Name("TomatoNotes.showAISettings"), object: nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        applyAppearance()
        updateDockVisibility()
        installEditingMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.sendAction(on: .leftMouseUp)
        }
        let panelHeight = min(660, max(400, (statusItem.button?.window?.screen?.visibleFrame.height ?? 740) - 40))
        let panel = MainPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: panelHeight),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        panel.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "番茄小记"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = makePaperHostingView(rootView: MainPanel(
            state: state,
            createNote: { [weak self] in self?.hidePanel(); self?.notes.create() },
            openNote: { [weak self] id in self?.hidePanel(); self?.notes.open(id) },
            openWork: { [weak self] scope in self?.hidePanel(); self?.work.open(scope) },
            testReminder: { [weak self] in self?.testReminder() },
            requestNotifications: { [weak self] in self?.reminders.requestIfNeeded() },
            panelHeight: panelHeight
        ).onExitCommand { [weak self] in self?.hidePanel() }, size: NSSize(width: 420, height: panelHeight))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        mainPanel = panel

        state.onDataChanged = { [weak self] in self?.refreshStatusItem() }
        state.onGuardSetupRequired = { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: Notification.Name("TomatoNotes.showFocus"), object: nil)
            self.hidePanel()
            if self.guardSetupWindow?.window?.isVisible != true {
                let controller = FocusGuardSetupWindowController(state: self.state)
                controller.onClosed = { [weak self] in if self?.terminating == false { self?.showPopover() } }
                self.guardSetupWindow = controller
            }
            NSApp.activate(ignoringOtherApps: true)
            self.guardSetupWindow?.window?.makeKeyAndOrderFront(nil)
        }
        state.guardController.onNotice = { [weak self] title, message, allow in
            guard let self else { return }
            self.guardNotices.show(title: title, message: message, allow: allow,
                                   glassEnabled: self.state.settings.glassControlsEnabled)
            self.reminders.send(title: title, body: message, sound: self.state.settings.soundEnabled,
                                notification: self.state.settings.notificationsEnabled)
        }
        state.onStarted = { [weak self] in
            guard let self, self.state.settings.notificationsEnabled else { return }
            self.reminders.requestIfNeeded()
        }
        state.onStageCompleted = { [weak self] next in
            guard let self else { return }
            self.reminders.send(title: next == .focus ? "休息结束了" : "这一轮完成了",
                                body: next == .focus ? "准备好后，开始下一轮专注。" : "这一轮的投入已记录，先休息一下。点击打开面板可查看进展，或开始\(next.label)。",
                                sound: self.state.settings.soundEnabled,
                                notification: self.state.settings.notificationsEnabled)
        }
        state.onDailyReviewFinished = { [weak self] day, succeeded in
            guard let self else { return }
            self.reminders.send(title: succeeded ? "今天的 AI 回顾已整理好" : "今天的 AI 回顾需要重试",
                                body: succeeded ? "点击查看今天做了什么、取得了什么成果。" : "记录和图片已保留，点击打开后可重试。",
                                sound: self.state.settings.soundEnabled,
                                notification: self.state.settings.notificationsEnabled, reviewDay: day)
        }
        state.applyHotkeys = { [weak self] settings in self?.shortcuts.apply(settings) }
        shortcuts.onPress = { [weak self] id in
            guard let self, !self.state.deviceLocked else { return }
            switch id {
            case 1: self.state.startOrPause()
            case 2: self.showQuickTodo()
            case 3: self.notes.openRecent()
            default: break
            }
        }
        if let message = shortcuts.apply(state.settings) { state.feedback = message }
        reminders.onOpen = { [weak self] in self?.showPopover() }
        reminders.onOpenReview = { [weak self] day in self?.hidePanel(); self?.work.open(.day(day)) }
        reminders.onStatus = { [weak self] message in self?.state.notificationStatus = message }
        reminders.refreshStatus()

        installSystemObservers()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.tick() }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
        refreshStatusItem()
        notes.restore()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-panel") || arguments.contains("--show-ai-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover()
                if arguments.contains("--show-ai-settings") {
                    NotificationCenter.default.post(name: Notification.Name("TomatoNotes.showAISettings"), object: nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidResignActive(_ notification: Notification) {
        if !ProcessInfo.processInfo.arguments.contains("--ui-stay-open") { hidePanel() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        notes.flushAll()
        state.prepareForQuit()
        return .terminateNow
    }

    @objc private func togglePopover() {
        if panelPresented && NSApp.isActive { hidePanel() }
        else { showPopover() }
    }

    private func showPopover() {
        if state.guardSetupPresented, let setup = guardSetupWindow?.window, setup.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            setup.makeKeyAndOrderFront(nil)
            return
        }
        guard let panel = mainPanel, let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame
        let anchorX = statusItem.button?.window?.frame.midX ?? available.maxX - 230
        let x = min(max(anchorX - 210, available.minX + 10), available.maxX - 430)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: available.maxY - 6))
        panelPresented = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panelPresented = false
        mainPanel?.orderOut(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    private func refreshStatusItem() {
        applyAppearance()
        updateDockVisibility()
        updateTimerActivity()
        let symbol: String
        switch state.timer.phase {
        case .paused: symbol = "pause.circle"
        case .completed: symbol = "checkmark.circle"
        case .idle, .running: symbol = state.timer.stage == .focus ? "timer" : "cup.and.saucer"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: state.statusText)
        statusItem?.button?.title = " \(state.remainingText)"
        statusItem?.button?.toolTip = "番茄小记 · \(state.statusText)"
    }

    private func updateDockVisibility() {
        let desired = state.settings.showDockIcon || ProcessInfo.processInfo.arguments.contains("--ui-test")
        guard desired != showingDock else { return }
        showingDock = desired
        NSApp.setActivationPolicy(desired ? .regular : .accessory)
    }

    private func applyAppearance() {
        let preference = state.settings.appearance
        guard appliedAppearance != preference else { return }
        appliedAppearance = preference
        // AppKit 便签和 SwiftUI 窗口共用应用外观；nil 恢复系统实时跟随。
        NSApp.appearance = preference.nativeAppearance
    }

    private func updateTimerActivity() {
        if state.timer.phase == .running && state.canWrite {
            if timerActivity == nil {
                // 保持用户启动的倒计时及时回调，同时允许系统按原设置进入睡眠。
                timerActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                      reason: "番茄小记倒计时")
            }
        } else if let activity = timerActivity {
            ProcessInfo.processInfo.endActivity(activity)
            timerActivity = nil
        }
    }

    private func testReminder() {
        reminders.send(title: "番茄小记的轻提醒", body: "这是测试提醒，计时到点时也会这样提醒你。",
                       sound: state.settings.soundEnabled, notification: state.settings.notificationsEnabled)
        state.feedback = "已触发测试提醒，请以系统实际显示和声音为准"
    }

    private func showQuickTodo() {
        guard state.canWrite else { showPopover(); return }
        if let quickPanel { quickPanel.makeKeyAndOrderFront(nil); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        hidePanel()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 166),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = InteractiveHostingView(rootView: QuickTodoView(
            onSave: { [weak self] text in self?.state.addTodo(text); self?.closeQuickTodo() },
            onClose: { [weak self] in self?.closeQuickTodo() }
        ))
        panel.center()
        quickPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeQuickTodo() {
        quickPanel?.orderOut(nil)
        quickPanel = nil
        if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }

    private func installSystemObservers() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            if self.panelPresented, event.window !== self.mainPanel,
               event.window !== self.statusItem.button?.window { self.hidePanel() }
            return event
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(showExistingInstance), name: NSNotification.Name("com.zixuan.TomatoNotes.showPanel"),
                                object: state.repository.fileURL.path)
        distributed.addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func appChanged() { state.appDidChange() }
    @objc private func willSleep() { state.pauseForSystem("设备睡眠已暂停") }
    @objc private func sessionResigned() { state.pauseForSystem("用户会话已暂停") }
    @objc private func screenLocked() {
        state.pauseForSystem("锁屏已暂停")
        state.deviceLocked = true
        hidePanel()
        closeQuickTodo()
    }
    @objc private func screenUnlocked() { state.deviceLocked = false }
    @objc private func showExistingInstance() { showPopover() }
    @objc private func closeCurrentWindow() {
        guard let window = NSApp.keyWindow else { return }
        if window === mainPanel { hidePanel() }
        else if window === quickPanel { closeQuickTodo() }
        else { window.performClose(nil) }
    }
    @objc private func screensChanged() { notes.fitToScreens() }

    private func installEditingMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "打开番茄小记", action: #selector(showExistingInstance), keyEquivalent: "0").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出番茄小记", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"),
                                       ("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                       ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭当前窗口", action: #selector(closeCurrentWindow), keyEquivalent: "w").target = self
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}

private final class MainPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let args = ProcessInfo.processInfo.arguments
    let repository: LocalRepository
    if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
        repository = LocalRepository(fileURL: URL(fileURLWithPath: args[index + 1], isDirectory: true).appendingPathComponent("data.json"))
    } else if Bundle.main.bundleIdentifier == "com.zixuan.TomatoNotes.QA" || Bundle.main.bundleIdentifier == "com.zixuan.TomatoNotes.GuardQA" {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let name = Bundle.main.bundleIdentifier == "com.zixuan.TomatoNotes.GuardQA" ? "TomatoNotes-GuardQA" : "TomatoNotes-QA"
        repository = LocalRepository(fileURL: root.appendingPathComponent("\(name)/data.json"))
    } else { repository = LocalRepository() }
    do {
        let lock = try RepositoryLock(repository: repository)
        let coordinator = AppCoordinator(repository: repository, dataLock: lock)
        application.delegate = coordinator
        application.finishLaunching()
        coordinator.start()
        withExtendedLifetime(coordinator) { application.run() }
    } catch RepositoryLockError.inUse(let pid) {
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.zixuan.TomatoNotes.showPanel"),
                                                                     object: repository.fileURL.path, userInfo: nil, deliverImmediately: true)
        if let pid { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
    } catch {
        let alert = NSAlert()
        alert.messageText = "无法打开番茄小记"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
