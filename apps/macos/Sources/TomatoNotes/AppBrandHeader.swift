import AppKit
import SwiftUI

struct AppBrandHeader: View {
    var brandMark: NSImage? = Bundle.main.url(forResource: "BrandMark", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    var date = Date()
    var settingsSelected = false
    var openSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let brandMark {
                    Image(nsImage: brandMark).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "timer").font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                }
            }.frame(width: 40, height: 40).accessibilityHidden(true)
            Text("番茄小记").font(.system(size: 17, weight: .semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 3) {
                    Text("今天 ·")
                    Text(date, format: .dateTime.weekday(.abbreviated))
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                Text(date, format: .dateTime.month().day())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primary)
            }
            .accessibilityElement(children: .combine)
            if let openSettings {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(settingsSelected ? Theme.accent : Theme.secondary)
                        .frame(width: 34, height: 34)
                        .background(settingsSelected ? Theme.accentSoft : Theme.surface.opacity(0.7), in: Circle())
                        .overlay(Circle().stroke(Theme.border.opacity(0.65), lineWidth: 0.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("设置")
                .accessibilityLabel("设置")
                .accessibilityAddTraits(settingsSelected ? .isSelected : [])
                .accessibilityIdentifier("navigation.设置")
            }
        }
        .padding(.horizontal, 23).padding(.top, 18).padding(.bottom, 16)
    }
}
