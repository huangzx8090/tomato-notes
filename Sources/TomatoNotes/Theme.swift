import AppKit
import SwiftUI

// 显式使用属性包装器，兼容未附带 SwiftUIMacros 的命令行 SDK。
typealias ViewState<Value> = SwiftUI.State<Value>

enum Theme {
    static let background = Color(hex: 0xF6F2EA)
    static let surface = Color(hex: 0xFFFCF6)
    static let primary = Color(hex: 0x302E2B)
    static let secondary = Color(hex: 0x706960)
    static let accent = Color(hex: 0xA84632)
    static let accentSoft = Color(hex: 0xF1DDD4)
    static let green = Color(hex: 0x52705D)
    static let greenSoft = Color(hex: 0xE8EEE6)
    static let border = Color(hex: 0xE3DBCF)
    static let notePaper = NSColor(srgbRed: 251 / 255, green: 241 / 255, blue: 211 / 255, alpha: 1)
    static let noteRule = NSColor(srgbRed: 216 / 255, green: 202 / 255, blue: 168 / 255, alpha: 0.7)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border.opacity(0.6), lineWidth: 0.6))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var green = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 43)
            .foregroundStyle(.white)
            .background((green ? Theme.green : Theme.accent).opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondary).padding(.horizontal, 11).padding(.vertical, 8)
            .background(configuration.isPressed ? Theme.border : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 0.7))
            .contentShape(Rectangle())
    }
}

final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

func durationLabel(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) 秒" }
    if total < 3600 { return "\(total / 60) 分 \(total % 60) 秒" }
    return "\(total / 3600) 小时 \(total % 3600 / 60) 分"
}
