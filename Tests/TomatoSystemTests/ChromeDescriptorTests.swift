import Carbon
import Foundation
import Testing
import TomatoCore
@testable import TomatoSystem

struct ChromeDescriptorTests {
    @Test func decodesNativeRectangleAndAppleScriptListBounds() throws {
        let rectangle: [Int16] = [20, -1000, 620, 0]
        let data = rectangle.withUnsafeBytes { Data($0) }
        let descriptor = try #require(NSAppleEventDescriptor(descriptorType: 0x71647274, data: data))
        let bounds = try ChromeBrowser.decodeBounds(descriptor)
        #expect(bounds.x == -1000 && bounds.y == 20 && bounds.width == 1000 && bounds.height == 600)
        let list = NSAppleEventDescriptor.list()
        for (index, value) in [10, 20, 1010, 620].enumerated() { list.insert(.init(int32: Int32(value)), at: index + 1) }
        let other = try ChromeBrowser.decodeBounds(list)
        #expect(other.x == 10 && other.y == 20 && other.width == 1000 && other.height == 600)
    }
    @Test func missingAppleEventObjectConfirmsCloseButPermissionAndTimeoutDoNot() {
        for code in [-1728, -1719] {
            guard case .noPage = ChromeBrowser.failure(for: code) else { Issue.record("消失的对象应识别为不存在"); continue }
        }
        guard case .permission = ChromeBrowser.failure(for: -1743) else { Issue.record("权限错误应保留"); return }
        guard case .unavailable = ChromeBrowser.failure(for: -1712) else { Issue.record("超时不能当作关闭成功"); return }
    }
    @Test func captureRequiresOneMatchingTitleAndFrame() throws {
        let page = GuardPage(windowID: "1", tabID: "2", url: "https://example.test/", title: "微积分课程", isPrivate: false,
                             bounds: .init(x: 0, y: 20, width: 1000, height: 700))
        let frame = CGRect(x: 0, y: 20, width: 1000, height: 700)
        let course = FocusPageCapture.WindowCandidate(id: 10, frame: frame, title: "微积分课程 - Google Chrome")
        let other = FocusPageCapture.WindowCandidate(id: 11, frame: frame, title: "其他页面")
        #expect(try FocusPageCapture.matchedWindowID(for: page, candidates: [other, course]) == 10)
        for candidates in [[other], [course, course], [.init(id: 12, frame: frame, title: nil)],
                           [.init(id: 13, frame: frame.offsetBy(dx: 300, dy: 0), title: page.title)]] {
            #expect(throws: FocusCaptureError.self) { try FocusPageCapture.matchedWindowID(for: page, candidates: candidates) }
        }
    }
}
