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

    @Test func allWindowsLocksIDsBeforeReadingOnlyNormalTabs() throws {
        let fixture = ChromeTabsFixture([
            .init("incognito", mode: "incognito", tabs: [.init("secret")]),
            .init("first", tabs: [.init("1", url: "chrome://newtab/", title: String(repeating: "课", count: 601)),
                                  .init("2", url: "about:blank")]),
            .init("private", mode: "private", tabs: [.init("hidden")]),
            .init("second", tabs: [.init("1")])
        ])
        let pages = try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read)
        #expect(pages.map { "\($0.windowID):\($0.tabID)" } == ["first:1", "first:2", "second:1"])
        #expect(pages.map(\.url) == ["chrome://newtab/", "about:blank", "https://example.test/"])
        #expect(pages.first?.title.count == 600)
        #expect(pages.allSatisfy { !$0.isPrivate && $0.bounds == .init(x: 10, y: 20, width: 1000, height: 700) })
        #expect(fixture.requests == [
            .windowID(1), .windowID(2), .windowID(3), .windowID(4), .windowID(5),
            .mode("incognito"), .mode("first"), .bounds("first"), .tab("first", 1), .tab("first", 2),
            .tab("first", 3), .exists("first"), .mode("private"), .mode("second"), .bounds("second"),
            .tab("second", 1), .tab("second", 2), .exists("second")
        ])
    }

    @Test func allWindowsHasNoSixtyWindowOrTabLimit() throws {
        let windows = (1...65).map { window in
            ChromeTabsFixture.Window(String(window), tabs: (1...(window == 1 ? 75 : 1)).map { .init(String($0)) })
        }
        let fixture = ChromeTabsFixture(windows)
        let pages = try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read)
        #expect(pages.count == 139)
        #expect(pages.filter { $0.windowID == "1" }.count == 75)
        #expect(pages.last?.windowID == "65")
        #expect(fixture.requests.contains(.windowID(66)))
        #expect(fixture.requests.contains(.tab("1", 76)))
        #expect(fixture.requests.contains(.tab("65", 2)))
    }

    @Test func allWindowsAcceptsEmptyAndEntirelyPrivateCollections() throws {
        for modes: [String] in [[], ["incognito"], ["private"], ["incognito", "private"], ["normal", "incognito"]] {
            let fixture = ChromeTabsFixture(modes.enumerated().map { .init(String($0.offset), mode: $0.element) })
            #expect(try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read).isEmpty)
            for window in fixture.windows.values where window.mode != "normal" {
                #expect(!fixture.requests.contains(.bounds(window.id)))
                #expect(!fixture.requests.contains(.tab(window.id, 1)))
            }
        }
    }

    @Test(arguments: [-1743, -1712])
    func allWindowsPropagatesPermissionAndTimeoutAtEveryReadStage(code: Int) throws {
        let stages: [ChromeTabsFixture.Read] = [
            .windowID(1), .windowID(3), .mode("second"), .bounds("second"),
            .tab("second", 1), .tab("second", 2), .exists("second")
        ]
        for stage in stages {
            let fixture = ChromeTabsFixture([.init("first", tabs: [.init("1")]), .init("second", tabs: [.init("2")])])
            fixture.intercept = { request in
                if request == stage { throw ChromeBrowser.failure(for: code) }
                return nil
            }
            do {
                _ = try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read)
                Issue.record("权限或超时错误不能返回部分标签：\(stage)")
            } catch {
                if code == -1743 {
                    guard case ChromeBrowserError.permission = error else { Issue.record("权限错误必须向上传递"); continue }
                } else {
                    guard case ChromeBrowserError.unavailable = error else { Issue.record("超时必须向上传递"); continue }
                }
            }
            #expect(fixture.requests.last == stage)
        }
    }

    @Test(arguments: [-1728, -1719])
    func allWindowsSkipsDisappearedWindowsWithoutLosingLaterWindows(code: Int) throws {
        let stages: [ChromeTabsFixture.Read] = [.mode("first"), .bounds("first"), .tab("first", 2), .exists("first")]
        for stage in stages {
            let fixture = ChromeTabsFixture([.init("first", tabs: [.init("1")]), .init("second", tabs: [.init("2")])])
            fixture.intercept = { [unowned fixture] request in
                if request == stage {
                    fixture.windows.removeValue(forKey: "first")
                    throw ChromeBrowser.failure(for: code)
                }
                return nil
            }
            let pages = try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read)
            #expect(pages.map(\.windowID) == ["second"])
            #expect(pages.map(\.tabID) == ["2"])
        }
    }

    @Test func allWindowsDeduplicatesIDsButPreservesDistinctTabsWithTheSameURL() throws {
        let fixture = ChromeTabsFixture([
            .init("first", tabs: [.init("1"), .init("1"), .init("2")]),
            .init("second", tabs: [.init("1")])
        ], indices: ["first", "first", "second"])
        let pages = try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read)
        #expect(pages.map { "\($0.windowID):\($0.tabID)" } == ["first:1", "first:2", "second:1"])
        #expect(pages.allSatisfy { $0.url == "https://example.test/" })
        #expect(fixture.requests.filter { $0 == .mode("first") }.count == 1)
        #expect(fixture.requests.contains(.tab("first", 4)))
    }

    @Test func allWindowsRejectsMalformedRepliesInsteadOfReturningPartialPages() throws {
        let missingID = ChromeTabsFixture.tabProperties(.init(""))
        let missingURL = NSAppleEventDescriptor.record()
        missingURL.setDescriptor(.init(string: "2"), forKeyword: ChromeTabsFixture.code("ID  "))
        missingURL.setDescriptor(.init(string: "课程"), forKeyword: ChromeTabsFixture.code("pnam"))
        let missingTitle = NSAppleEventDescriptor.record()
        missingTitle.setDescriptor(.init(string: "2"), forKeyword: ChromeTabsFixture.code("ID  "))
        missingTitle.setDescriptor(.init(string: "https://example.test/"), forKeyword: ChromeTabsFixture.code("URL "))
        let replies: [(ChromeTabsFixture.Read, NSAppleEventDescriptor)] = [
            (.windowID(2), .init(string: "")), (.windowID(2), .null()),
            (.mode("second"), .null()), (.mode("second"), .init(string: "unknown")),
            (.bounds("second"), .null()), (.tab("second", 1), missingID),
            (.tab("second", 1), missingURL), (.tab("second", 1), missingTitle),
            (.exists("second"), .init(string: "different"))
        ]
        for (stage, reply) in replies {
            let fixture = ChromeTabsFixture([.init("first", tabs: [.init("1")]), .init("second", tabs: [.init("2")])])
            fixture.intercept = { $0 == stage ? reply : nil }
            do {
                _ = try ChromeBrowser().enumerateAllWindowTabs(read: fixture.read)
                Issue.record("格式错误不能被当作索引结束：\(stage)")
            } catch {
                guard case ChromeBrowserError.unavailable = error else { Issue.record("格式错误应报告不可用"); continue }
            }
        }
    }

    @Test func allWindowsChecksCancellationBeforeAndAfterReadsIncludingNoPage() async throws {
        let stages: [ChromeTabsFixture.Read?] = [nil, .windowID(1), .windowID(2), .mode("first"),
                                               .bounds("first"), .tab("first", 1), .tab("first", 2), .exists("first")]
        for stage in stages {
            let fixture = ChromeTabsFixture([.init("first", tabs: [.init("1")])])
            let task = Task { () throws -> [GuardPage] in
                if stage == nil { withUnsafeCurrentTask { $0?.cancel() } }
                return try ChromeBrowser().enumerateAllWindowTabs { reference in
                    let result = Result { try fixture.read(reference) }
                    if fixture.requests.last == stage { withUnsafeCurrentTask { $0?.cancel() } }
                    return try result.get()
                }
            }
            let result = await task.result
            #expect(throws: CancellationError.self) { try result.get() }
            if let stage { #expect(fixture.requests.last == stage) }
            else { #expect(fixture.requests.isEmpty) }
        }
    }
}

private final class ChromeTabsFixture {
    enum Read: Equatable, Sendable {
        case windowID(Int32), mode(String), bounds(String), tab(String, Int32), exists(String)
    }
    struct Tab {
        var id: String
        var url: String
        var title: String
        init(_ id: String, url: String = "https://example.test/", title: String = "课程") {
            self.id = id; self.url = url; self.title = title
        }
    }
    struct Window {
        var id: String
        var mode: String
        var tabs: [Tab]
        init(_ id: String, mode: String = "normal", tabs: [Tab] = []) {
            self.id = id; self.mode = mode; self.tabs = tabs
        }
    }
    let indices: [String]
    var windows: [String: Window]
    var requests: [Read] = []
    var intercept: ((Read) throws -> NSAppleEventDescriptor?)?

    init(_ windows: [Window], indices: [String]? = nil) {
        self.indices = indices ?? windows.map(\.id)
        self.windows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    }

    func read(_ reference: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let request = try decode(reference)
        requests.append(request)
        if let reply = try intercept?(request) { return reply }
        if case let .windowID(index) = request {
            guard index > 0, Int(index) <= indices.count else { throw ChromeBrowserError.noPage }
            return .init(string: indices[Int(index) - 1])
        }
        let id: String
        switch request {
        case let .mode(value), let .bounds(value), let .tab(value, _), let .exists(value): id = value
        case .windowID: throw ChromeBrowserError.unavailable
        }
        guard let window = windows[id] else { throw ChromeBrowserError.noPage }
        switch request {
        case .mode: return .init(string: window.mode)
        case .bounds:
            let bounds = NSAppleEventDescriptor.list()
            for (index, value) in [10, 20, 1010, 720].enumerated() { bounds.insert(.init(int32: Int32(value)), at: index + 1) }
            return bounds
        case let .tab(_, index):
            #expect(window.mode == "normal")
            #expect(requests.contains(.mode(id)))
            guard index > 0, Int(index) <= window.tabs.count else { throw ChromeBrowserError.noPage }
            return Self.tabProperties(window.tabs[Int(index) - 1])
        case .exists: return .init(string: id)
        case .windowID: throw ChromeBrowserError.unavailable
        }
    }

    // 解码真实的对象描述符；若实现改成窗口 pALL 或无痕 tabs，测试会在此失败。
    private func decode(_ reference: NSAppleEventDescriptor) throws -> Read {
        #expect(reference.descriptorType == Self.code("obj "))
        #expect(reference.forKeyword(Self.code("want"))?.typeCodeValue == Self.code("prop"))
        #expect(reference.forKeyword(Self.code("form"))?.enumCodeValue == Self.code("prop"))
        let property = try #require(reference.forKeyword(Self.code("seld"))).typeCodeValue
        let container = try #require(reference.forKeyword(Self.code("from")))
        let kind = try #require(container.forKeyword(Self.code("want"))).typeCodeValue
        let form = try #require(container.forKeyword(Self.code("form"))).enumCodeValue
        let selection = try #require(container.forKeyword(Self.code("seld")))
        if kind == Self.code("cwin") {
            if form == Self.code("indx"), property == Self.code("ID  ") { return .windowID(selection.int32Value) }
            #expect(form == Self.code("ID  "))
            let id = try #require(selection.stringValue)
            switch property {
            case Self.code("mode"): return .mode(id)
            case Self.code("pbnd"): return .bounds(id)
            case Self.code("ID  "): return .exists(id)
            default: Issue.record("禁止读取窗口 pALL 或其他属性"); throw ChromeBrowserError.unavailable
            }
        }
        #expect(kind == Self.code("CrTb"))
        #expect(form == Self.code("indx"))
        #expect(property == Self.code("pALL"))
        let window = try #require(container.forKeyword(Self.code("from")))
        #expect(window.forKeyword(Self.code("want"))?.typeCodeValue == Self.code("cwin"))
        #expect(window.forKeyword(Self.code("form"))?.enumCodeValue == Self.code("ID  "))
        let id = try #require(window.forKeyword(Self.code("seld"))?.stringValue)
        return .tab(id, selection.int32Value)
    }

    static func tabProperties(_ tab: Tab) -> NSAppleEventDescriptor {
        let properties = NSAppleEventDescriptor.record()
        properties.setDescriptor(.init(string: tab.id), forKeyword: code("ID  "))
        properties.setDescriptor(.init(string: tab.url), forKeyword: code("URL "))
        properties.setDescriptor(.init(string: tab.title), forKeyword: code("pnam"))
        return properties
    }
    static func code(_ value: String) -> UInt32 { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
}
