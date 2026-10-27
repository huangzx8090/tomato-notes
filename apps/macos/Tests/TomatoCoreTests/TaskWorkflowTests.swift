import Foundation
import Testing
@testable import TomatoCore

struct TaskWorkflowTests {
    @Test func remindersAreScheduledWithoutDuplicatingOrChangingHistory() {
        var workflow = TaskWorkflow()
        let id = workflow.scheduleReminder(listID: "list", reminderID: "r1", externalID: "external", day: "2026-10-27")
        #expect(workflow.scheduleReminder(listID: "list", reminderID: "r1", externalID: "external", day: "2026-10-27") == id)
        #expect(workflow.scheduleReminder(listID: "list", reminderID: "r1", externalID: "external", day: "2026-10-28") == id)
        #expect(workflow.plannedReminders.count == 1)
        workflow.unscheduleReminder(id: id, day: "2026-10-28")
        #expect(workflow.plannedReminders[0].scheduledDays == ["2026-10-27"])
        let other = workflow.scheduleReminder(listID: "other-list", reminderID: "r1", externalID: nil, day: "2026-10-27")
        #expect(other != id)
    }

    @Test func sessionLinksAreStableAndPersistThroughExistingDataContract() throws {
        var workflow = TaskWorkflow()
        workflow.remindersEnabled = true
        workflow.selectedListIDs = ["selected"]
        let task = TaskReference(source: .local, id: UUID())
        let session = UUID()
        workflow.bind(sessionID: session, to: task)
        workflow.bind(sessionID: session, to: TaskReference(source: .local, id: UUID()))
        workflow.localProgress.append(.init(todoID: task.id, sessionID: session, text: "已核对第一步"))
        var data = AppData()
        data.extraFields["anotherPlatform"] = .string("keep")
        try workflow.save(into: &data)
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        #expect(restored.schemaVersion == AppData.currentSchemaVersion)
        #expect(restored.extraFields["anotherPlatform"] == .string("keep"))
        #expect(try TaskWorkflow.load(from: restored) == workflow)
        #expect(try TaskWorkflow.load(from: restored).task(for: session) == task)
    }

    @Test func dataMergeRetainsImportedWorkflowAndRejectsConflictingLinks() throws {
        let session = UUID(), todo = UUID()
        var source = AppData()
        var incoming = TaskWorkflow()
        incoming.remindersEnabled = true
        incoming.selectedListIDs = ["source-list"]
        incoming.bind(sessionID: session, to: .init(source: .local, id: todo))
        incoming.localProgress.append(.init(todoID: todo, sessionID: session, text: "模拟进展"))
        try incoming.save(into: &source)
        let merged = try DataMerger.merge(primary: AppData(), importing: [source, source])
        let workflow = try TaskWorkflow.load(from: merged)
        #expect(!workflow.remindersEnabled && workflow.selectedListIDs.isEmpty)
        #expect(workflow.task(for: session) == .init(source: .local, id: todo))
        #expect(workflow.localProgress.count == 1 && workflow.localProgress.first?.text == "模拟进展")
        var conflict = AppData()
        var different = TaskWorkflow()
        different.bind(sessionID: session, to: .init(source: .local, id: UUID()))
        try different.save(into: &conflict)
        #expect(throws: DataMergeError.self) { try DataMerger.merge(primary: source, importing: [conflict]) }
    }

    @Test func unsupportedMetadataIsNotSilentlyReplaced() throws {
        var data = AppData()
        data.extraFields[TaskWorkflow.storageKey] = .object(["version": .number(99)])
        #expect(throws: (any Error).self) { try TaskWorkflow.load(from: data) }
        #expect(data.extraFields[TaskWorkflow.storageKey] == .object(["version": .number(99)]))
    }
}
