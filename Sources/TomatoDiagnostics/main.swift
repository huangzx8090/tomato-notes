import AppKit
import Carbon
import Foundation
import TomatoCore
import TomatoSystem

struct CheckFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func require(_ value: Bool, _ message: String) throws {
    if !value { throw CheckFailure(message) }
}

func child(_ arguments: [String]) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    return process
}

func awaitReady(_ process: Process, at url: URL) throws {
    let deadline = Date().addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: url.path), process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    try require(FileManager.default.fileExists(atPath: url.path), "验证子进程未能就绪")
}

func register(_ code: UInt32, exclusive: Bool = true) -> (OSStatus, EventHotKeyRef?) {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(code, UInt32(controlKey | optionKey),
                                     EventHotKeyID(signature: 0x544D4447, id: code), GetApplicationEventTarget(),
                                     exclusive ? OptionBits(kEventHotKeyExclusive) : 0, &ref)
    return (status, ref)
}

func probe(_ code: UInt32, occupied: Bool) throws {
    let process = try child(["--probe-hotkey", String(code), occupied ? "occupied" : "free"])
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "跨进程按键 \(code) 的占用状态不符")
}

MainActor.assumeIsolated {
    do {
        let args = CommandLine.arguments
        switch args.dropFirst().first {
        case "--hold-lock":
            let repository = LocalRepository(fileURL: URL(fileURLWithPath: args[2]).appendingPathComponent("data.json"))
            let lock = try RepositoryLock(repository: repository)
            try Data().write(to: URL(fileURLWithPath: args[3]))
            withExtendedLifetime(lock) { RunLoop.main.run(until: Date().addingTimeInterval(30)) }
        case "--hold-hotkey":
            _ = NSApplication.shared
            let (status, ref) = register(UInt32(args[2])!, exclusive: args[4] == "exclusive")
            try require(status == noErr && ref != nil, "无法创建占用进程：\(status)")
            defer { if let ref { UnregisterEventHotKey(ref) } }
            try Data().write(to: URL(fileURLWithPath: args[3]))
            RunLoop.main.run(until: Date().addingTimeInterval(30))
        case "--probe-hotkey":
            _ = NSApplication.shared
            let (status, ref) = register(UInt32(args[2])!)
            defer { if let ref { UnregisterEventHotKey(ref) } }
            let occupied = status == OSStatus(eventHotKeyExistsErr)
            try require(args[3] == "occupied" ? occupied : status == noErr, "按键注册结果不符：\(status)")
        default:
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("TomatoChecks-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = root.appendingPathComponent("locked")
            let ready = root.appendingPathComponent("lock-ready")
            let holder = try child(["--hold-lock", directory.path, ready.path])
            defer { if holder.isRunning { holder.terminate(); holder.waitUntilExit() } }
            try awaitReady(holder, at: ready)
            do {
                _ = try RepositoryLock(repository: LocalRepository(fileURL: directory.appendingPathComponent("data.json")))
                throw CheckFailure("第二个进程错误地取得了同库锁")
            } catch RepositoryLockError.inUse(let owner) { try require(owner == holder.processIdentifier, "锁的进程标识不符") }
            let other = try RepositoryLock(repository: LocalRepository(fileURL: root.appendingPathComponent("other/data.json")))
            withExtendedLifetime(other) {}
            holder.terminate()
            holder.waitUntilExit()
            let released = try RepositoryLock(repository: LocalRepository(fileURL: directory.appendingPathComponent("data.json")))
            withExtendedLifetime(released) {}
            print("PASS 同库跨进程互斥、异库共存、进程退出自动释放")

            _ = NSApplication.shared
            let keyReady = root.appendingPathComponent("key-ready")
            let keyHolder = try child(["--hold-hotkey", "38", keyReady.path, "exclusive"]) // Control + Option + J
            defer { if keyHolder.isRunning { keyHolder.terminate(); keyHolder.waitUntilExit() } }
            try awaitReady(keyHolder, at: keyReady)
            var settings = AppSettings()
            settings.timerHotkey.letter = "F"
            settings.todoHotkey.letter = "G"
            settings.noteHotkey.letter = "H"
            let manager = HotkeyManager()
            try require(manager.apply(settings) == nil, "初始验证快捷键被占用，请释放 Control + Option + F/G/H 后重试")
            try probe(3, occupied: true)
            try probe(5, occupied: true)
            try probe(4, occupied: true)
            var duplicate = settings
            duplicate.todoHotkey.letter = "f"
            try require(manager.apply(duplicate) != nil, "未拒绝内部重复组合")
            try probe(3, occupied: true)
            var swapped = settings
            swapped.timerHotkey.letter = "G"
            swapped.todoHotkey.letter = "F"
            try require(manager.apply(swapped) == nil, "交换已有组合不应产生自占用")
            var conflict = swapped
            conflict.timerHotkey.letter = "I"
            conflict.todoHotkey.letter = "J"
            try require(manager.apply(conflict) != nil, "未发现另一进程的独占注册")
            try probe(3, occupied: true)
            try probe(5, occupied: true)
            try probe(4, occupied: true)
            try probe(34, occupied: false) // I 在事务失败后应已释放。
            settings.timerHotkey.enabled = false
            settings.todoHotkey.enabled = false
            settings.noteHotkey.enabled = false
            try require(manager.apply(settings) == nil, "无法停用快捷键")
            try probe(3, occupied: false)
            try probe(5, occupied: false)
            try probe(4, occupied: false)
            withExtendedLifetime(manager) {}
            print("PASS Carbon 真实跨进程冲突、内部重复、换键、失败保留旧键、释放新增键、关闭释放")
        }
    } catch {
        FileHandle.standardError.write(Data("FAIL \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
