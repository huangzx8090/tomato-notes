import Foundation
import Testing
@testable import TomatoCore

struct DataProtectionTests {
    @Test func lockRejectsSecondWriterIncludingSymlinkAndReleases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("real")
        let repository = LocalRepository(fileURL: directory.appendingPathComponent("data.json"))
        var lock: RepositoryLock? = try RepositoryLock(repository: repository)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let aliased = LocalRepository(fileURL: link.appendingPathComponent("data.json"))
        do {
            _ = try RepositoryLock(repository: aliased)
            Issue.record("第二个写入者不能获得锁")
        } catch RepositoryLockError.inUse(let pid) {
            #expect(pid == ProcessInfo.processInfo.processIdentifier)
        }
        #expect(lock != nil)
        lock = nil
        let reopened = try RepositoryLock(repository: repository)
        withExtendedLifetime(reopened) {}
    }

    @Test func backupPreservesOriginalBytesAndNeverOverwritesPreviousBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(fileURL: directory.appendingPathComponent("data.json"))
        try repository.save(AppData())
        let bytes = try Data(contentsOf: repository.fileURL)
        let first = try #require(try repository.backup())
        let second = try #require(try repository.backup())
        #expect(first != second)
        #expect(try Data(contentsOf: first) == bytes)
        #expect(try Data(contentsOf: second) == bytes)
        #expect(try Data(contentsOf: repository.fileURL) == bytes)
    }

    @Test func mergeDeduplicatesStableIDsAndPreservesPauseAndAccounting() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var engine = TimerEngine(data: AppData())
        engine.start(at: now)
        _ = engine.advance(seconds: 12.5, endingAt: now.addingTimeInterval(12.5), app: nil, recordingEnabled: true)
        let primary = engine.data
        var incoming = AppData()
        incoming.todos = [TodoItem(text: "保留中文输入", localDay: "2026-10-21")]
        var note = StickyNote()
        note.text = "第一行\n第二行"
        note.width = 425
        incoming.notes = [note]
        let merged = try DataMerger.merge(primary: primary, importing: [primary, incoming, incoming])
        #expect(merged.timer.phase == .paused)
        #expect(merged.timer.remainingSeconds == primary.timer.remainingSeconds)
        #expect(merged.sessions.count == 1)
        #expect(merged.intervals.reduce(0) { $0 + $1.seconds } == 12.5)
        #expect(merged.usage.reduce(0) { $0 + $1.seconds } == 12.5)
        #expect(merged.todos.count == 1)
        #expect(merged.notes.count == 1)
        #expect(merged.notes[0].width == 425)
        #expect(primary.timer.phase == .running)
    }

    @Test func mergeRejectsDifferentContentsForSameIDAndUnbalancedRecords() throws {
        var primary = AppData()
        primary.todos = [TodoItem(text: "原始内容", localDay: "2026-10-21")]
        var conflict = primary
        conflict.todos[0].text = "另一份不同内容"
        #expect(throws: DataMergeError.self) { try DataMerger.merge(primary: primary, importing: [conflict]) }
        var engine = TimerEngine(data: AppData())
        engine.start(at: Date())
        _ = engine.advance(seconds: 3, endingAt: Date(), app: nil, recordingEnabled: true)
        var broken = engine.data
        broken.usage.removeAll()
        #expect(throws: DataMergeError.self) { try DataMerger.merge(primary: broken, importing: []) }
        #expect(primary.todos[0].text == "原始内容")
    }

    @Test func mergeEndsUnselectedOpenSessionWithoutCreatingFocusTime() throws {
        var engine = TimerEngine(data: AppData())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        engine.start(at: start)
        _ = engine.advance(seconds: 7, endingAt: start.addingTimeInterval(7), app: nil, recordingEnabled: false)
        let merged = try DataMerger.merge(primary: AppData(), importing: [engine.data])
        #expect(merged.timer.phase == .idle)
        #expect(merged.sessions[0].endedAt == start.addingTimeInterval(7))
        #expect(!merged.sessions[0].completed)
        #expect(merged.intervals.reduce(0) { $0 + $1.seconds } == 7)
    }
}
