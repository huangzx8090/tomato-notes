import Foundation

public enum RepositoryError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "数据版本 \(version) 高于当前应用支持的版本；原始数据未改动。"
        }
    }
}

public struct LocalRepository {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = root.appendingPathComponent("TomatoNotes", isDirectory: true)
                .appendingPathComponent("data.json")
        }
    }

    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppData() }
        let data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fileURL))
        guard data.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion(data.schemaVersion) }
        return data
    }

    public func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: .atomic)
    }

    /// 复制磁盘上的原始字节，不用重新编码覆盖备份，便于恢复和核对。
    @discardableResult
    public func backup(to directory: URL? = nil) throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let root = directory ?? fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = root.appendingPathComponent("data-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        try FileManager.default.copyItem(at: fileURL, to: destination)
        return destination
    }
}
