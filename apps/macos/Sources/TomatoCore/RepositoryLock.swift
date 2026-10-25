import Darwin
import Foundation

public enum RepositoryLockError: LocalizedError {
    case inUse(processID: Int32?)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .inUse: "这份数据已由另一个番茄小记进程打开。"
        case .unavailable(let message): "无法保护本地数据：\(message)"
        }
    }
}

/// 在读取数据之前取得锁，持有至进程退出；不删除锁文件，避免旧 inode 与新文件同时被锁定。
public final class RepositoryLock {
    private let descriptor: Int32

    public init(repository: LocalRepository) throws {
        let directory = repository.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(".tomato-notes.lock")
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RepositoryLockError.unavailable(String(cString: strerror(errno))) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            let owner = (try? String(contentsOf: url, encoding: .utf8))
                .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            close(fd)
            if code == EWOULDBLOCK { throw RepositoryLockError.inUse(processID: owner) }
            throw RepositoryLockError.unavailable(String(cString: strerror(code)))
        }
        let owner = Array("\(getpid())\n".utf8)
        guard ftruncate(fd, 0) == 0, owner.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == owner.count else {
            let code = errno
            close(fd)
            throw RepositoryLockError.unavailable(String(cString: strerror(code)))
        }
        descriptor = fd
    }

    deinit { close(descriptor) }
}
