import Foundation

public struct TimerEngine {
    public private(set) var data: AppData

    public init(data: AppData) { self.data = data }

    public mutating func replaceData(_ data: AppData) { self.data = data }

    public mutating func recoverAfterLaunch() {
        if data.timer.phase == .running {
            data.timer.phase = .paused
            data.timer.pauseReason = "已恢复上次计时，等待继续"
            data.timer.updatedAt = Date()
        }
    }

    public mutating func start(at now: Date, goal: String? = nil,
                               whitelistedBundleIDs: [String]? = nil) {
        switch data.timer.phase {
        case .running: return
        case .paused:
            data.timer.phase = .running
            data.timer.pauseReason = nil
        case .idle, .completed:
            if data.timer.phase == .completed {
                data.timer.stage = data.timer.nextStage ?? .focus
                data.timer.nextStage = nil
            }
            data.timer.targetSeconds = data.settings.duration(for: data.timer.stage)
            data.timer.remainingSeconds = data.timer.targetSeconds
            data.timer.phase = .running
            data.timer.pauseReason = nil
            if data.timer.stage == .focus {
                let session = FocusSession(startedAt: now, goal: goal,
                                           whitelistedBundleIDs: whitelistedBundleIDs)
                data.timer.sessionID = session.id
                data.sessions.append(session)
            } else {
                data.timer.sessionID = nil
            }
        }
        data.timer.updatedAt = now
    }

    public mutating func pause(reason: String, at now: Date) {
        guard data.timer.phase == .running else { return }
        data.timer.phase = .paused
        data.timer.pauseReason = reason
        data.timer.updatedAt = now
    }

    public mutating func advance(seconds requested: Double, endingAt now: Date,
                                 app: AppIdentity?, recordingEnabled: Bool,
                                 calendar: Calendar = .current) -> Bool {
        guard data.timer.phase == .running, requested > 0 else { return false }
        let used = min(requested, data.timer.remainingSeconds)
        let end = now.addingTimeInterval(-(requested - used))
        let start = end.addingTimeInterval(-used)

        if data.timer.stage == .focus, let sessionID = data.timer.sessionID {
            // 独立累计白名单外时长；即使关闭 App 明细记录，也保留这项汇总。
            if let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
               let bundleIDs = data.sessions[index].whitelistedBundleIDs,
               let seconds = data.sessions[index].outsideWhitelistSeconds,
               let app,
               !app.bundleID.hasPrefix("com.zixuan.TomatoNotes"),
               !bundleIDs.contains(app.bundleID) {
                data.sessions[index].outsideWhitelistSeconds = seconds + used
            }
            for part in LocalTime.split(start: start, end: end, effectiveSeconds: used, calendar: calendar) {
                appendInterval(part, sessionID: sessionID)
                let kind: UsageKind = !recordingEnabled ? .disabled : (app == nil ? .unattributed : .app)
                appendUsage(part, sessionID: sessionID, kind: kind, app: app)
            }
        }

        data.timer.remainingSeconds = max(0, data.timer.remainingSeconds - used)
        data.timer.updatedAt = end
        if data.timer.remainingSeconds <= 0.000_001 {
            complete(at: end, calendar: calendar)
            return true
        }
        return false
    }

    public mutating func endEarly(at now: Date, calendar: Calendar = .current) {
        guard data.timer.stage == .focus,
              data.timer.phase == .running || data.timer.phase == .paused else { return }
        finishSession(at: now, completed: false, reason: "提前结束", calendar: calendar)
        data.timer.stage = .focus
        data.timer.phase = .idle
        data.timer.nextStage = nil
        data.timer.sessionID = nil
        data.timer.targetSeconds = data.settings.duration(for: .focus)
        data.timer.remainingSeconds = data.timer.targetSeconds
        data.timer.pauseReason = nil
        data.timer.updatedAt = now
    }

    public mutating func setWhitelistBundleIDs(_ bundleIDs: [String]?, for sessionID: UUID) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].endedAt == nil else { return }
        let normalized = bundleIDs.map { Array(Set($0)).sorted() }
        guard data.sessions[index].whitelistedBundleIDs != normalized else { return }
        data.sessions[index].whitelistedBundleIDs = normalized
        if normalized == nil {
            data.sessions[index].outsideWhitelistSeconds = nil
        } else if data.sessions[index].outsideWhitelistSeconds == nil {
            data.sessions[index].outsideWhitelistSeconds = 0
        }
    }

    public mutating func skipBreak(at now: Date) {
        if data.timer.phase == .completed, let next = data.timer.nextStage, next != .focus {
            if next == .longBreak { data.timer.completedInSet = 0 }
            resetForFocus(at: now)
            return
        }
        guard data.timer.stage != .focus,
              data.timer.phase == .running || data.timer.phase == .paused else { return }
        if data.timer.stage == .longBreak { data.timer.completedInSet = 0 }
        resetForFocus(at: now)
    }

    private mutating func complete(at now: Date, calendar: Calendar) {
        guard data.timer.phase == .running else { return }
        let finished = data.timer.stage
        data.timer.phase = .completed
        data.timer.pauseReason = nil
        if finished == .focus {
            finishSession(at: now, completed: true, reason: "自然完成", calendar: calendar)
            data.timer.completedInSet += 1
            data.timer.nextStage = data.timer.completedInSet >= data.settings.longBreakEvery ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak { data.timer.completedInSet = 0 }
            data.timer.nextStage = .focus
        }
        data.timer.sessionID = nil
    }

    private mutating func resetForFocus(at now: Date) {
        data.timer.stage = .focus
        data.timer.phase = .idle
        data.timer.nextStage = nil
        data.timer.sessionID = nil
        data.timer.targetSeconds = data.settings.duration(for: .focus)
        data.timer.remainingSeconds = data.timer.targetSeconds
        data.timer.pauseReason = nil
        data.timer.updatedAt = now
    }

    private mutating func finishSession(at now: Date, completed: Bool, reason: String, calendar: Calendar) {
        guard let id = data.timer.sessionID,
              let index = data.sessions.firstIndex(where: { $0.id == id }),
              data.sessions[index].endedAt == nil else { return }
        data.sessions[index].endedAt = now
        data.sessions[index].endedLocalDay = LocalTime.dayKey(now, calendar: calendar)
        data.sessions[index].endTimeZoneID = calendar.timeZone.identifier
        data.sessions[index].completed = completed
        data.sessions[index].endReason = reason
        // 只把本轮结果留在历史记录中，不长期保存本轮白名单。
        data.sessions[index].whitelistedBundleIDs = nil
    }

    private mutating func appendInterval(_ piece: LocalTime.Piece, sessionID: UUID) {
        if let index = data.intervals.indices.last,
           data.intervals[index].sessionID == sessionID,
           data.intervals[index].localDay == piece.day,
           data.intervals[index].timeZoneID == piece.timeZoneID,
           abs(data.intervals[index].endedAt.timeIntervalSince(piece.start)) < 0.005 {
            data.intervals[index].endedAt = piece.end
            data.intervals[index].seconds += piece.seconds
        } else {
            data.intervals.append(FocusInterval(sessionID: sessionID,
                                                startedAt: piece.start, endedAt: piece.end,
                                                localDay: piece.day, timeZoneID: piece.timeZoneID,
                                                seconds: piece.seconds))
        }
    }

    private mutating func appendUsage(_ piece: LocalTime.Piece, sessionID: UUID,
                                      kind: UsageKind, app: AppIdentity?) {
        if let index = data.usage.indices.last,
           data.usage[index].sessionID == sessionID,
           data.usage[index].localDay == piece.day,
           data.usage[index].kind == kind,
           data.usage[index].bundleID == (kind == .app ? app?.bundleID : nil),
           data.usage[index].timeZoneID == piece.timeZoneID,
           abs(data.usage[index].endedAt.timeIntervalSince(piece.start)) < 0.005 {
            data.usage[index].endedAt = piece.end
            data.usage[index].seconds += piece.seconds
        } else {
            data.usage.append(AppUsageSegment(sessionID: sessionID, kind: kind,
                                              appName: kind == .app ? app?.name : nil,
                                              bundleID: kind == .app ? app?.bundleID : nil,
                                              startedAt: piece.start, endedAt: piece.end,
                                              localDay: piece.day, timeZoneID: piece.timeZoneID,
                                              seconds: piece.seconds))
        }
    }
}
