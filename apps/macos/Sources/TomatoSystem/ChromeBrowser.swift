import AppKit
import Carbon
import Foundation
import TomatoCore

public enum ChromeBrowserError: LocalizedError {
    case notRunning, permission, noPage, privateWindow, changed, unavailable, closeUnconfirmed
    public var errorDescription: String? {
        switch self {
        case .notRunning: "请先打开 Chrome 的普通浏览窗口。"
        case .permission: "尚未允许控制 Chrome，请在系统设置的“隐私与安全性 → 自动化”中允许番茄小记。"
        case .noPage: "当前没有可读取的普通 Chrome 标签页。"
        case .privateWindow: "无痕窗口仅提醒，不读取页面、截图或关闭标签。"
        case .changed: "页面已经切换，本次判断已取消。"
        case .unavailable: "Chrome 暂时无法响应，本次只提醒，不关闭页面。"
        case .closeUnconfirmed: "未能确认 Chrome 是否完成关闭，请核对当前页面；不会继续强制操作。"
        }
    }
}

/// 只使用 Chrome 自带的 Apple Events 接口；不注入网页脚本，也不读取正文或浏览历史。
public actor ChromeBrowser {
    public init() {}
    private static let bundleID = "com.google.Chrome"

    public func requestAccess(askUserIfNeeded: Bool = true) throws {
        guard isRunning else { throw ChromeBrowserError.notRunning }
        let target = targetDescriptor()
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, cc("core"), cc("getd"), askUserIfNeeded)
        guard status == noErr else { throw ChromeBrowserError.permission }
    }

    public func frontPage(requireFrontmost: Bool = true) throws -> GuardPage {
        guard isRunning else { throw ChromeBrowserError.notRunning }
        if requireFrontmost { try requireChromeForeground() }
        let (window, windowProperties, windowID) = try ordinaryFrontWindow()
        let tabProperties = try get(property("pALL", of: property("acTa", of: window)))
        let page = try page(from: tabProperties, window: windowProperties)
        guard try frontWindowID() == windowID else { throw ChromeBrowserError.changed }
        if requireFrontmost { try requireChromeForeground() }
        return page
    }

    public func currentWindowTabs() throws -> [GuardPage] {
        guard isRunning else { throw ChromeBrowserError.notRunning }
        let (window, windowProperties, _) = try ordinaryFrontWindow()
        // Chrome 不支持在单个事件里读取 every tab 的属性（会返回 -1700），必须按索引逐个取；
        // 越界时 Chrome 返回 -1719，正好当作遍历结束。
        var pages: [GuardPage] = []
        for rawIndex in 1...60 {
            let index = Int32(rawIndex)
            let tab = object("CrTb", form: "indx", value: .init(int32: index), container: window)
            do {
                let properties = try get(property("pALL", of: tab))
                pages.append(try page(from: properties, window: windowProperties))
            } catch ChromeBrowserError.noPage {
                break
            }
        }
        return pages
    }

    public func allWindowTabs() throws -> [GuardPage] {
        try Task.checkCancellation()
        guard isRunning else { throw ChromeBrowserError.notRunning }
        return try enumerateAllWindowTabs(read: { try get($0) })
    }

    // 注入只读事件，测试无需连接 Chrome 或请求自动化权限。
    nonisolated func enumerateAllWindowTabs(read: (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor) throws -> [GuardPage] {
        func checkedRead(_ reference: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
            try Task.checkCancellation()
            let result = Result { try read(reference) }
            try Task.checkCancellation()
            return try result.get()
        }
        func nextIndex(_ index: Int32) throws -> Int32 {
            guard index < .max else { throw ChromeBrowserError.unavailable }
            return index + 1
        }
        func string(_ descriptor: NSAppleEventDescriptor) throws -> String {
            guard let value = descriptor.stringValue, !value.isEmpty else { throw ChromeBrowserError.unavailable }
            return value
        }

        // 先收集 ID；读取标签期间窗口消失或重排，不会改变随后使用的窗口引用。
        var windowIDs: [String] = []
        var seenWindows: Set<String> = []
        var windowIndex: Int32 = 1
        while true {
            let window = object("cwin", form: "indx", value: .init(int32: windowIndex))
            let idDescriptor: NSAppleEventDescriptor
            do { idDescriptor = try checkedRead(property("ID  ", of: window)) }
            catch ChromeBrowserError.noPage { break }
            let id = try string(idDescriptor)
            if seenWindows.insert(id).inserted { windowIDs.append(id) }
            windowIndex = try nextIndex(windowIndex)
        }

        var pages: [GuardPage] = []
        for id in windowIDs {
            try Task.checkCancellation()
            let window = object("cwin", form: "ID  ", value: .init(string: id))
            do {
                // sdef 的 mode 在创建后不可变；必须先用 ID 检查，不能先读窗口 pALL 或 tabs。
                let mode = try string(checkedRead(property("mode", of: window)))
                if mode == "incognito" || mode == "private" { continue }
                guard mode == "normal" else { throw ChromeBrowserError.unavailable }
                let boundsDescriptor = try checkedRead(property("pbnd", of: window))
                let bounds: GuardPage.Bounds
                do { bounds = try Self.decodeBounds(boundsDescriptor) }
                catch ChromeBrowserError.noPage { throw ChromeBrowserError.unavailable }

                var windowPages: [GuardPage] = []
                var seenTabs: Set<String> = []
                var tabIndex: Int32 = 1
                while true {
                    let tab = object("CrTb", form: "indx", value: .init(int32: tabIndex), container: window)
                    let properties: NSAppleEventDescriptor
                    do { properties = try checkedRead(property("pALL", of: tab)) }
                    catch ChromeBrowserError.noPage { break }
                    // 只有事件返回 noPage 才代表索引结束；字段缺失不能伪装成完整快照。
                    guard let tabID = properties.forKeyword(cc("ID  "))?.stringValue, !tabID.isEmpty,
                          let url = properties.forKeyword(cc("URL "))?.stringValue,
                          let title = properties.forKeyword(cc("pnam"))?.stringValue else {
                        throw ChromeBrowserError.unavailable
                    }
                    if seenTabs.insert(tabID).inserted {
                        windowPages.append(GuardPage(windowID: id, tabID: tabID, url: url, title: String(title.prefix(600)),
                                                     isPrivate: false, bounds: bounds))
                    }
                    tabIndex = try nextIndex(tabIndex)
                }
                // noPage 也可能是整个窗口消失；确认窗口仍在，才保留该窗口已读的标签。
                guard try string(checkedRead(property("ID  ", of: window))) == id else {
                    throw ChromeBrowserError.unavailable
                }
                pages.append(contentsOf: windowPages)
            } catch ChromeBrowserError.noPage { continue }
        }
        try Task.checkCancellation()
        return pages
    }

    public func closeIfUnchanged(_ expected: GuardPage) throws -> Bool {
        let current = try frontPage()
        guard current.windowID == expected.windowID, current.tabID == expected.tabID,
              current.url == expected.url, current.title == expected.title, !current.isPrivate else {
            throw ChromeBrowserError.changed
        }
        let window = object("cwin", form: "ID  ", value: .init(string: expected.windowID))
        let tab = object("CrTb", form: "ID  ", value: .init(string: expected.tabID), container: window)
        try requireChromeForeground()
        do { _ = try send("clos", direct: tab) }
        catch { throw ChromeBrowserError.closeUnconfirmed }
        do {
            _ = try get(property("ID  ", of: tab))
            throw ChromeBrowserError.closeUnconfirmed
        } catch ChromeBrowserError.noPage { return true }
    }

    private var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }
    private func frontWindowID() throws -> String {
        let front = object("cwin", form: "indx", value: .init(int32: 1))
        guard let id = try get(property("ID  ", of: front)).stringValue, !id.isEmpty else { throw ChromeBrowserError.noPage }
        return id
    }
    private func ordinaryFrontWindow() throws -> (NSAppleEventDescriptor, NSAppleEventDescriptor, String) {
        // 先锁定窗口 ID，再读取模式；前台窗口切换不能把普通窗口检查套用到无痕窗口。
        let id = try frontWindowID()
        let window = object("cwin", form: "ID  ", value: .init(string: id))
        let mode = try get(property("mode", of: window)).stringValue
        guard mode == "normal" else { throw mode == "incognito" ? ChromeBrowserError.privateWindow : .noPage }
        let properties = try get(property("pALL", of: window))
        guard properties.forKeyword(cc("mode"))?.stringValue == "normal" else { throw ChromeBrowserError.privateWindow }
        return (window, properties, id)
    }
    private func requireChromeForeground() throws {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID else { throw ChromeBrowserError.changed }
    }
    private nonisolated func cc(_ value: String) -> UInt32 { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private func targetDescriptor() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(descriptorType: cc("bund"), data: Data(Self.bundleID.utf8))!
    }
    private nonisolated func property(_ code: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object("prop", form: "prop", value: .init(typeCode: cc(code)), container: container)
    }
    private nonisolated func object(_ type: String, form: String, value: NSAppleEventDescriptor,
                        container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: cc(type)), forKeyword: cc("want"))
        record.setDescriptor(.init(enumCode: cc(form)), forKeyword: cc("form"))
        record.setDescriptor(value, forKeyword: cc("seld"))
        record.setDescriptor(container, forKeyword: cc("from"))
        return record.coerce(toDescriptorType: cc("obj "))!
    }
    private func get(_ reference: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor { try send("getd", direct: reference) }
    private func send(_ command: String, direct: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: cc("core"), eventID: cc(command), targetDescriptor: targetDescriptor(),
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(direct, forKeyword: cc("----"))
        do {
            // timeout 的单位是 tick（1/60 秒），120 即 2 秒；传 2 只有约 33 毫秒，Chrome 必然超时。
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 120)
            let error = reply.paramDescriptor(forKeyword: cc("errn"))?.int32Value ?? 0
            guard error == 0 else {
                throw Self.failure(for: Int(error))
            }
            return reply.paramDescriptor(forKeyword: cc("----")) ?? .null()
        } catch let error as ChromeBrowserError { throw error }
        catch {
            throw Self.failure(for: (error as NSError).code)
        }
    }
    static func failure(for code: Int) -> ChromeBrowserError {
        if code == -1743 { return .permission }
        if code == -1728 || code == -1719 { return .noPage }
        return .unavailable
    }
    private func page(from tab: NSAppleEventDescriptor, window: NSAppleEventDescriptor) throws -> GuardPage {
        guard let windowID = window.forKeyword(cc("ID  "))?.stringValue,
              let tabID = tab.forKeyword(cc("ID  "))?.stringValue,
              let url = tab.forKeyword(cc("URL "))?.stringValue,
              let title = tab.forKeyword(cc("pnam"))?.stringValue,
              let bounds = window.forKeyword(cc("pbnd")) else { throw ChromeBrowserError.noPage }
        return GuardPage(windowID: windowID, tabID: tabID, url: url, title: String(title.prefix(600)), isPrivate: false,
                         bounds: try Self.decodeBounds(bounds))
    }
    static func decodeBounds(_ value: NSAppleEventDescriptor) throws -> GuardPage.Bounds {
        if value.descriptorType == 0x71647274, value.data.count == 8 {
            let parts = value.data.withUnsafeBytes { raw in (0..<4).map { Double(raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) } }
            return .init(x: parts[1], y: parts[0], width: parts[3] - parts[1], height: parts[2] - parts[0])
        }
        if let list = value.coerce(toDescriptorType: 0x6C697374), list.numberOfItems == 4 {
            let a = (1...4).map { Double(list.atIndex($0)?.int32Value ?? 0) }
            return .init(x: a[0], y: a[1], width: a[2] - a[0], height: a[3] - a[1])
        }
        throw ChromeBrowserError.noPage
    }
}
