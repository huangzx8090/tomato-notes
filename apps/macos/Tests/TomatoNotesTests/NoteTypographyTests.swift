import AppKit
import Testing
@testable import TomatoNotes

struct NoteTypographyTests {
    @MainActor @Test func rulesFollowTextFragmentsAfterWrappingAndNewlines() {
        let editor = LinedTextView(frame: NSRect(x: 0, y: 0, width: 180, height: 300))
        editor.textContainerInset = NSSize(width: 15, height: 7)
        editor.isRichText = false
        NoteTypography.apply(to: editor, text: "第一行中文和 English。\n第二行足够长，应该自动换成多行文字，然后继续。")

        guard let manager = editor.layoutManager, let container = editor.textContainer else {
            Issue.record("编辑器缺少文本布局组件")
            return
        }
        manager.ensureLayout(for: container)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) {
            rect, _, _, glyphRange, _ in
            let ruleY = editor.ruleY(forLine: count)
            let baselineY = editor.textContainerOrigin.y + rect.minY + manager.location(forGlyphAt: glyphRange.location).y
            #expect(abs(ruleY - (editor.textContainerOrigin.y + rect.maxY - 0.5)) < 0.01)
            #expect(ruleY > baselineY)
            count += 1
        }
        #expect(count >= 3)
    }
}
