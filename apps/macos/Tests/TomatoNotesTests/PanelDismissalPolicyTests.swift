import Testing
@testable import TomatoNotes

struct PanelDismissalPolicyTests {
    private final class Window {
        weak var parent: Window?
        weak var sheetParent: Window?
    }

    private func shouldDismiss(_ clicked: Window?, panel: Window?, status: Window? = nil) -> Bool {
        PanelDismissalPolicy.shouldDismiss(clickedWindow: clicked, panel: panel, statusWindow: status) {
            [$0.parent, $0.sheetParent].compactMap { $0 }
        }
    }

    @Test func panelAndStatusItemClicksKeepPanelVisible() {
        let panel = Window(), status = Window()
        #expect(!shouldDismiss(panel, panel: panel, status: status))
        #expect(!shouldDismiss(status, panel: panel, status: status))
    }

    @Test func sheetAndItsNestedChildKeepPanelVisible() {
        let panel = Window(), sheet = Window(), child = Window(), nestedSheet = Window()
        sheet.sheetParent = panel
        child.parent = sheet
        nestedSheet.sheetParent = child
        #expect(!shouldDismiss(sheet, panel: panel))
        #expect(!shouldDismiss(child, panel: panel))
        #expect(!shouldDismiss(nestedSheet, panel: panel))
    }

    @Test func bothNativeParentRelationshipsAreFollowed() {
        let panel = Window(), unrelated = Window(), sheet = Window()
        sheet.parent = unrelated
        sheet.sheetParent = panel
        #expect(!shouldDismiss(sheet, panel: panel))
        sheet.parent = panel
        sheet.sheetParent = unrelated
        #expect(!shouldDismiss(sheet, panel: panel))
    }

    @Test func unrelatedWindowAndMissingEventWindowDismissPanel() {
        let panel = Window(), unrelated = Window(), unrelatedSheet = Window()
        unrelatedSheet.sheetParent = unrelated
        #expect(shouldDismiss(unrelated, panel: panel))
        #expect(shouldDismiss(unrelatedSheet, panel: panel))
        #expect(shouldDismiss(nil, panel: panel))
        #expect(!shouldDismiss(unrelated, panel: nil))
    }

    @Test func repeatedRelationshipsTerminateAndStillFindPanel() {
        let panel = Window(), first = Window(), second = Window()
        first.parent = second
        second.parent = first
        #expect(shouldDismiss(first, panel: panel))
        second.sheetParent = panel
        #expect(!shouldDismiss(first, panel: panel))
    }
}
