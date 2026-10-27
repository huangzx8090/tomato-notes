import SwiftUI

enum PanelTab: String, CaseIterable {
    case focus = "专注", todos = "待办", today = "今日", notes = "便签", ranking = "排行", settings = "设置"

    static let primaryTabs: [PanelTab] = [.focus, .todos, .today, .notes, .ranking]

    var symbol: String {
        switch self {
        case .focus: "timer"
        case .todos: "checklist"
        case .today: "sun.max"
        case .notes: "note.text"
        case .ranking: "chart.bar.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct PanelNavigation: View {
    @Binding var selection: PanelTab
    @Environment(\.glassControlsEnabled) private var glassControlsEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var capsulePosition: CGFloat = 0
    @ViewState private var capsuleOrigin: CGFloat = 0

    private var usesGlass: Bool { glassControlsEnabled && !reduceTransparency }
    private var selectedIndex: CGFloat? { PanelTab.primaryTabs.firstIndex(of: selection).map(CGFloat.init) }

    var body: some View {
        ZStack {
            track
            selectionSurface.padding(4).opacity(selectedIndex == nil ? 0 : 1)
        }
        .allowsHitTesting(false)
        // 标签放在整个玻璃容器外，避免被材质采样、折射或模糊。
        .overlay { tabs.padding(4) }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("页面切换")
        .onAppear { moveCapsule(animated: false) }
        .onChange(of: selection) { _, _ in moveCapsule(animated: true) }
    }

    @ViewBuilder private var track: some View {
        if usesGlass, #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(Theme.surface.opacity(0.22)), in: .capsule)
        } else if usesGlass {
            Capsule().fill(.ultraThinMaterial)
        } else {
            Capsule().fill(Theme.border.opacity(0.42))
        }
    }

    @ViewBuilder private var selectionSurface: some View {
        let shape = FlowingTabShape(position: capsulePosition, origin: capsuleOrigin, target: selectedIndex ?? capsulePosition)
        if usesGlass, #available(macOS 26.0, *) {
            GlassEffectContainer {
                Color.clear.glassEffect(.regular.tint(Theme.surface.opacity(0.55)).interactive(), in: shape)
            }
        } else if usesGlass {
            shape.fill(.ultraThinMaterial).overlay(shape.stroke(Theme.surface.opacity(0.8), lineWidth: 0.7))
        } else {
            shape.fill(Theme.surface).shadow(color: Theme.primary.opacity(0.05), radius: 3, y: 1)
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.primaryTabs, id: \.self) { item in
                Button { selection = item } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .medium))
                        Text(item.rawValue).font(.system(size: 12, weight: .semibold)).fixedSize()
                    }
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .foregroundStyle(selection == item ? Theme.accent : Theme.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
                .accessibilityIdentifier("navigation.\(item.rawValue)")
            }
        }
    }

    private func moveCapsule(animated: Bool) {
        guard let selectedIndex else { return }
        capsuleOrigin = capsulePosition
        withAnimation(animated && !reduceMotion ? .spring(response: 0.52, dampingFraction: 0.84) : nil) {
            capsulePosition = selectedIndex
        }
    }
}

private struct FlowingTabShape: Shape {
    var position: CGFloat
    let origin: CGFloat
    let target: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let count = CGFloat(PanelTab.primaryTabs.count)
        let gap: CGFloat = 4
        let slot = max(0, (rect.width - gap * (count - 1)) / count)
        let distance = target - origin
        let progress = distance == 0 ? 1 : min(1, max(0, (position - origin) / distance))
        // 途中轻轻拉长、到位时收圆；位置连续插值，快速切换时也不会重建选中层。
        let stretch = sin(progress * .pi) * min(30, abs(distance) * slot * 0.28)
        let width = slot + stretch
        let x = min(max(0, position * (slot + gap) - stretch / 2), max(0, rect.width - width))
        if NavigationTrace.enabled {
            let frame = String(format: "navigation-frame position=%.4f width=%.2f\n", Double(position), Double(width))
            FileHandle.standardError.write(Data(frame.utf8))
        }
        return Path(roundedRect: CGRect(x: rect.minX + x, y: rect.minY, width: width, height: rect.height),
                    cornerRadius: rect.height / 2)
    }
}

private enum NavigationTrace {
    static let enabled = Bundle.main.bundleIdentifier?.hasSuffix(".QA") == true &&
        ProcessInfo.processInfo.arguments.contains("--ui-trace-navigation")
}
