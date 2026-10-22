import Foundation
import Testing
@testable import TomatoCore

struct NoteLibraryTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    @Test func todayUsesCreationDayEvenAfterEditingOrReopeningAnOldNote() {
        var yesterday = StickyNote(at: date("2026-10-21T15:59:59Z"), calendar: calendar)
        yesterday.updatedAt = date("2026-10-22T02:00:00Z")
        yesterday.isOpen = true
        let today = StickyNote(at: date("2026-10-21T16:00:00Z"), calendar: calendar)
        let notes = [yesterday, today]
        #expect(NoteLibrary.notes(on: "2026-10-22", in: notes, calendar: calendar).map(\.id) == [today.id])
        #expect(NoteLibrary.history(excluding: "2026-10-22", in: notes, calendar: calendar).first?.notes.first?.id == yesterday.id)
    }

    @Test func legacyNotesDecodeAndUseCreationDateWithoutNewMetadata() throws {
        let original = StickyNote(at: date("2026-10-21T03:00:00Z"), calendar: calendar)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "localDay")
        json.removeValue(forKey: "continuedFromNoteID")
        let restored = try JSONDecoder().decode(StickyNote.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.localDay == nil)
        #expect(restored.dayKey(calendar: calendar) == "2026-10-21")
        #expect(restored.id == original.id)
    }

    @Test func continueCopiesTextAndSizeWhilePreservingOriginalAndResettingWindowPosition() throws {
        var original = StickyNote(at: date("2026-10-21T03:00:00Z"), calendar: calendar)
        original.text = "第一行想法\n明天继续写"
        original.isOpen = false
        original.x = 133; original.y = 244; original.width = 420; original.height = 380
        var notes = [original]
        let now = date("2026-10-22T03:00:00Z")
        let id = try #require(NoteLibrary.continueNote(original.id, in: &notes, at: now, calendar: calendar))
        let copy = try #require(notes.first { $0.id == id })
        #expect(id != original.id)
        #expect(copy.text == original.text)
        #expect(copy.width == 420 && copy.height == 380)
        #expect(copy.x == nil && copy.y == nil && copy.isOpen)
        #expect(copy.createdAt == now && copy.updatedAt == now)
        #expect(copy.localDay == "2026-10-22" && copy.continuedFromNoteID == original.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(notes[0]) == encoder.encode(original))
    }

    @Test func repeatedContinueDoesNotOverwriteEditsAndNextDayCreatesANewCopy() throws {
        let original = StickyNote(at: date("2026-10-21T03:00:00Z"), calendar: calendar)
        var notes = [original]
        let now = date("2026-10-22T03:00:00Z")
        let first = try #require(NoteLibrary.continueNote(original.id, in: &notes, at: now, calendar: calendar))
        notes[1].text = "今天补写的内容"
        notes[1].isOpen = false
        let second = NoteLibrary.continueNote(original.id, in: &notes, at: now.addingTimeInterval(1), calendar: calendar)
        #expect(first == second && notes.count == 2)
        #expect(notes[1].text == "今天补写的内容")
        let tomorrow = NoteLibrary.continueNote(original.id, in: &notes, at: now.addingTimeInterval(86400), calendar: calendar)
        #expect(tomorrow != first && notes.count == 3)
        #expect(notes[2].localDay == "2026-10-23")
    }

    @Test func currentOrMissingNoteCannotCreateUnnecessaryCopies() {
        let now = date("2026-10-22T03:00:00Z")
        let original = StickyNote(at: now, calendar: calendar)
        var notes = [original]
        #expect(NoteLibrary.continueNote(original.id, in: &notes, at: now, calendar: calendar) == original.id)
        #expect(NoteLibrary.continueNote(UUID(), in: &notes, at: now, calendar: calendar) == nil)
        #expect(notes.count == 1)
    }

    @Test func historyGroupsAndSortsWithoutLosingNotesWhenClockChanges() {
        var recent = StickyNote(at: date("2026-10-21T03:00:00Z"), calendar: calendar)
        recent.updatedAt = date("2026-10-21T05:00:00Z")
        let earlier = StickyNote(at: date("2026-10-21T02:00:00Z"), calendar: calendar)
        let old = StickyNote(at: date("2026-10-20T02:00:00Z"), calendar: calendar)
        let future = StickyNote(at: date("2026-10-23T02:00:00Z"), calendar: calendar)
        let groups = NoteLibrary.history(excluding: "2026-10-22", in: [old, earlier, future, recent], calendar: calendar)
        #expect(groups.map(\.day) == ["2026-10-23", "2026-10-21", "2026-10-20"])
        #expect(groups[1].notes.map(\.id) == [recent.id, earlier.id])
        #expect(groups.flatMap(\.notes).count == 4)
    }

    @Test func newDateAndContinuationMetadataSurviveRepositoryRoundTrip() throws {
        var note = StickyNote(at: date("2026-10-22T03:00:00Z"), calendar: calendar)
        note.continuedFromNoteID = UUID()
        var data = AppData()
        data.notes = [note]
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        #expect(restored.notes[0].localDay == "2026-10-22")
        #expect(restored.notes[0].continuedFromNoteID == note.continuedFromNoteID)
        var abroad = Calendar(identifier: .gregorian)
        abroad.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(restored.notes[0].dayKey(calendar: abroad) == "2026-10-22")
    }
}
