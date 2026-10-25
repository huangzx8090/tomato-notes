import Foundation
import Testing
import TomatoCore

struct NoteTextExportTests {
    @Test(arguments: [
        "",
        " \t  \r\n\n ",
        " \t中文标题  \r\n第二行\n\nemoji 👍🏽 和 e\u{0301}\r尾行\t \n",
        "原文\u{0000}中的控制符\u{2028}保留\u{2029}",
        "\u{FEFF}原文已有的字符也保留"
    ])
    func dataPreservesEveryUTF8Byte(text: String) {
        let note = makeNote(text)
        let export = NoteTextExport(note: note)

        #expect(export.data == Data(text.utf8))
        #expect(String(decoding: export.data, as: UTF8.self) == text)
        #expect(note.text == text)
    }

    @Test func doesNotAddBOMTitleDateOrNewline() {
        let export = NoteTextExport(note: makeNote("便签正文"))

        #expect(Array(export.data) == Array("便签正文".utf8))
        #expect(!export.data.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test func filenameUsesExistingTitleAndKeepsChinese() {
        let note = makeNote("  中文便签  \n下一行不作为文件名")
        let export = NoteTextExport(note: note)

        #expect(export.suggestedFilename == note.title + ".txt")
        #expect(export.suggestedFilename == "中文便签.txt")
    }

    @Test func removesSeparatorsColonsControlCharactersAndLineBreaks() {
        let note = makeNote("中/文\\便:签\u{0000}\u{0007}\u{000B}\u{001B}\u{007F}\u{0085}\u{2028}\u{2029}名\n正文")
        let export = NoteTextExport(note: note)
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
            .union(CharacterSet(charactersIn: "/\\:"))

        #expect(export.suggestedFilename == "中文便签名.txt")
        #expect(export.suggestedFilename.unicodeScalars.allSatisfy { !forbidden.contains($0) })
        #expect(export.data == Data(note.text.utf8))
    }

    @Test(arguments: ["", " \t \n正文", ".", "..", "/\\:", ": \t/\\", "\u{0000}\u{0007}", ".txt", "..txt", "...txt"])
    func unusableNamesHaveSafeFallback(text: String) {
        #expect(NoteTextExport(note: makeNote(text)).suggestedFilename == "新便签.txt")
    }

    @Test(arguments: ["中文.txt", "中文.TXT", "中文.TxT", "  中文.txt  ", "中/文.txt"])
    func existingTextExtensionIsNotDuplicated(text: String) {
        #expect(NoteTextExport(note: makeNote(text)).suggestedFilename == "中文.txt")
    }

    @Test func otherExtensionsRemainPartOfTitle() {
        #expect(NoteTextExport(note: makeNote("计划.md")).suggestedFilename == "计划.md.txt")
    }

    @Test func longTextUsesTitleLimitWithoutTruncatingBody() {
        let text = String(repeating: "中文👍🏽e\u{0301}", count: 2_000) + "\n  完整末行 \n"
        let note = makeNote(text)
        let export = NoteTextExport(note: note)

        #expect(note.title.count == 24)
        #expect(export.suggestedFilename == note.title + ".txt")
        #expect(export.data == Data(text.utf8))
    }

    @Test func longUnicodeFilenameTruncatesOnlyBetweenCompleteCharacters() {
        let character = "中" + String(repeating: "\u{0301}", count: 20)
        let note = makeNote(String(repeating: character, count: 40))
        let export = NoteTextExport(note: note)
        let stem = String(export.suggestedFilename.dropLast(4))

        #expect(export.suggestedFilename.hasSuffix(".txt"))
        #expect(export.suggestedFilename.utf8.count <= 255)
        #expect(!stem.isEmpty && stem.count < note.title.count)
        #expect(note.title.hasPrefix(stem))
        #expect(stem.allSatisfy { String($0) == character })
        #expect(export.data == Data(note.text.utf8))
    }

    @Test func oversizedSingleCharacterUsesFallbackWithoutSplittingIt() {
        let text = "中" + String(repeating: "\u{0301}", count: 300)
        let export = NoteTextExport(note: makeNote(text))

        #expect(export.suggestedFilename == "新便签.txt")
        #expect(export.data == Data(text.utf8))
    }

    @Test func textExtensionExposedByTruncationIsNotDuplicated() {
        let first = "中" + String(repeating: "\u{0301}", count: 100)
        let last = "文" + String(repeating: "\u{0301}", count: 30)
        let export = NoteTextExport(note: makeNote(first + ".txt" + last))

        #expect(export.suggestedFilename == first + ".txt")
    }

    @Test(arguments: ["", " \t中文便签 \r\n\n完整正文 👍🏽e\u{0301}\u{0000}\t \n", "\u{FEFF}原文已有的字符也保留"])
    func atomicWritePreservesOriginalBytesInIsolatedDirectory(text: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTextExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let export = NoteTextExport(note: makeNote(text))
        let url = root.appendingPathComponent(export.suggestedFilename)
        try Data("旧文件内容".utf8).write(to: url)
        try export.data.write(to: url, options: .atomic)
        let saved = try Data(contentsOf: url)

        #expect(saved == Data(text.utf8))
        #expect(String(decoding: saved, as: UTF8.self) == text)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [export.suggestedFilename])
    }

    private func makeNote(_ text: String) -> StickyNote {
        var note = StickyNote(at: Date(timeIntervalSince1970: 0))
        note.text = text
        return note
    }
}
