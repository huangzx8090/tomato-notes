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
            self.fileURL = fileURL
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
}
