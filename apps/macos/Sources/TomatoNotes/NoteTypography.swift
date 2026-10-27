import AppKit
import SwiftUI

enum NoteTypography {
    static let lineHeight: CGFloat = 28

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func editorFont(size: CGFloat = 16) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let font = NSFont(descriptor: descriptor, size: size) else { return base }
        return font
    }

    static func apply(to editor: NSTextView, text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: editorFont(), .paragraphStyle: paragraph, .foregroundColor: Theme.noteInk
        ]
        editor.font = editorFont()
        editor.defaultParagraphStyle = paragraph
        editor.string = text
        editor.textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: (text as NSString).length))
        // 已有文字与后续输入使用同一衬线字体，中文由系统匹配宋体。
        editor.typingAttributes = attributes
    }
}

final class LinedTextView: NSTextView {
    func ruleY(forLine line: Int) -> CGFloat {
        textContainerOrigin.y + CGFloat(line + 1) * NoteTypography.lineHeight - 0.5
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        Theme.noteRule.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5
        let pitch = NoteTypography.lineHeight
        let firstRule = ruleY(forLine: 0)
        let firstVisibleLine = max(0, Int(floor((rect.minY - firstRule) / pitch)))
        let left = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
        let right = bounds.width - left
        var y = ruleY(forLine: firstVisibleLine)
        // 横线使用与文本容器相同的起点和固定行高，滚动、换行后仍落在行尾。
        while y <= rect.maxY {
            path.move(to: NSPoint(x: left, y: y))
            path.line(to: NSPoint(x: max(left, right), y: y))
            y += pitch
        }
        path.stroke()
    }
}
