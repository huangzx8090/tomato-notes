import Foundation

public struct NoteTextExport: Sendable {
    public let suggestedFilename: String
    public let data: Data

    public init(note: StickyNote) {
        suggestedFilename = Self.filename(for: note.title)
        data = Data(note.text.utf8)
    }

    private static func filename(for title: String) -> String {
        let forbidden = CharacterSet.controlCharacters
            .union(.newlines)
            .union(CharacterSet(charactersIn: "/\\:"))
        let stem = String(title.unicodeScalars.filter { !forbidden.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 标题虽限制字符数，组合字符仍可能很长；按完整字符为扩展名预留字节空间。
        var boundedStem = ""
        var byteCount = 0
        for character in stem {
            let bytes = character.utf8.count
            guard bytes <= 240 - byteCount else { break }
            boundedStem.append(character)
            byteCount += bytes
        }
        boundedStem = boundedStem.trimmingCharacters(in: .whitespacesAndNewlines)
        if boundedStem.lowercased().hasSuffix(".txt") {
            boundedStem.removeLast(4)
        }
        boundedStem = boundedStem.trimmingCharacters(in: .whitespacesAndNewlines)
        if boundedStem.isEmpty || boundedStem == "." || boundedStem == ".." {
            boundedStem = "新便签"
        }
        return boundedStem + ".txt"
    }
}
