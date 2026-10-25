import Foundation

public enum RepositoryLocationError: LocalizedError {
    case missingDirectory
    case conflictingOptions
    case testUsesSharedLibrary

    public var errorDescription: String? {
        switch self {
        case .missingDirectory: "--data-dir 后需要提供独立资料目录；未打开或写入日常资料。"
        case .conflictingOptions: "--shared-data 不能与 --data-dir 或 --ui-test 同时使用。"
        case .testUsesSharedLibrary: "测试模式不能使用日常资料目录，请通过 --data-dir 指定独立目录。"
        }
    }
}

public enum RepositoryLocation {
    /// 应用名称、安装位置和 Bundle ID 不决定日常资料位置；只有显式测试或自定义目录才隔离。
    public static func resolve(arguments: [String], bundleIdentifier: String?,
                               applicationSupportDirectory: URL? = nil) throws -> LocalRepository {
        let root = applicationSupportDirectory ?? LocalRepository.sharedFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let shared = LocalRepository(fileURL: root.appendingPathComponent("TomatoNotes/data.json"))
        let testing = arguments.contains("--ui-test")
        let customIndices = arguments.indices.filter { arguments[$0] == "--data-dir" }
        if arguments.contains("--shared-data"), testing || !customIndices.isEmpty {
            throw RepositoryLocationError.conflictingOptions
        }
        if let index = customIndices.first {
            guard customIndices.count == 1, arguments.indices.contains(index + 1),
                  !arguments[index + 1].isEmpty, !arguments[index + 1].hasPrefix("--") else {
                throw RepositoryLocationError.missingDirectory
            }
            let repository = LocalRepository(fileURL: URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                .appendingPathComponent("data.json"))
            guard !testing || repository.fileURL != shared.fileURL else { throw RepositoryLocationError.testUsesSharedLibrary }
            return repository
        }
        if testing {
            let name = bundleIdentifier == "com.zixuan.TomatoNotes.GuardQA" ? "TomatoNotes-GuardQA" : "TomatoNotes-QA"
            return LocalRepository(fileURL: root.appendingPathComponent("\(name)/data.json"))
        }
        return shared
    }
}
