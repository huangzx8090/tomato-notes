import AppKit

enum PanelDismissalPolicy {
    @MainActor
    static func shouldDismiss(clickedWindow: NSWindow?, panel: NSWindow?, statusWindow: NSWindow?) -> Bool {
        shouldDismiss(clickedWindow: clickedWindow, panel: panel, statusWindow: statusWindow) {
            [$0.parent, $0.sheetParent].compactMap { $0 }
        }
    }

    static func shouldDismiss<Window: AnyObject>(
        clickedWindow: Window?, panel: Window?, statusWindow: Window?,
        relatedWindows: (Window) -> [Window]
    ) -> Bool {
        guard let panel else { return false }
        guard let clickedWindow else { return true }
        var pending = [clickedWindow]
        var visited: Set<ObjectIdentifier> = []
        while let window = pending.popLast() {
            guard visited.insert(ObjectIdentifier(window)).inserted else { continue }
            if window === panel || window === statusWindow { return false }
            // SwiftUI sheet 是独立窗口；其原生子窗口也属于面板内操作。
            pending.append(contentsOf: relatedWindows(window))
        }
        return true
    }
}
