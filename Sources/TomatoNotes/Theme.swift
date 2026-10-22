import AppKit
import SwiftUI
import TomatoCore

// 显式使用属性包装器，兼容未附带 SwiftUIMacros 的命令行 SDK。
typealias ViewState<Value> = SwiftUI.State<Value>

enum Theme {
    static let backgroundNS = adaptive("background", light: 0xF6F2EA, dark: 0x211E1B)
    static let background = Color(nsColor: backgroundNS)
    static let surface = color("surface", light: 0xFFFCF6, dark: 0x2D2824)
    static let primary = color("primary", light: 0x302E2B, dark: 0xF0E6D6)
    static let secondary = color("secondary", light: 0x706960, dark: 0xBCAD9D)
    static let accent = color("accent", light: 0xA84632, dark: 0xEEA48B)
    static let accentFill = color("accentFill", light: 0xA84632, dark: 0x98402D)
    static let accentSoft = color("accentSoft", light: 0xF1DDD4, dark: 0x4A3028)
    static let green = color("green", light: 0x52705D, dark: 0xABC7AC)
    static let greenFill = color("greenFill", light: 0x52705D, dark: 0x405D47)
    static let greenSoft = color("greenSoft", light: 0xE8EEE6, dark: 0x2E3C30)
    static let border = color("border", light: 0xE3DBCF, dark: 0x554A40)
    static let notePaper = adaptive("notePaper", light: 0xFBF1D3, dark: 0x342E22)
    static let noteInk = adaptive("noteInk", light: 0x302E2B, dark: 0xF2E5C3)
    static let noteRule = adaptive("noteRule", light: 0xD8CAA8, dark: 0x75633F).withAlphaComponent(0.7)
    static let noteAction = adaptive("noteAction", light: 0x7A4D2E, dark: 0xDBC395)
    static let dialRimLight = color("dialRimLight", light: 0xFFFFFF, dark: 0x65594D)
    static let dialRimShadow = color("dialRimShadow", light: 0xD7D0C5, dark: 0x302A25)
    static let dialRimEnd = color("dialRimEnd", light: 0xF9F5ED, dark: 0x4A4037)
    static let dialFaceLight = color("dialFaceLight", light: 0xFFFEFA, dark: 0x50453A)
    static let dialFaceShadow = color("dialFaceShadow", light: 0xEEE7DB, dark: 0x342D26)
    static let dialHighlight = color("dialHighlight", light: 0xFFFFFF, dark: 0x887661)
    static let dialShadow = color("dialShadow", light: 0xB1A391, dark: 0x000000)

    private static func color(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: adaptive(name, light: light, dark: dark))
    }
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("TomatoNotes." + name)) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                           green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255, alpha: 1)
        }
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
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
            .modifier(GlassControlSurface(cornerRadius: 12, tint: green ? Theme.greenFill : Theme.accentFill,
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
