import AppKit
import SwiftUI

struct AppBrandHeader: View {
    var brandMark: NSImage? = Bundle.main.url(forResource: "BrandMark", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    var date = Date()

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
            Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 23).padding(.top, 18).padding(.bottom, 16)
    }
}
