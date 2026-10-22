import AppKit
import CoreGraphics
import Foundation
import IOKit
import TomatoCore
import TomatoSystem

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var errorMessage: String?
    @Published var feedback: String?
    @Published private(set) var lastDeletedTodo: TodoItem?
    @Published var notificationStatus = "首次开始或测试提醒时申请通知权限"
    @Published private(set) var calendarDay = LocalTime.dayKey(Date())
    @Published private(set) var generatingScopes: Set<String> = []
    @Published private(set) var reviewErrors: [String: String] = [:]
    @Published private(set) var hasAPIKey = false
    @Published var aiStatus = "尚未配置 AI 服务商 API Key"
    @Published private(set) var testingAI = false
    @Published private(set) var aiModels: [String] = []
    @Published private(set) var loadingAIModels = false
    @Published var guardSetupPresented = false
    @Published var focusGoalDraft = ""

    let repository: LocalRepository
    let workImages: WorkImageStore
    let guardController = FocusGuardController()
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

    init(repository: LocalRepository = LocalRepository()) {
        self.repository = repository
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
        refreshCredentialStatus()
        guardController.currentSnapshot = { [weak self] in
            guard let self else { return (TimerSnapshot(), true, FocusGuardSettings()) }
            return (self.timer, self.deviceLocked, self.settings.focusGuard)
        }
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
            lastUptime = nil
            publish()
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
        publish()
        onStarted?()
    }

    func tick() {
        let day = LocalTime.dayKey(Date())
        if day != calendarDay { calendarDay = day }
        guard canWrite else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastLidCheck >= 1 {
            lidClosed = Self.isLidClosed()
            lastLidCheck = uptime
        }
        if timer.phase == .running && (deviceLocked || shouldPauseForLid(lidClosed)) {
            // 合盖通知可能不伴随睡眠，检测后立刻冻结最近检查点。
            engine.pause(reason: deviceLocked ? "锁屏已暂停" : "合盖已暂停", at: Date())
            lastUptime = nil
            publish()
            return
        }
        advanceToNow()
        if timerOnlySessionID != timer.sessionID || timer.phase == .completed || timer.phase == .idle {
            timerOnlySessionID = nil
        }
        guardController.tick(timer: timer, locked: deviceLocked, settings: settings.focusGuard)
        checkAutomaticSessionReviews()
        if uptime - lastReviewCheck >= 15, !deviceLocked {
            lastReviewCheck = uptime
            checkDailyReviewSchedule()
        }
    }

    func pauseForSystem(_ reason: String) {
        guard canWrite, timer.phase == .running else { return }
        advanceToNow()
        engine.pause(reason: reason, at: Date())
        lastUptime = nil
        publish()
    }

    func appDidChange() {
        guard canWrite else { return }
        advanceToNow()
        currentApp = Self.frontmostApp()
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
        publish()
        if let id = endingSessionID { recordEndedFocus(id) }
    }

    func prepareForQuit() {
        guardController.stop()
        guard canWrite else { return }
        advanceToNow()
        if timer.phase == .running { engine.pause(reason: "应用退出已暂停", at: Date()) }
        publish()
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
            publish()
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
        var next = data
        next.settings = value
        if next.timer.phase == .idle {
            next.timer.targetSeconds = value.duration(for: .focus)
            next.timer.remainingSeconds = next.timer.targetSeconds
        }
        engine.replaceData(next)
        publish()
        feedback = "设置已保存"
        return true
    }

    func addTodo(_ text: String) {
        guard canWrite else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = data
        next.todos.append(TodoItem(text: trimmed, localDay: todayKey))
        engine.replaceData(next)
        publish()
    }

    @discardableResult
    func toggleTodo(_ id: UUID) -> Bool {
        guard canWrite else { return false }
        advanceToNow()
        var next = data
        guard let index = next.todos.firstIndex(where: { $0.id == id && $0.localDay == todayKey }) else { return false }
        next.todos[index].completedAt = next.todos[index].completedAt == nil ? Date() : nil
        engine.replaceData(next)
        publish()
        return canWrite && next.todos[index].isCompleted
    }

    func updateTodo(_ id: UUID, text: String) {
        guard canWrite else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = data
        guard let index = next.todos.firstIndex(where: { $0.id == id && $0.localDay == todayKey }) else { return }
        next.todos[index].text = trimmed
        engine.replaceData(next)
        publish()
    }

    func deleteTodo(_ id: UUID) {
        guard canWrite else { return }
        var next = data
        var history = todoDeletionHistory
        guard history.remove(id, on: todayKey, from: &next.todos) else { return }
        engine.replaceData(next)
        publish()
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
            publish()
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

    func createNote() -> UUID? {
        guard canWrite else { return nil }
        var next = data
        let note = StickyNote()
        next.notes.append(note)
        engine.replaceData(next)
        publish()
        return note.id
    }

    func note(_ id: UUID) -> StickyNote? { data.notes.first { $0.id == id } }

    func continueNote(_ id: UUID) -> UUID? {
        guard canWrite else { return nil }
        var next = data
        guard let copyID = NoteLibrary.continueNote(id, in: &next.notes) else { return nil }
        engine.replaceData(next)
        publish()
        return canWrite ? copyID : nil
    }

    @discardableResult
    func deleteNote(_ id: UUID) -> Bool {
        guard canWrite, data.notes.contains(where: { $0.id == id }) else { return false }
        var next = data
        next.notes.removeAll { $0.id == id }
        engine.replaceData(next)
        publish()
        if canWrite { feedback = "便签已删除" }
        return canWrite
    }

    func updateNoteText(_ id: UUID, text: String) {
        guard canWrite else { return }
        var next = data
        guard let index = next.notes.firstIndex(where: { $0.id == id }) else { return }
        next.notes[index].text = text
        next.notes[index].updatedAt = Date()
        engine.replaceData(next)
        publish()
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
        var next = data
        for line in lines { next.todos.append(TodoItem(text: line, localDay: todayKey, createdAt: now)) }
        engine.replaceData(next)
        lastConversion = (id, text, now)
        publish()
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
        publish(persist: false)
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

    func refreshCredentialStatus() {
        do {
            rebuildAIClient()
            guardController.updateAIProvider(aiProvider)
            hasAPIKey = try credentials.isConfigured(providerID: aiProvider.id)
            aiStatus = hasAPIKey ? "\(aiProvider.name) 已配置，可生成文字和图片成果总结" : "尚未配置 \(aiProvider.name) 的 API Key"
        } catch { hasAPIKey = false; aiStatus = error.localizedDescription }
    }

    /// 设置中的服务商/模型变更后重建 AI 客户端。
    private func rebuildAIClient() {
        let resolved = settings.ai.resolved()
        guard resolved != aiProvider else { return }
        aiProvider = resolved
        ai = AIReviewClient(provider: resolved)
        aiModels = []
    }

    func saveAPIKey(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try credentials.save(value, providerID: aiProvider.id)
            refreshCredentialStatus()
            feedback = "\(aiProvider.name) 的 API Key 已保存到本机钥匙串"
        } catch { aiStatus = error.localizedDescription }
    }

    func removeAPIKey() {
        do {
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
                guard let key = try credentials.read(providerID: aiProvider.id) else { throw AIReviewError.missingKey }
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
                guard let key = try credentials.read(providerID: aiProvider.id) else { throw AIReviewError.missingKey }
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
        Task {
            defer { generatingScopes.remove(scope.key) }
            do {
                guard let key = try credentials.read(providerID: aiProvider.id) else { throw AIReviewError.missingKey }
                hasAPIKey = true
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
        let images = try context.images.map { image -> Data in
            guard let bytes = try? Data(contentsOf: workImages.url(for: image)) else { throw AIReviewError.missingImage }
            return bytes
        }
        let content = try await ai.summarize(context: context, images: images, apiKey: apiKey)
        guard canWrite else { return }
        let id = ensureWorkRecord(for: scope)
        var next = data
        guard let index = next.workRecords.firstIndex(where: { $0.id == id }) else { return }
        next.workRecords[index].summary = AISummary(content: content, model: aiProvider.defaultModel,
                                                   contextDigest: context.digest, imageIDs: context.images.map(\.id))
        engine.replaceData(next)
        publish()
    }

    private func checkDailyReviewSchedule() {
        guard let day = ReviewSchedule.dueDay(at: Date(), settings: settings.review, lastAttemptDay: data.lastReviewAttemptDay),
              generatingScopes.isEmpty, pendingSessionReviews.isEmpty else { return }
        generateReview(for: .day(day), scheduled: true)
    }

    private func recordEndedFocus(_ id: UUID) {
        guard let progress = SessionProgress.build(sessionID: id, from: data),
              progress.session.endedAt != nil, progress.focusSeconds > 0 else { return }
        ensureWorkRecord(for: .session(id))
        if hasAPIKey, AutomaticSessionReview.shouldGenerate(sessionID: id, from: data), !pendingSessionReviews.contains(id) {
            pendingSessionReviews.append(id)
        }
    }

    private func checkAutomaticSessionReviews() {
        guard settings.review.autoSummarizeSessions else { pendingSessionReviews.removeAll(); return }
        guard !deviceLocked, hasAPIKey, generatingScopes.isEmpty else { return }
        while !pendingSessionReviews.isEmpty {
            let id = pendingSessionReviews.removeFirst()
            guard AutomaticSessionReview.shouldGenerate(sessionID: id, from: data) else { continue }
            let recordID = ensureWorkRecord(for: .session(id))
            var next = data
            guard let index = next.workRecords.firstIndex(where: { $0.id == recordID }) else { continue }
            // 先落盘再发送，退出或断网后也不会悄悄重试同一轮。
            next.workRecords[index].autoReviewAttemptedAt = Date()
            engine.replaceData(next)
            publish()
            guard canWrite else { return }
            generateReview(for: .session(id), automatic: true)
            return
        }
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
        let completed = engine.advance(seconds: delta, endingAt: Date(), app: currentApp,
                                       recordingEnabled: settings.recordingEnabled)
        let next = engine.data.timer.nextStage
        publish(persist: completed || uptime - lastSavedUptime >= 2)
        if completed {
            lastUptime = nil
            if let id = sessionID { recordEndedFocus(id) }
            onStageCompleted?(next ?? .focus)
        }
    }

    private func publish(persist: Bool = true) {
        data = engine.data
        if persist {
            do {
                try repository.save(data)
                lastSavedUptime = ProcessInfo.processInfo.systemUptime
            } catch { errorMessage = "保存本地数据失败：\(error.localizedDescription)" }
        }
        onDataChanged?()
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
