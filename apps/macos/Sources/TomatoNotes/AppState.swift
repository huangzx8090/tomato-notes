import AppKit
import CoreGraphics
import Foundation
import IOKit
import TomatoCore
import TomatoSystem

struct HistoryNavigationRequest: Equatable {
    let id = UUID()
    let day: String
    let todoID: UUID?
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var errorMessage: String?
    @Published var feedback: String?
    @Published private(set) var lastDeletedTodo: TodoItem?
    @Published var notificationStatus = "首次开始或测试提醒时申请通知权限"
    @Published private(set) var calendarDay = LocalTime.dayKey(Date())
    @Published private(set) var focusHeatmapRevision = 0
    @Published private(set) var historySearchRevision = 0
    @Published private(set) var historyNavigationRequest: HistoryNavigationRequest?
    @Published private(set) var generatingScopes: Set<String> = []
    @Published private(set) var reviewErrors: [String: String] = [:]
    @Published private(set) var hasAPIKey = false
    @Published var aiStatus = "尚未配置 AI 服务商 API Key"
    @Published private(set) var testingAI = false
    @Published private(set) var aiModels: [String] = []
    @Published private(set) var loadingAIModels = false
    @Published var guardSetupPresented = false
    @Published var focusGoalDraft = ""
    @Published private(set) var activityStatus = "开启后，专注时自动留下活动记录。"
    @Published private(set) var identifyingActivity = false
    @Published private(set) var activityErrors: [UUID: String] = [:]
    @Published private(set) var focusModeShortcutInstalled = false
    @Published private(set) var focusModeShortcutStatus = "尚未安装专注模式快捷指令。"
    @Published private(set) var focusModeEnabled = false

    let repository: LocalRepository
    var onOpenSharedLibrary: (() -> Void)?
    let workImages: WorkImageStore
    let guardController = FocusGuardController()
    private let focusModeShortcut = FocusModeShortcutController()
    var onGuardSetupRequired: (() -> Void)?
    private var guardSetupStartsTimer = false
    private var pendingGuardPlan: FocusGuardPlan?
    private var pendingTimerOnly = false
    private var timerOnlySessionID: UUID?
    var onDataChanged: (() -> Void)?
    var onStageCompleted: ((TimerStage) -> Void)?
    var onStarted: (() -> Void)?
    var applyHotkeys: ((AppSettings) -> String?)?
    var onDailyReviewFinished: ((String, Bool) -> Void)?
    var deviceLocked = false
    private var engine: TimerEngine
    private var lastUptime: TimeInterval?
    private var lastSavedUptime: TimeInterval = 0
    private var lastHeatmapMinute = Calendar.current.component(.minute, from: Date())
    private var lastLidCheck: TimeInterval = 0
    private var lidClosed = false
    private var currentApp: AppIdentity?
    private var lastConversion: (UUID, String, Date)?
    private var todoDeletionHistory = TodoDeletionHistory()
    private let credentials = AIProviderCredentials()
    private var ai = AIReviewClient(provider: AIProviderCatalog.deepseek)
    /// 当前生效的 AI 配置；设置变更后重建客户端。
    private(set) var aiProvider: AIProviderConfig = AIProviderCatalog.deepseek
    private var workSaveTask: DispatchWorkItem?
    private var lastReviewCheck: TimeInterval = 0
    private var pendingSessionReviews: [UUID] = []
    private let activityChrome = ChromeBrowser()
    private var activitySampleTask: Task<Void, Never>?
    private var activityTopicTask: Task<Void, Never>?
    private var topicSessionID: UUID?
    private var sampleGeneration = UUID()
    private var activityGeneration = UUID()
    private var topicRequestID = UUID()
    private var lastActivityPoll: TimeInterval = 0
    private var lastActivityTopicCheck: TimeInterval = 0
    private var activitySample: (page: ActivityPage, identity: String, at: Date)?
    private var noteBaselines: [UUID: String] = [:]
    private var noteRecordingBlockID = UUID()
    private var noteBaselineDay = LocalTime.dayKey(Date())
    private let aiClientFactory: (AIProviderConfig) -> AIReviewClient
    private let injectedKeyReader: ((String) throws -> String?)?

    init(repository: LocalRepository = LocalRepository(),
         aiClientFactory: @escaping (AIProviderConfig) -> AIReviewClient = { AIReviewClient(provider: $0) },
         keyReader: ((String) throws -> String?)? = nil) {
        self.repository = repository
        self.aiClientFactory = aiClientFactory
        self.injectedKeyReader = keyReader
        self.workImages = WorkImageStore(repository: repository)
        do {
            var loaded = try repository.load()
            var recovered = TimerEngine(data: loaded)
            recovered.recoverAfterLaunch()
            loaded = recovered.data
            self.data = loaded
            self.engine = recovered
            if loaded.timer.phase == .paused && loaded.timer.pauseReason == "已恢复上次计时，等待继续" {
                try repository.save(loaded)
            }
        } catch {
            self.data = AppData()
            self.engine = TimerEngine(data: AppData())
            self.errorMessage = "读取本地数据失败：\(error.localizedDescription)。为保护原始文件，当前禁止写入。"
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        deviceLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        currentApp = Self.frontmostApp()
        if let day = data.lastReviewAttemptDay, let error = data.lastReviewError { reviewErrors[WorkScope.day(day).key] = error }
        ai = aiClientFactory(data.settings.ai.resolved())
        refreshCredentialStatus()
        guardController.currentSnapshot = { [weak self] in
            guard let self else { return (TimerSnapshot(), true, FocusGuardSettings()) }
            return (self.timer, self.deviceLocked, self.settings.focusGuard)
        }
        focusModeShortcutInstalled = focusModeShortcut.isInstalled
        focusModeShortcutStatus = focusModeShortcut.status
        focusModeEnabled = focusModeShortcut.isEnabled
        focusModeShortcut.onStateChange = { [weak self] installed, status in
            self?.focusModeShortcutInstalled = installed
            self?.focusModeShortcutStatus = status
            self?.syncFocusMode()
        }
        syncFocusMode()
    }

    var canWrite: Bool { errorMessage == nil }
    var todayKey: String { LocalTime.dayKey(Date()) }
    var timer: TimerSnapshot { data.timer }
    var settings: AppSettings { data.settings }
    var isTimerOnlyRound: Bool { timer.sessionID != nil && timerOnlySessionID == timer.sessionID }

    var remainingText: String {
        let seconds = Int(ceil(max(0, timer.remainingSeconds)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var statusText: String {
        switch timer.phase {
        case .idle: "待开始"
        case .running: timer.stage == .focus ? "正在专注" : "正在\(timer.stage.label)"
        case .paused: timer.pauseReason ?? "已暂停"
        case .completed: "\(timer.stage.label)完成"
        }
    }

    var primaryAction: String {
        switch timer.phase {
        case .idle: "开始专注"
        case .running: "暂停"
        case .paused: "继续"
        case .completed: "开始\(timer.nextStage?.label ?? "下一轮")"
        }
    }

    func startOrPause() {
        guard canWrite else { return }
        if timer.phase == .running {
            advanceToNow()
            engine.pause(reason: "手动暂停", at: Date())
            stopActivitySampling()
            lastUptime = nil
            publish(focusHeatmapChanged: timer.stage == .focus)
            return
        }
        guard !deviceLocked else { feedback = "设备仍处于锁屏状态"; return }
        guard !shouldPauseForLid(Self.isLidClosed()) else { feedback = "合盖已暂停；外接屏工作模式可在设置中允许"; return }
        let nextStage = timer.phase == .completed ? (timer.nextStage ?? .focus) : timer.stage
        if nextStage == .focus, settings.focusGuard.enabled, pendingGuardPlan == nil, !pendingTimerOnly, !isTimerOnlyRound,
           !(timer.phase == .paused && guardController.sessionID == timer.sessionID && guardController.plan != nil) {
            if var reused = settings.focusGuard.reusablePlan {
                let goal = focusGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !goal.isEmpty { reused.goal = String(goal.prefix(300)) }
                pendingGuardPlan = reused
            }
            else { openGuardSetup(startAfter: true); return }
        }
        let previousSessionID = timer.sessionID
        engine.start(at: Date(), goal: pendingGuardPlan?.goal ?? focusGoalDraft,
                     whitelistedBundleIDs: pendingGuardPlan?.applicationWhitelistBundleIDs)
        if engine.data.timer.stage == .focus, engine.data.timer.sessionID != previousSessionID { focusGoalDraft = "" }
        if let plan = pendingGuardPlan, let id = engine.data.timer.sessionID {
            guardController.configure(plan, sessionID: id)
            engine.setWhitelistBundleIDs(plan.applicationWhitelistBundleIDs, for: id)
            var next = engine.data
            if let index = next.sessions.firstIndex(where: { $0.id == id }) { next.sessions[index].goal = plan.goal }
            next.settings.focusGuard.rememberDraft(plan)
            engine.replaceData(next)
            timerOnlySessionID = nil
        } else if pendingTimerOnly, let id = engine.data.timer.sessionID {
            timerOnlySessionID = id
            guardController.disableForRound()
            engine.setWhitelistBundleIDs(nil, for: id)
        }
        pendingGuardPlan = nil
        pendingTimerOnly = false
        lastUptime = ProcessInfo.processInfo.systemUptime
        currentApp = Self.frontmostApp()
        publish(historyContentChanged: engine.data.timer.sessionID != previousSessionID)
        markAutomaticRecording()
        onStarted?()
    }

    func tick() {
        let now = Date()
        let day = LocalTime.dayKey(now)
        var heatmapNeedsRefresh = false
        if day != calendarDay { calendarDay = day; heatmapNeedsRefresh = true }
        let minute = Calendar.current.component(.minute, from: now)
        if minute != lastHeatmapMinute {
            lastHeatmapMinute = minute
            if timer.phase == .running && timer.stage == .focus { heatmapNeedsRefresh = true }
        }
        if heatmapNeedsRefresh { focusHeatmapRevision &+= 1 }
        guard canWrite else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastLidCheck >= 1 {
            lidClosed = Self.isLidClosed()
            lastLidCheck = uptime
        }
        if timer.phase == .running && (deviceLocked || shouldPauseForLid(lidClosed)) {
            // 合盖通知可能不伴随睡眠，检测后立刻冻结最近检查点。
            engine.pause(reason: deviceLocked ? "锁屏已暂停" : "合盖已暂停", at: Date())
            stopActivitySampling()
            lastUptime = nil
            publish(focusHeatmapChanged: timer.stage == .focus)
            return
        }
        advanceToNow()
        if timerOnlySessionID != timer.sessionID || timer.phase == .completed || timer.phase == .idle {
            timerOnlySessionID = nil
        }
        guardController.tick(timer: timer, locked: deviceLocked, settings: settings.focusGuard)
        pollActivityPage()
        checkAutomaticSessionReviews()
        checkActivityTopic()
        if uptime - lastReviewCheck >= 15, !deviceLocked {
            lastReviewCheck = uptime
            checkDailyReviewSchedule()
        }
    }

    func pauseForSystem(_ reason: String) {
        guard canWrite, timer.phase == .running else { return }
        advanceToNow()
        engine.pause(reason: reason, at: Date())
        stopActivitySampling()
        lastUptime = nil
        publish(focusHeatmapChanged: timer.stage == .focus)
    }

    func appDidChange() {
        guard canWrite else { return }
        advanceToNow()
        currentApp = Self.frontmostApp()
        resetActivityPageSample()
        guardController.foregroundDidChange()
    }

    func endEarlyOrSkip() {
        guard canWrite else { return }
        advanceToNow()
        let endingSessionID = timer.stage == .focus ? timer.sessionID : nil
        if timer.phase == .completed { engine.skipBreak(at: Date()) }
        else if timer.stage == .focus { engine.endEarly(at: Date()) }
        else { engine.skipBreak(at: Date()) }
        lastUptime = nil
        stopActivitySampling()
        publish(focusHeatmapChanged: endingSessionID != nil)
        if let id = endingSessionID { recordEndedFocus(id) }
    }

    func prepareForQuit() {
        guardController.stop()
        stopActivitySampling()
        guard canWrite else {
            focusModeShortcut.setActive(false)
            focusModeShortcut.waitForPendingOperations()
            return
        }
        advanceToNow()
        if timer.phase == .running { engine.pause(reason: "应用退出已暂停", at: Date()) }
        publish(focusHeatmapChanged: timer.stage == .focus)
        focusModeShortcut.waitForPendingOperations()
    }

    var guardSetupActionTitle: String { guardSetupStartsTimer ? "设置并开始专注" : "保存本轮白名单" }

    func openGuardSetup(startAfter: Bool) {
        guard canWrite else { return }
        guardSetupStartsTimer = startAfter
        guardSetupPresented = true
        onGuardSetupRequired?()
    }

    func saveGuardPlan(_ plan: FocusGuardPlan) {
        guard canWrite else { return }
        var settings = self.settings
        settings.focusGuard.enabled = true
        settings.focusGuard.rememberDraft(plan)
        guard updateSettings(settings) else { return }
        if guardSetupStartsTimer {
            pendingGuardPlan = plan
            guardSetupPresented = false
            startOrPause()
        } else if let id = timer.sessionID, timer.stage == .focus,
                  timer.phase == .running || timer.phase == .paused {
            guardController.configure(plan, sessionID: id)
            engine.setWhitelistBundleIDs(plan.applicationWhitelistBundleIDs, for: id)
            var next = engine.data
            if let index = next.sessions.firstIndex(where: { $0.id == id }) { next.sessions[index].goal = plan.goal }
            engine.replaceData(next)
            publish(historyContentChanged: true)
            timerOnlySessionID = nil
            guardSetupPresented = false
        } else { feedback = "本轮已经结束，请在开始下一轮时重新设置白名单。"; guardSetupPresented = false }
    }

    func useTimerOnlyForRound(goal: String? = nil) {
        guard canWrite else { return }
        guardSetupPresented = false
        if guardSetupStartsTimer {
            if let goal { focusGoalDraft = String(goal.prefix(300)) }
            pendingGuardPlan = nil
            pendingTimerOnly = true
            startOrPause()
        } else if let id = timer.sessionID, timer.stage == .focus,
                  timer.phase == .running || timer.phase == .paused {
            timerOnlySessionID = id
            guardController.disableForRound()
            engine.setWhitelistBundleIDs(nil, for: id)
            publish()
        }
    }

    func backupData() -> URL? {
        guard canWrite else { return nil }
        advanceToNow()
        publish()
        guard canWrite else { return nil }
        do {
            let url = try repository.backup()
            feedback = "本地数据已备份"
            return url
        } catch {
            feedback = "备份失败：\(error.localizedDescription)"
            return nil
        }
    }

    func updateSettings(_ value: AppSettings) -> Bool {
        guard canWrite else { return false }
        let keysChanged = value.timerHotkey != settings.timerHotkey || value.todoHotkey != settings.todoHotkey || value.noteHotkey != settings.noteHotkey
        if keysChanged, let message = applyHotkeys?(value) {
            feedback = message
            return false
        }
        advanceToNow()
        if value.activityRecording != settings.activityRecording || value.ai != settings.ai || value.recordingEnabled != settings.recordingEnabled {
            stopActivitySampling()
            activityGeneration = UUID()
        }
        var next = data
        next.settings = value
        if next.timer.phase == .idle {
            next.timer.targetSeconds = value.duration(for: .focus)
            next.timer.remainingSeconds = next.timer.targetSeconds
        }
        engine.replaceData(next)
        publish()
        markAutomaticRecording()
        feedback = "设置已保存"
        return true
    }

    func installFocusModeShortcut() {
        focusModeShortcut.install()
    }

    func openFocusModeShortcut() {
        focusModeShortcut.openInstalledShortcut()
    }

    func setFocusModeEnabled(_ enabled: Bool) {
        guard !enabled || focusModeShortcutInstalled else { return }
        guard focusModeEnabled != enabled else { return }
        focusModeEnabled = enabled
        focusModeShortcut.setEnabled(enabled)
        syncFocusMode()
    }

    func addTodo(_ text: String) {
        guard canWrite else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = data
        next.todos.append(TodoItem(text: trimmed, localDay: todayKey))
        engine.replaceData(next)
        publish(historyContentChanged: true)
    }

    @discardableResult
    func toggleTodo(_ id: UUID) -> Bool {
        guard canWrite else { return false }
        advanceToNow()
        let now = Date()
        let day = LocalTime.dayKey(now)
        var next = data
        guard let index = next.todos.firstIndex(where: { $0.id == id && $0.effectiveScheduledDay == day }) else { return false }
        if next.todos[index].completedAt == nil {
            next.todos[index].completedAt = now
            next.todos[index].completedLocalDay = day
        } else {
            next.todos[index].completedAt = nil
            next.todos[index].completedLocalDay = nil
        }
        if !deviceLocked { ActivityRecorder.recordTodo(next.todos[index], at: now, in: &next) }
        engine.replaceData(next)
        publish()
        return canWrite && next.todos[index].isCompleted
    }

    func updateTodo(_ id: UUID, text: String) {
        guard canWrite else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let day = todayKey
        var next = data
        guard let index = next.todos.firstIndex(where: { $0.id == id && $0.effectiveScheduledDay == day }) else { return }
        next.todos[index].text = trimmed
        engine.replaceData(next)
        publish(historyContentChanged: true)
    }

    func deleteTodo(_ id: UUID) {
        guard canWrite else { return }
        let day = todayKey
        var next = data
        var history = todoDeletionHistory
        guard history.remove(id, on: day, from: &next.todos) else { return }
        engine.replaceData(next)
        publish(historyContentChanged: true)
        guard canWrite else { return }
        todoDeletionHistory = history
        lastDeletedTodo = history.lastDeleted
        feedback = nil
    }

    func undoTodoDeletion() {
        guard canWrite else { return }
        var next = data
        var history = todoDeletionHistory
        let restored = history.restoreLast(in: &next.todos)
        if restored != nil {
            engine.replaceData(next)
            publish(historyContentChanged: true)
            guard canWrite else { return }
        }
        todoDeletionHistory = history
        lastDeletedTodo = history.lastDeleted
        feedback = restored == nil ? "这条待办已存在，未重复恢复" : "待办已恢复"
    }

    func dismissFeedback() {
        todoDeletionHistory.discard()
        lastDeletedTodo = nil
        feedback = nil
    }

    @discardableResult
    func scheduleTodosForToday(_ ids: Set<UUID>) -> [UUID] {
        guard canWrite, !ids.isEmpty else { return [] }
        let day = todayKey
        var next = data
        let changed = TodoCarryover.schedule(ids, on: day, in: &next.todos)
        guard !changed.isEmpty else { return [] }
        engine.replaceData(next)
        publish()
        if canWrite { feedback = changed.count == 1 ? "待办已安排到今天" : "已安排 \(changed.count) 项到今天" }
        return changed
    }

    func undoTodoSchedule(_ id: UUID) {
        guard canWrite else { return }
        let day = todayKey
        var next = data
        let result = TodoCarryover.undoSchedule(id, on: day, in: &next.todos)
        switch result {
        case .undone:
            engine.replaceData(next)
            publish()
            if canWrite { feedback = "已撤销安排，待办文字和完成记录已保留" }
        case .completed:
            feedback = "这条待办已完成，不能直接撤销结转"
        case .missing:
            feedback = "记录已不存在"
        case .notScheduledToday:
            feedback = "这条待办目前不在今天的安排中"
        }
    }

    func requestHistoryDay(_ day: String, highlightTodoID: UUID? = nil) {
        historyNavigationRequest = HistoryNavigationRequest(day: day, todoID: highlightTodoID)
    }

    func createNote() -> UUID? {
        guard canWrite else { return nil }
        var next = data
        let note = StickyNote()
        next.notes.append(note)
        engine.replaceData(next)
        publish(historyContentChanged: true)
        return note.id
    }

    func note(_ id: UUID) -> StickyNote? { data.notes.first { $0.id == id } }

    func continueNote(_ id: UUID) -> UUID? {
        guard canWrite else { return nil }
        var next = data
        guard let copyID = NoteLibrary.continueNote(id, in: &next.notes) else { return nil }
        engine.replaceData(next)
        publish(historyContentChanged: true)
        return canWrite ? copyID : nil
    }

    @discardableResult
    func deleteNote(_ id: UUID) -> Bool {
        guard canWrite, data.notes.contains(where: { $0.id == id }) else { return false }
        var next = data
        next.notes.removeAll { $0.id == id }
        engine.replaceData(next)
        publish(historyContentChanged: true)
        if canWrite { feedback = "便签已删除" }
        return canWrite
    }

    func updateNoteText(_ id: UUID, text: String) {
        guard canWrite else { return }
        advanceToNow()
        var next = data
        guard let index = next.notes.firstIndex(where: { $0.id == id }) else { return }
        let previous = next.notes[index].text
        next.notes[index].text = text
        next.notes[index].updatedAt = Date()
        if ActivityRecorder.isRecording(next), !deviceLocked {
            if todayKey != noteBaselineDay {
                noteBaselines.removeAll()
                noteRecordingBlockID = UUID()
                noteBaselineDay = todayKey
            }
            if noteBaselines[id] == nil { noteBaselines[id] = previous }
            ActivityRecorder.recordNote(next.notes[index], previousText: noteBaselines[id] ?? previous, at: Date(), blockID: noteRecordingBlockID, in: &next)
        }
        engine.replaceData(next)
        publish(historyContentChanged: true)
    }

    func updateNoteFrame(_ id: UUID, frame: NSRect) {
        guard canWrite else { return }
        var next = data
        guard let index = next.notes.firstIndex(where: { $0.id == id }) else { return }
        next.notes[index].x = frame.origin.x
        next.notes[index].y = frame.origin.y
        next.notes[index].width = frame.width
        next.notes[index].height = frame.height
        engine.replaceData(next)
        publish()
    }

    func setNoteOpen(_ id: UUID, isOpen: Bool) {
        guard canWrite else { return }
        var next = data
        guard let index = next.notes.firstIndex(where: { $0.id == id }) else { return }
        next.notes[index].isOpen = isOpen
        next.notes[index].updatedAt = Date()
        engine.replaceData(next)
        publish()
    }

    func convertNoteToTodos(_ id: UUID, text: String) -> Int {
        guard canWrite else { return 0 }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { feedback = "便签里没有可添加的文字"; return 0 }
        if let previous = lastConversion, previous.0 == id, previous.1 == text,
           Date().timeIntervalSince(previous.2) < 1 { return 0 }
        let now = Date()
        let day = todayKey
        var next = data
        for line in lines { next.todos.append(TodoItem(text: line, localDay: day, createdAt: now)) }
        engine.replaceData(next)
        lastConversion = (id, text, now)
        publish(historyContentChanged: true)
        feedback = "已添加 \(lines.count) 条待办"
        return lines.count
    }

    func summary(for day: String) -> DailySummary { DailySummary.build(day: day, from: data) }

    func workRecord(for scope: WorkScope) -> WorkRecord? { ReviewContextBuilder.record(for: scope, in: data) }

    @discardableResult
    func ensureWorkRecord(for scope: WorkScope) -> UUID {
        if let record = workRecord(for: scope) { return record.id }
        let record: WorkRecord
        switch scope {
        case .session(let id): record = WorkRecord(localDay: data.sessions.first { $0.id == id }?.endedLocalDay ?? todayKey, sessionID: id)
        case .day(let day): record = WorkRecord(localDay: day)
        }
        guard canWrite else { return record.id }
        var next = data
        next.workRecords.append(record)
        engine.replaceData(next)
        publish()
        return record.id
    }

    func updateWorkText(_ text: String, for scope: WorkScope) {
        guard canWrite else { return }
        let id = ensureWorkRecord(for: scope)
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == id }) else { return }
        next.workRecords[index].userText = text
        next.workRecords[index].updatedAt = Date()
        engine.replaceData(next)
        publish(persist: false, historyContentChanged: true)
        workSaveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.publish() }
        workSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func flushWorkChanges() { workSaveTask?.cancel(); if canWrite { publish() } }

    func importWorkImages(_ urls: [URL], for scope: WorkScope) {
        guard canWrite, !generatingScopes.contains(scope.key) else { return }
        let id = ensureWorkRecord(for: scope)
        guard (workRecord(for: scope)?.images.count ?? 0) + urls.count <= 6 else { feedback = "每条成果记录最多添加 6 张图片"; return }
        let store = workImages
        generatingScopes.insert(scope.key)
        Task {
            defer { generatingScopes.remove(scope.key) }
            do {
                let imported = try await Task.detached(priority: .userInitiated) { try store.importImages(at: urls) }.value
                var next = data
                guard let index = next.workRecords.firstIndex(where: { $0.id == id }) else { return }
                next.workRecords[index].images.append(contentsOf: imported)
                next.workRecords[index].updatedAt = Date()
                engine.replaceData(next)
                publish()
                reviewErrors[scope.key] = nil
            } catch { reviewErrors[scope.key] = error.localizedDescription }
        }
    }

    func removeWorkImage(_ imageID: UUID, from scope: WorkScope) {
        guard canWrite, !generatingScopes.contains(scope.key), let record = workRecord(for: scope) else { return }
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == record.id }) else { return }
        next.workRecords[index].images.removeAll { $0.id == imageID }
        next.workRecords[index].updatedAt = Date()
        engine.replaceData(next)
        publish()
    }

    private func readAPIKey(providerID: String) throws -> String? {
        if let injectedKeyReader { return try injectedKeyReader(providerID) }
        return try credentials.read(providerID: providerID)
    }

    func refreshCredentialStatus() {
        do {
            rebuildAIClient()
            guardController.updateAIProvider(aiProvider)
            if let injectedKeyReader { hasAPIKey = try injectedKeyReader(aiProvider.id) != nil }
            else { hasAPIKey = try credentials.isConfigured(providerID: aiProvider.id) }
            aiStatus = hasAPIKey ? "\(aiProvider.name) 已配置，可生成文字和图片成果总结" : "尚未配置 \(aiProvider.name) 的 API Key"
        } catch { hasAPIKey = false; aiStatus = error.localizedDescription }
    }

    /// 设置中的服务商/模型变更后重建 AI 客户端。
    private func rebuildAIClient() {
        let resolved = settings.ai.resolved()
        guard resolved != aiProvider else { return }
        let catalogChanged = resolved.id != aiProvider.id || resolved.baseURL != aiProvider.baseURL
        aiProvider = resolved
        ai = aiClientFactory(resolved)
        if catalogChanged { aiModels = [] }
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do {
            try credentials.save(value, providerID: aiProvider.id)
            refreshCredentialStatus()
            feedback = "\(aiProvider.name) 的 API Key 已保存到本机钥匙串"
            return true
        } catch { aiStatus = error.localizedDescription; return false }
    }

    func removeAPIKey() {
        do {
            stopActivitySampling()
            activityGeneration = UUID()
            try credentials.remove(providerID: aiProvider.id)
            refreshCredentialStatus()
        } catch { aiStatus = error.localizedDescription }
    }

    func updateAIProvider(_ update: (inout AISettings) -> Void) {
        var settings = self.settings
        update(&settings.ai)
        if updateSettings(settings) { refreshCredentialStatus() }
    }

    func fetchAIModels() {
        guard !loadingAIModels else { return }
        loadingAIModels = true
        Task {
            defer { loadingAIModels = false }
            do {
                guard let key = try readAPIKey(providerID: aiProvider.id) else { throw AIReviewError.missingKey }
                let models = try await ai.fetchModels(apiKey: key)
                guard !models.isEmpty else { throw AIReviewError.invalidResponse }
                aiModels = models
                aiStatus = "已获取 \(models.count) 个可用模型，请从列表中选择"
            } catch { aiStatus = error.localizedDescription }
        }
    }

    func testAIConnection() {
        guard !testingAI else { return }
        testingAI = true
        Task {
            defer { testingAI = false }
            do {
                guard let key = try readAPIKey(providerID: aiProvider.id) else { throw AIReviewError.missingKey }
                try await ai.testConnection(apiKey: key)
                hasAPIKey = true
                aiStatus = "\(aiProvider.name) 连接成功"
                fetchAIModels()
            } catch { aiStatus = error.localizedDescription }
        }
    }

    func generateReview(for scope: WorkScope, scheduled: Bool = false, automatic: Bool = false) {
        guard canWrite, !generatingScopes.contains(scope.key) else { return }
        advanceToNow()
        ensureWorkRecord(for: scope)
        generatingScopes.insert(scope.key)
        reviewErrors[scope.key] = nil
        let reviewProvider = aiProvider
        let generation = activityGeneration
        Task {
            defer { generatingScopes.remove(scope.key) }
            do {
                guard let key = try readAPIKey(providerID: aiProvider.id) else { throw AIReviewError.missingKey }
                hasAPIKey = true
                if automatic, case .session(let id) = scope {
                    await identifyActivityTopic(id, final: true)
                    guard settings.review.autoSummarizeSessions || settings.activityRecording.enabled else { return }
                    if deviceLocked {
                        if !pendingSessionReviews.contains(id) { pendingSessionReviews.append(id) }
                        return
                    }
                }
                guard generation == activityGeneration, reviewProvider == aiProvider else { return }
                if automatic, case .session(let id) = scope {
                    guard AutomaticSessionReview.shouldGenerate(sessionID: id, from: data) else { return }
                    var next = data
                    guard let index = next.workRecords.firstIndex(where: { $0.sessionID == id }) else { return }
                    // 在真正发送回顾前落盘；主题判断期间锁屏则等待解锁，尚不消耗这次回顾机会。
                    next.workRecords[index].autoReviewAttemptedAt = Date()
                    engine.replaceData(next)
                    publish()
                    guard canWrite else { return }
                }
                if case .day(let day) = scope {
                    // 先理解尚未总结的各轮文字和图片，再综合全天，避免每天重复上传相同图片。
                    let rounds = data.workRecords.filter { $0.localDay == day && $0.sessionID != nil && (!$0.userText.isEmpty || !$0.images.isEmpty) }
                    for round in rounds {
                        let roundScope = WorkScope.session(round.sessionID!)
                        let context = ReviewContextBuilder.build(for: roundScope, from: data)
                        if round.summary?.contextDigest != context.digest {
                            guard !generatingScopes.contains(roundScope.key) else {
                                throw NSError(domain: "TomatoNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "有一轮成果正在生成，请稍后重新汇总当天。"])
                            }
                            generatingScopes.insert(roundScope.key)
                            defer { generatingScopes.remove(roundScope.key) }
                            try await generateAndStore(roundScope, apiKey: key)
                            guard generation == activityGeneration, reviewProvider == aiProvider else { return }
                        }
                    }
                }
                try await generateAndStore(scope, apiKey: key)
                if !automatic { feedback = "AI 总结已保存" }
                if scheduled, case .day(let day) = scope {
                    finishScheduledReview(day: day, error: nil)
                    onDailyReviewFinished?(day, true)
                }
            } catch {
                reviewErrors[scope.key] = error.localizedDescription
                if scheduled, case .day(let day) = scope {
                    finishScheduledReview(day: day, error: error.localizedDescription)
                    onDailyReviewFinished?(day, false)
                }
            }
        }
    }

    private func generateAndStore(_ scope: WorkScope, apiKey: String) async throws {
        let context = ReviewContextBuilder.build(for: scope, from: data)
        let client = ai
        let generation = activityGeneration
        let images = try context.images.map { image -> Data in
            guard let bytes = try? Data(contentsOf: workImages.url(for: image)) else { throw AIReviewError.missingImage }
            return bytes
        }
        let content = try await client.summarize(context: context, images: images, apiKey: apiKey)
        try Task.checkCancellation()
        guard canWrite, generation == activityGeneration, client.provider == aiProvider else { return }
        let id = ensureWorkRecord(for: scope)
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == id }) else { return }
        next.workRecords[index].summary = AISummary(content: content, model: client.model,
                                                   contextDigest: context.digest, imageIDs: context.images.map(\.id))
        engine.replaceData(next)
        publish(historyContentChanged: true)
    }

    private func checkDailyReviewSchedule() {
        guard let day = ReviewSchedule.dueDay(at: Date(), settings: settings.review, lastAttemptDay: data.lastReviewAttemptDay),
              generatingScopes.isEmpty, pendingSessionReviews.isEmpty, !identifyingActivity else { return }
        generateReview(for: .day(day), scheduled: true)
    }

    private func recordEndedFocus(_ id: UUID) {
        guard let progress = SessionProgress.build(sessionID: id, from: data),
              progress.session.endedAt != nil, progress.focusSeconds > 0 else { return }
        let recordID = ensureWorkRecord(for: .session(id))
        if let day = progress.session.endedLocalDay,
           let index = engine.data.workRecords.firstIndex(where: { $0.id == recordID }), engine.data.workRecords[index].localDay != day {
            var next = engine.data
            next.workRecords[index].localDay = day
            engine.replaceData(next)
        }
        publish(historyContentChanged: true)
        if hasAPIKey, AutomaticSessionReview.shouldGenerate(sessionID: id, from: data), !pendingSessionReviews.contains(id) {
            pendingSessionReviews.append(id)
        }
    }

    private func checkAutomaticSessionReviews() {
        guard settings.review.autoSummarizeSessions || settings.activityRecording.enabled else { pendingSessionReviews.removeAll(); return }
        guard !deviceLocked, hasAPIKey, generatingScopes.isEmpty, !identifyingActivity else { return }
        while !pendingSessionReviews.isEmpty {
            let id = pendingSessionReviews.removeFirst()
            guard AutomaticSessionReview.shouldGenerate(sessionID: id, from: data) else { continue }
            generateReview(for: .session(id), automatic: true)
            return
        }
    }

    func requestActivityChromeAccess() {
        Task {
            do {
                try await activityChrome.requestAccess()
                activityStatus = "Chrome 已授权；专注时自动记录普通页面。"
            } catch { activityStatus = error.localizedDescription }
        }
    }

    private func markAutomaticRecording() {
        guard canWrite, !deviceLocked, ActivityRecorder.isRecording(data), let id = timer.sessionID else { return }
        let recordID = ensureWorkRecord(for: .session(id))
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == recordID }), next.workRecords[index].automaticRecordingUsed != true else { return }
        next.workRecords[index].automaticRecordingUsed = true
        engine.replaceData(next)
        publish()
    }

    private func resetActivityPageSample() {
        sampleGeneration = UUID()
        activitySample = nil
        activitySampleTask?.cancel()
        activitySampleTask = nil
    }

    private func stopActivitySampling() {
        resetActivityPageSample()
        if activityTopicTask != nil, let id = topicSessionID {
            var next = engine.data
            if let index = next.workRecords.firstIndex(where: { $0.sessionID == id }), next.workRecords[index].titleOverride == nil {
                // 主动中止的判断与接口失败不同：允许结束时用同一材料完成首次命名。
                next.workRecords[index].topicAttemptDigest = nil
                engine.replaceData(next)
                publish(persist: false)
            }
        }
        topicRequestID = UUID()
        activityTopicTask?.cancel()
        activityTopicTask = nil
        identifyingActivity = false
        topicSessionID = nil
        noteBaselines.removeAll()
        noteRecordingBlockID = UUID()
        lastActivityTopicCheck = 0
    }

    private func pollActivityPage() {
        guard ActivityRecorder.isRecording(data), !deviceLocked, settings.activityRecording.chromeEnabled,
              Self.frontmostApp()?.bundleID == "com.google.Chrome", let sessionID = timer.sessionID else {
            if activitySample != nil || activitySampleTask != nil { resetActivityPageSample() }
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard activitySampleTask == nil, uptime - lastActivityPoll >= 5 else { return }
        lastActivityPoll = uptime
        let generation = sampleGeneration
        activitySampleTask = Task {
            defer { if generation == sampleGeneration { activitySampleTask = nil } }
            do {
                // 后台采样不触发系统授权弹窗；用户在设置里主动点“允许读取 Chrome”。
                try await activityChrome.requestAccess(askUserIfNeeded: false)
                let raw = try await activityChrome.frontPage()
                guard !Task.isCancelled, generation == sampleGeneration, !deviceLocked, canWrite,
                      ActivityRecorder.isRecording(data), timer.sessionID == sessionID,
                      settings.activityRecording.chromeEnabled, Self.frontmostApp()?.bundleID == "com.google.Chrome" else { return }
                guard let page = ActivityPage(title: raw.title, url: raw.url, isPrivate: raw.isPrivate) else {
                    activitySample = nil; activityStatus = "当前页面不在记录范围内。"; return
                }
                advanceToNow()
                guard ActivityRecorder.isRecording(data), timer.sessionID == sessionID else { return }
                let now = Date()
                let identity = raw.windowID + ":" + raw.tabID
                if let previous = activitySample, previous.identity == identity, previous.page == page {
                    var next = data
                    ActivityRecorder.appendPage(page, sessionID: sessionID, start: previous.at, end: now, to: &next)
                    engine.replaceData(next)
                    publish(persist: false)
                }
                activitySample = (page, identity, now)
                activityStatus = "正在自动记录普通 Chrome 页面。"
            } catch {
                guard generation == sampleGeneration, !Task.isCancelled else { return }
                activitySample = nil
                activityStatus = error.localizedDescription
            }
        }
    }

    private func checkActivityTopic() {
        guard canWrite, !deviceLocked, hasAPIKey, !identifyingActivity, generatingScopes.isEmpty,
              let id = timer.sessionID, ActivityRecorder.isRecording(data) else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastActivityTopicCheck >= 15 else { return }
        lastActivityTopicCheck = uptime
        guard ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data) else { return }
        identifyingActivity = true
        let requestID = UUID()
        topicRequestID = requestID
        topicSessionID = id
        activityTopicTask = Task {
            defer {
                if requestID == topicRequestID { identifyingActivity = false; activityTopicTask = nil; topicSessionID = nil }
            }
            await identifyActivityTopic(id, final: false)
        }
    }

    private func identifyActivityTopic(_ id: UUID, final: Bool) async {
        guard canWrite, !deviceLocked, hasAPIKey, ActivityTopicPolicy.shouldIdentify(sessionID: id, in: data, final: final) else { return }
        let context = ActivityTopicContext.build(sessionID: id, from: data)
        let generation = activityGeneration
        let client = ai
        let recordID = ensureWorkRecord(for: .session(id))
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == recordID }) else { return }
        next.workRecords[index].topicAttemptCount = (next.workRecords[index].topicAttemptCount ?? 0) + 1
        next.workRecords[index].topicAttemptDigest = context.digest
        next.workRecords[index].topicAttemptFocusSeconds = SessionProgress.build(sessionID: id, from: data)?.focusSeconds ?? 0
        if final { next.workRecords[index].finalTopicAttempted = true }
        engine.replaceData(next)
        publish()
        guard canWrite else { return }
        do {
            guard let key = try readAPIKey(providerID: client.provider.id) else { throw AIReviewError.missingKey }
            let result = try await client.identifyActivity(context: context, apiKey: key)
            guard !Task.isCancelled, !deviceLocked, canWrite, generation == activityGeneration, client.provider == aiProvider,
                  settings.activityRecording.enabled else { return }
            guard result.confidence >= 0.75, !result.title.isEmpty else { activityErrors[id] = nil; return }
            var updated = data
            guard let index = updated.workRecords.firstIndex(where: { $0.id == recordID }), updated.workRecords[index].titleOverride == nil else { return }
            let previous = updated.workRecords[index].activityTopic
            let title = ActivityPrivacy.clean(result.title, limit: 60)
            let groupID = result.matchingTopicID ?? (previous?.title == title ? previous?.groupID : nil) ?? UUID()
            updated.workRecords[index].activityTopic = ActivityTopic(groupID: groupID, title: title, confidence: result.confidence,
                evidenceIDs: result.evidenceIDs, model: client.model)
            engine.replaceData(updated)
            publish()
            activityErrors[id] = nil
        } catch {
            guard !Task.isCancelled, generation == activityGeneration else { return }
            activityErrors[id] = error.localizedDescription
        }
    }

    func renameActivitySession(_ id: UUID, title: String) {
        guard canWrite else { return }
        let cleaned = ActivityPrivacy.clean(title, limit: 60)
        guard !cleaned.isEmpty else { return }
        activityGeneration = UUID()
        stopActivitySampling()
        let recordID = ensureWorkRecord(for: .session(id))
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == recordID }) else { return }
        next.workRecords[index].titleOverride = cleaned
        // 用户修改的名称独立成组，下一轮 AI 可以在有新证据时复用这项纠正。
        next.workRecords[index].activityTopic = ActivityTopic(title: cleaned, confidence: 1,
            evidenceIDs: next.workRecords[index].activityTopic?.evidenceIDs ?? [], model: "用户命名")
        next.workRecords[index].updatedAt = Date()
        engine.replaceData(next)
        publish()
    }

    func removeFocusActivity(_ id: UUID) {
        guard canWrite, let activity = data.focusActivities.first(where: { $0.id == id }) else { return }
        activityGeneration = UUID()
        stopActivitySampling()
        let recordID = ensureWorkRecord(for: .session(activity.sessionID))
        var next = data
        let removed = Set(next.focusActivities.filter { $0.sessionID == activity.sessionID && $0.sourceKey == activity.sourceKey }.map(\.id))
        let affectedDays = Set(next.focusActivities.filter { removed.contains($0.id) }.map(\.localDay))
        next.focusActivities.removeAll { removed.contains($0.id) }
        for index in next.workRecords.indices where next.workRecords[index].sessionID == nil && affectedDays.contains(next.workRecords[index].localDay) {
            next.workRecords[index].summary = nil
        }
        if let index = next.workRecords.firstIndex(where: { $0.id == recordID }) {
            next.workRecords[index].excludedActivityKeys = Array(Set((next.workRecords[index].excludedActivityKeys ?? []) + [activity.sourceKey]))
            next.workRecords[index].summary = nil
            if next.workRecords[index].titleOverride == nil,
               !(Set(next.workRecords[index].activityTopic?.evidenceIDs ?? []).intersection(removed)).isEmpty {
                next.workRecords[index].activityTopic = nil
            }
            next.workRecords[index].updatedAt = Date()
        }
        engine.replaceData(next)
        publish(historyContentChanged: true)
    }

    private func finishScheduledReview(day: String, error: String?) {
        guard canWrite else { return }
        var next = data
        next.lastReviewAttemptDay = day
        next.lastReviewError = error
        engine.replaceData(next)
        publish()
    }

    private func advanceToNow() {
        guard timer.phase == .running, let previous = lastUptime else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let delta = max(0, uptime - previous)
        lastUptime = uptime
        guard delta > 0 else { return }
        let sessionID = timer.sessionID
        if let sessionID, let plan = guardController.plan,
           guardController.sessionID == sessionID {
            engine.setWhitelistBundleIDs(plan.applicationWhitelistBundleIDs, for: sessionID)
        }
        let hadSessionInterval = sessionID.map { id in data.intervals.contains { $0.sessionID == id } } ?? true
        let completed = engine.advance(seconds: delta, endingAt: Date(), app: currentApp,
                                       recordingEnabled: settings.recordingEnabled)
        let next = engine.data.timer.nextStage
        let firstIntervalRecorded = !hadSessionInterval && (sessionID.map { id in
            engine.data.intervals.contains { $0.sessionID == id }
        } ?? false)
        publish(persist: completed || uptime - lastSavedUptime >= 2,
                historyContentChanged: firstIntervalRecorded,
                focusHeatmapChanged: completed && sessionID != nil)
        if completed {
            lastUptime = nil
            stopActivitySampling()
            if let id = sessionID { recordEndedFocus(id) }
            onStageCompleted?(next ?? .focus)
        }
    }

    private func publish(persist: Bool = true, historyContentChanged: Bool = false,
                         focusHeatmapChanged: Bool = false) {
        data = engine.data
        if historyContentChanged { historySearchRevision &+= 1 }
        if focusHeatmapChanged { focusHeatmapRevision &+= 1 }
        if persist {
            do {
                try repository.save(data)
                lastSavedUptime = ProcessInfo.processInfo.systemUptime
            } catch { errorMessage = "保存本地数据失败：\(error.localizedDescription)" }
        }
        syncFocusMode()
        onDataChanged?()
    }

    private func syncFocusMode() {
        let shouldEnable = focusModeEnabled && timer.stage == .focus && timer.phase == .running
        focusModeShortcut.setActive(shouldEnable)
    }

    static func frontmostApp() -> AppIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let name = app.localizedName, let bundleID = app.bundleIdentifier else { return nil }
        return AppIdentity(name: name, bundleID: bundleID)
    }

    static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }

    private func shouldPauseForLid(_ closed: Bool) -> Bool {
        DevicePolicy.shouldPauseForLid(closed: closed,
                                       externalDisplayActive: Self.hasActiveExternalDisplay(),
                                       allowExternalWork: settings.allowClamshellWithExternalDisplay)
    }

    static func hasActiveExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let display = CGDirectDisplayID(number.uint32Value)
            return CGDisplayIsBuiltin(display) == 0 && CGDisplayIsActive(display) != 0
        }
    }
}
