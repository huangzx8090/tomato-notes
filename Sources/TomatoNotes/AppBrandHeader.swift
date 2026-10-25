import AppKit
import SwiftUI

struct AppBrandHeader: View {
    var icon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    var date = Date()

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "timer").font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                }
            }.frame(width: 40, height: 40).accessibilityHidden(true)
            Text("番茄小记").font(.system(size: 17, weight: .semibold))
            Spacer()
            Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 23).padding(.top, 18).padding(.bottom, 16)
    }
}
