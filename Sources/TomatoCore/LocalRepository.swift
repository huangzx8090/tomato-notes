import Foundation

public enum RepositoryError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "当前应用不支持数据版本 \(version)；原始数据未改动。"
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
        var data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fileURL))
        guard (1...AppData.currentSchemaVersion).contains(data.schemaVersion) else { throw RepositoryError.unsupportedVersion(data.schemaVersion) }
        if data.schemaVersion < AppData.currentSchemaVersion {
            // 升级前先保存原始字节；旧版会拒绝新版本数据，避免丢弃 AI 成果字段。
            try backup(to: fileURL.deletingLastPathComponent().appendingPathComponent("Backups/schema-v\(data.schemaVersion)"))
            data.schemaVersion = AppData.currentSchemaVersion
        }
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
        let attachments = fileURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
        if FileManager.default.fileExists(atPath: attachments.path) {
            let assets = destination.deletingPathExtension().appendingPathExtension("assets").appendingPathComponent("Attachments", isDirectory: true)
            if let model = try? JSONDecoder().decode(AppData.self, from: Data(contentsOf: fileURL)) {
                let imageNames = Set(model.workRecords.flatMap(\.images).map(\.fileName))
                if !imageNames.isEmpty {
                    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                    for name in imageNames {
                        try FileManager.default.copyItem(at: attachments.appendingPathComponent(name), to: assets.appendingPathComponent(name))
                    }
                }
            } else { try FileManager.default.copyItem(at: attachments, to: assets) }
        }
        return destination
    }
}
