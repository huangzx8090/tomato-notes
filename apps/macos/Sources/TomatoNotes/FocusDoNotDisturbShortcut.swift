import AppKit
import Foundation

@MainActor
final class FocusDoNotDisturbShortcutController {
    nonisolated private static let shortcutIDKey = "focusDoNotDisturbShortcutID"
    nonisolated private static let activatedByAppKey = "focusDoNotDisturbActivatedByApp"
    nonisolated private static let enabledKey = "focusDoNotDisturbEnabled"
    nonisolated private static let shortcutCommand = "/usr/bin/shortcuts"

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "TomatoNotes.FocusDoNotDisturbShortcut"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    private(set) var isInstalled: Bool
    private(set) var status: String
    var onStateChange: ((Bool, String) -> Void)?
    private var pendingShortcutName: String?
    private var isInstalling = false
    private var lastRequestedActive: Bool?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    init() {
        isInstalled = UserDefaults.standard.string(forKey: Self.shortcutIDKey) != nil
        status = isInstalled ? "快捷指令已安装。" : "首次使用前请安装勿扰快捷指令。"
    }

    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        publish(isInstalled: false, status: "正在准备本机快捷指令…")

        let suffix = String(UUID().uuidString.prefix(6)).uppercased()
        let name = "TomatoNotes 勿扰控制 \(suffix)"
        queue.addOperation { [weak self] in
            do {
                let shortcutURL = try Self.makeSignedShortcut(named: name)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.pendingShortcutName = name
                    guard NSWorkspace.shared.open(shortcutURL) else {
                        Self.removeFile(at: shortcutURL)
                        self.pendingShortcutName = nil
                        self.isInstalling = false
                        self.publish(isInstalled: false, status: "无法打开快捷指令导入窗口，请确认“快捷指令”应用可用后重试。")
                        return
                    }
                    self.publish(isInstalled: false, status: "请在“快捷指令”弹窗中点击“添加快捷指令”；添加后会自动连接。")
                    self.pollForImport(named: name, fileURL: shortcutURL, attempt: 0)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isInstalling = false
                    self.publish(isInstalled: false, status: "快捷指令准备失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func openInstalledShortcut() {
        guard let identifier = UserDefaults.standard.string(forKey: Self.shortcutIDKey) else {
            install()
            return
        }
        queue.addOperation { [weak self] in
            do {
                _ = try Self.runCommand(arguments: ["view", identifier])
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.publish(isInstalled: false, status: "无法打开已安装的快捷指令；若已从系统中删除，请重新安装。")
                }
            }
        }
    }

    func setActive(_ active: Bool) {
        guard lastRequestedActive != active else { return }
        lastRequestedActive = active
        queue.addOperation { [weak self] in
            let defaults = UserDefaults.standard
            let wasActivatedByApp = defaults.bool(forKey: Self.activatedByAppKey)
            guard active != wasActivatedByApp else { return }
            guard let identifier = defaults.string(forKey: Self.shortcutIDKey) else {
                DispatchQueue.main.async { [weak self] in
                    self?.publish(isInstalled: false, status: "请先安装勿扰快捷指令，再开启此选项。")
                }
                return
            }

            do {
                let result = try Self.runCommand(arguments: ["run", identifier, "--input-path", "-"],
                                                 input: active ? "on" : "off")
                guard result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
                    throw ShortcutError.runFailed(result.error.isEmpty ? "快捷指令未确认操作结果。" : result.error)
                }
                defaults.set(active, forKey: Self.activatedByAppKey)
                DispatchQueue.main.async { [weak self] in
                    self?.publish(isInstalled: true, status: active ? "专注勿扰已开启。" : "专注勿扰已关闭。")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.publish(isInstalled: true, status: "勿扰切换失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func waitForPendingOperations() {
        queue.waitUntilAllOperationsAreFinished()
    }

    private func pollForImport(named name: String, fileURL: URL, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.pendingShortcutName == name else { return }
            self.queue.addOperation { [weak self] in
                let identifier: String?
                do {
                    let result = try Self.runCommand(arguments: ["list", "--show-identifiers"])
                    identifier = Self.identifier(for: name, in: result.output)
                } catch {
                    identifier = nil
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.pendingShortcutName == name else { return }
                    if let identifier {
                        UserDefaults.standard.set(identifier, forKey: Self.shortcutIDKey)
                        self.pendingShortcutName = nil
                        self.isInstalling = false
                        self.lastRequestedActive = nil
                        Self.removeFile(at: fileURL)
                        self.publish(isInstalled: true, status: "快捷指令已添加。现在可以开启上方选项。")
                    } else if attempt < 59 {
                        self.pollForImport(named: name, fileURL: fileURL, attempt: attempt + 1)
                    } else {
                        self.pendingShortcutName = nil
                        self.isInstalling = false
                        Self.removeFile(at: fileURL)
                        self.publish(isInstalled: false, status: "还没有检测到快捷指令；点击安装按钮可重新尝试。")
                    }
                }
            }
        }
    }

    private func publish(isInstalled: Bool, status: String) {
        self.isInstalled = isInstalled
        self.status = status
        onStateChange?(isInstalled, status)
    }

    nonisolated private static func identifier(for name: String, in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard entry.hasPrefix("\(name) ("), entry.last == ")",
                  let openParen = entry.lastIndex(of: "(") else { continue }
            let value = entry[entry.index(after: openParen)..<entry.index(before: entry.endIndex)]
            if UUID(uuidString: String(value)) != nil { return String(value) }
        }
        return nil
    }

    nonisolated private static func makeSignedShortcut(named name: String) throws -> URL {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.zixuan.TomatoNotes"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Shortcuts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let unsignedURL = directory.appendingPathComponent("\(name).unsigned.shortcut")
        let signedURL = directory.appendingPathComponent("\(name).shortcut")
        let data = try PropertyListSerialization.data(fromPropertyList: workflow(), format: .binary, options: 0)
        try data.write(to: unsignedURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unsignedURL.path)

        defer { removeFile(at: unsignedURL) }
        // Apple 会验证快捷指令副本；使用 anyone 模式避免把本机联系人信息写入文件。
        _ = try runCommand(arguments: ["sign", "--mode", "anyone",
                                        "--input", unsignedURL.path, "--output", signedURL.path])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: signedURL.path)
        return signedURL
    }

    nonisolated private static func workflow() -> [String: Any] {
        // 快捷指令接收 on/off 输入，只切换系统“勿扰”专注模式并返回确认文本。
        let inputID = UUID().uuidString.uppercased()
        var actions: [[String: Any]] = [
            action("is.workflow.actions.text.trimwhitespace", [
                "UUID": inputID,
                "WFInput": [
                    "WFSerializationType": "WFTextTokenString",
                    "Value": [
                        "string": "\u{FFFC}",
                        "attachmentsByRange": ["{0, 1}": ["Type": "ExtensionInput"]]
                    ]
                ]
            ])
        ]
        actions += conditional(inputID: inputID, value: "on", enabled: true)
        actions += conditional(inputID: inputID, value: "off", enabled: false)
        actions.append(action("is.workflow.actions.output", ["WFOutput": textToken("unknown")]))

        return [
            "WFWorkflowClientVersion": "2607.0.4",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowImportQuestions": [],
            "WFWorkflowTypes": [],
            "WFQuickActionSurfaces": [],
            "WFWorkflowHasShortcutInputVariables": true,
            "WFWorkflowInputContentItemClasses": ["WFStringContentItem", "WFGenericFileContentItem"],
            "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"],
            "WFWorkflowActions": actions
        ]
    }

    nonisolated private static func conditional(inputID: String, value: String, enabled: Bool) -> [[String: Any]] {
        let groupID = UUID().uuidString.uppercased()
        return [
            action("is.workflow.actions.conditional", [
                "GroupingIdentifier": groupID,
                "WFControlFlowMode": 0,
                "WFCondition": 4,
                "WFConditionalActionString": value,
                "WFInput": [
                    "Type": "Variable",
                    "Variable": [
                        "WFSerializationType": "WFTextTokenAttachment",
                        "Value": ["Type": "ActionOutput", "OutputName": "Updated Text", "OutputUUID": inputID]
                    ]
                ]
            ]),
            action("is.workflow.actions.dnd.set", ["Enabled": enabled ? 1 : 0]),
            action("is.workflow.actions.output", ["WFOutput": textToken("ok")]),
            action("is.workflow.actions.conditional", ["GroupingIdentifier": groupID, "WFControlFlowMode": 1]),
            action("is.workflow.actions.conditional", ["GroupingIdentifier": groupID, "WFControlFlowMode": 2])
        ]
    }

    nonisolated private static func action(_ identifier: String, _ parameters: [String: Any]) -> [String: Any] {
        ["WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": parameters]
    }

    nonisolated private static func textToken(_ value: String) -> [String: Any] {
        ["WFSerializationType": "WFTextTokenString", "Value": ["string": value, "attachmentsByRange": [:]]]
    }

    nonisolated private static func runCommand(arguments: [String], input: String? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shortcutCommand)
        process.arguments = arguments
        let outputCapture = PipeCapture()
        let errorCapture = PipeCapture()
        process.standardOutput = outputCapture.pipe
        process.standardError = errorCapture.pipe
        let inputPipe = Pipe()
        if input != nil { process.standardInput = inputPipe }

        try process.run()
        let readers = DispatchGroup()
        outputCapture.startReading(in: readers)
        errorCapture.startReading(in: readers)
        if let input {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        readers.wait()
        let output = String(decoding: outputCapture.data, as: UTF8.self)
        let error = String(decoding: errorCapture.data, as: UTF8.self)
        let result = CommandResult(status: process.terminationStatus, output: output, error: error.trimmingCharacters(in: .whitespacesAndNewlines))
        guard result.status == 0 else { throw ShortcutError.commandFailed(result.error.isEmpty ? "shortcuts 命令退出码 \(result.status)" : result.error) }
        return result
    }

    nonisolated private static func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        let error: String
    }

    private final class PipeCapture: @unchecked Sendable {
        let pipe = Pipe()
        private let lock = NSLock()
        private var capturedData = Data()

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return capturedData
        }

        func startReading(in group: DispatchGroup) {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                capturedData = data
                lock.unlock()
                group.leave()
            }
        }
    }

    private enum ShortcutError: LocalizedError {
        case commandFailed(String)
        case runFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message): message
            case .runFailed(let message): message
            }
        }
    }
}
