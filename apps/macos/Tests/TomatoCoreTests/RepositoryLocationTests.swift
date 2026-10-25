import Foundation
import Testing
@testable import TomatoCore

struct RepositoryLocationTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @Test func ordinaryLaunchesShareOneLibraryAcrossBundleIdentifiers() throws {
        let directory = root()
        for bundleID in [nil, "com.zixuan.TomatoNotes", "com.zixuan.TomatoNotes.QA", "com.zixuan.TomatoNotes.GuardQA", "renamed.preview"] as [String?] {
            let repository = try RepositoryLocation.resolve(arguments: [], bundleIdentifier: bundleID,
                                                            applicationSupportDirectory: directory)
            #expect(repository.fileURL == directory.appendingPathComponent("TomatoNotes/data.json").standardizedFileURL.resolvingSymlinksInPath())
        }
    }

    @Test func explicitTestModeAlwaysUsesSeparateData() throws {
        let directory = root()
        for bundleID in [nil, "com.zixuan.TomatoNotes", "com.zixuan.TomatoNotes.QA", "com.zixuan.TomatoNotes.GuardQA"] as [String?] {
            let repository = try RepositoryLocation.resolve(arguments: ["--ui-test"], bundleIdentifier: bundleID,
                                                            applicationSupportDirectory: directory)
            let name = bundleID == "com.zixuan.TomatoNotes.GuardQA" ? "TomatoNotes-GuardQA" : "TomatoNotes-QA"
            #expect(repository.fileURL == LocalRepository(fileURL: directory.appendingPathComponent("\(name)/data.json")).fileURL)
        }
        let custom = directory.appendingPathComponent("custom")
        let repository = try RepositoryLocation.resolve(arguments: ["--ui-test", "--data-dir", custom.path], bundleIdentifier: nil,
                                                        applicationSupportDirectory: directory)
        #expect(repository.fileURL == LocalRepository(fileURL: custom.appendingPathComponent("data.json")).fileURL)
    }

    @Test func invalidArgumentsNeverFallBackToSharedData() throws {
        let directory = root()
        for arguments in [["--data-dir"], ["--data-dir", ""], ["--data-dir", "--show-panel"],
                          ["--data-dir", "/tmp/one", "--data-dir", "/tmp/two"],
                          ["--shared-data", "--ui-test"], ["--shared-data", "--data-dir", "/tmp/one"]] {
            #expect(throws: RepositoryLocationError.self) {
                try RepositoryLocation.resolve(arguments: arguments, bundleIdentifier: nil, applicationSupportDirectory: directory)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func testsRejectSharedDirectoryIncludingSymlink() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = directory.appendingPathComponent("TomatoNotes")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: shared)
        for location in [shared, alias] {
            #expect(throws: RepositoryLocationError.self) {
                try RepositoryLocation.resolve(arguments: ["--ui-test", "--data-dir", location.path], bundleIdentifier: nil,
                                               applicationSupportDirectory: directory)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: shared.appendingPathComponent("data.json").path))
    }

    @Test func anotherBuildReopensSameTimerAndRecordsAndCannotBecomeSecondWriter() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try RepositoryLocation.resolve(arguments: [], bundleIdentifier: "com.zixuan.TomatoNotes",
                                                   applicationSupportDirectory: directory)
        let second = try RepositoryLocation.resolve(arguments: [], bundleIdentifier: "com.zixuan.TomatoNotes.QA",
                                                    applicationSupportDirectory: directory)
        var lock: RepositoryLock? = try RepositoryLock(repository: first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var engine = TimerEngine(data: AppData())
        engine.start(at: now)
        _ = engine.advance(seconds: 12, endingAt: now.addingTimeInterval(12), app: nil, recordingEnabled: true)
        engine.pause(reason: "手动暂停", at: now.addingTimeInterval(12))
        var saved = engine.data
        saved.todos = [TodoItem(text: "共用待办", localDay: LocalTime.dayKey(now))]
        var note = StickyNote(at: now)
        note.text = "共用便签"
        saved.notes = [note]
        try first.save(saved)
        #expect(throws: RepositoryLockError.self) { try RepositoryLock(repository: second) }
        #expect(lock != nil)
        lock = nil
        let newLock = try RepositoryLock(repository: second)
        try withExtendedLifetime(newLock) {
            let restored = try second.load()
            #expect(restored.timer.sessionID == saved.timer.sessionID)
            #expect(restored.timer.phase == .paused)
            #expect(restored.timer.remainingSeconds == saved.timer.remainingSeconds)
            #expect(restored.sessions.map(\.id) == saved.sessions.map(\.id))
            #expect(restored.intervals.reduce(0) { $0 + $1.seconds } == 12)
            #expect(restored.todos.first?.id == saved.todos.first?.id)
            #expect(restored.notes.first?.text == "共用便签")
        }
    }
}
