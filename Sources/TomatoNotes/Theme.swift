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

private struct GlassControlsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var glassControlsEnabled: Bool {
        get { self[GlassControlsEnabledKey.self] }
        set { self[GlassControlsEnabledKey.self] = newValue }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var green = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 43)
            .foregroundStyle(.white)
            .modifier(GlassControlSurface(cornerRadius: 12, tint: green ? Theme.green : Theme.accent,
                                         prominent: true, pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.primary).padding(.horizontal, 11).padding(.vertical, 8)
            .modifier(GlassControlSurface(cornerRadius: 9, tint: Theme.surface.opacity(0.35),
                                         pressed: configuration.isPressed))
            .contentShape(Rectangle())
    }
}

struct GlassControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    var tint: Color = Theme.surface.opacity(0.3)
    var prominent = false
    var pressed = false
    @Environment(\.glassControlsEnabled) private var glassControlsEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if !glassControlsEnabled || reduceTransparency {
            content.background(prominent ? tint : Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(prominent ? .clear : Theme.border, lineWidth: 0.7))
                .opacity(pressed ? 0.8 : 1)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(pressed ? 0.84 : 1)
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .background(prominent ? tint : Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(pressed ? 0.8 : 1)
        }
    }
}

@MainActor
func makePaperHostingView<Content: View>(rootView: Content, size: NSSize, cornerRadius: CGFloat = 16) -> NSView {
    let frame = NSRect(origin: .zero, size: size)
    let hosting = InteractiveHostingView(rootView: rootView)
    hosting.frame = frame
    hosting.autoresizingMask = [.width, .height]
    hosting.wantsLayer = true
    hosting.layer?.cornerRadius = cornerRadius
    hosting.layer?.masksToBounds = true
    return hosting
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
