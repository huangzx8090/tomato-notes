import AppKit
import CoreGraphics
import Foundation
import IOKit
import TomatoCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var errorMessage: String?
    @Published var feedback: String?
    @Published var notificationStatus = "首次开始或测试提醒时申请通知权限"
    @Published private(set) var calendarDay = LocalTime.dayKey(Date())

    let repository: LocalRepository
    var onDataChanged: (() -> Void)?
    var onStageCompleted: ((TimerStage) -> Void)?
    var onStarted: (() -> Void)?
    var applyHotkeys: ((AppSettings) -> String?)?
    var deviceLocked = false
    private var engine: TimerEngine
    private var lastUptime: TimeInterval?
    private var lastSavedUptime: TimeInterval = 0
    private var lastLidCheck: TimeInterval = 0
    private var lidClosed = false
    private var currentApp: AppIdentity?
    private var lastConversion: (UUID, String, Date)?

    init(repository: LocalRepository = LocalRepository()) {
        self.repository = repository
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
    }

    var canWrite: Bool { errorMessage == nil }
    var todayKey: String { LocalTime.dayKey(Date()) }
    var timer: TimerSnapshot { data.timer }
    var settings: AppSettings { data.settings }

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
        engine.start(at: Date())
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
    }

    func endEarlyOrSkip() {
        guard canWrite else { return }
        advanceToNow()
        if timer.phase == .completed { engine.skipBreak(at: Date()) }
        else if timer.stage == .focus { engine.endEarly(at: Date()) }
        else { engine.skipBreak(at: Date()) }
        lastUptime = nil
        publish()
    }

    func prepareForQuit() {
        guard canWrite else { return }
        advanceToNow()
        if timer.phase == .running { engine.pause(reason: "应用退出已暂停", at: Date()) }
        publish()
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

    func toggleTodo(_ id: UUID) {
        guard canWrite else { return }
        var next = data
        guard let index = next.todos.firstIndex(where: { $0.id == id && $0.localDay == todayKey }) else { return }
        next.todos[index].completedAt = next.todos[index].completedAt == nil ? Date() : nil
        engine.replaceData(next)
        publish()
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

    private func advanceToNow() {
        guard timer.phase == .running, let previous = lastUptime else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let delta = max(0, uptime - previous)
        lastUptime = uptime
        guard delta > 0 else { return }
        let completed = engine.advance(seconds: delta, endingAt: Date(), app: currentApp,
                                       recordingEnabled: settings.recordingEnabled)
        let next = engine.data.timer.nextStage
        publish(persist: completed || uptime - lastSavedUptime >= 2)
        if completed {
            lastUptime = nil
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
