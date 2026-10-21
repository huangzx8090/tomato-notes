import Foundation
import TomatoCore
import TomatoSystem

enum ToolError: LocalizedError {
    case usage
    case destinationExists
    case missingSource(String)
    var errorDescription: String? {
        switch self {
        case .usage: "用法：TomatoDataTool merge --primary 数据文件 --source 数据文件 --destination 新数据文件 [--use-default-settings] [--show-dock] [--exclude-todo-id UUID]"
        case .destinationExists: "目标数据文件已经存在；为保护现有内容，不能直接覆盖。"
        case .missingSource(let path): "来源文件不存在：\(path)"
        }
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "import-deepseek-key" {
        guard let key = DeepSeekCredentials.environmentKey else {
            throw NSError(domain: "TomatoDataTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前终端未设置 deepseek 或 DEEPSEEK_API_KEY 环境变量。"])
        }
        try DeepSeekCredentials().save(key)
        print("DeepSeek 环境变量已导入本机钥匙串；未输出密钥。")
        exit(0)
    }
    guard args.first == "merge" else { throw ToolError.usage }
    var primaryPath: String?
    var sourcePaths: [String] = []
    var destinationPath: String?
    var defaults = false
    var showDock = false
    var excluded = Set<UUID>()
    var index = 1
    while index < args.count {
        let flag = args[index]
        if flag == "--use-default-settings" { defaults = true; index += 1; continue }
        if flag == "--show-dock" { showDock = true; index += 1; continue }
        guard index + 1 < args.count else { throw ToolError.usage }
        let value = args[index + 1]
        switch flag {
        case "--primary": primaryPath = value
        case "--source": sourcePaths.append(value)
        case "--destination": destinationPath = value
        case "--exclude-todo-id":
            guard let id = UUID(uuidString: value) else { throw ToolError.usage }
            excluded.insert(id)
        default: throw ToolError.usage
        }
        index += 2
    }
    guard let primaryPath, let destinationPath else { throw ToolError.usage }
    let destination = LocalRepository(fileURL: URL(fileURLWithPath: destinationPath))
    let sources = ([primaryPath] + sourcePaths).map { LocalRepository(fileURL: URL(fileURLWithPath: $0)) }
    let lockDirectories = Set(([destination] + sources).map { $0.fileURL.deletingLastPathComponent() })
    let locks = try lockDirectories.sorted { $0.path < $1.path }.map {
        try RepositoryLock(repository: LocalRepository(fileURL: $0.appendingPathComponent("data.json")))
    }
    try withExtendedLifetime(locks) {
        guard !FileManager.default.fileExists(atPath: destination.fileURL.path) else { throw ToolError.destinationExists }
        for source in sources where !FileManager.default.fileExists(atPath: source.fileURL.path) { throw ToolError.missingSource(source.fileURL.path) }
        let loaded = try sources.map { try $0.load() }
        var merged = try DataMerger.merge(primary: loaded[0], importing: Array(loaded.dropFirst()))
        merged.todos.removeAll { excluded.contains($0.id) }
        if defaults { merged.settings = AppSettings() }
        if showDock { merged.settings.showDockIcon = true }
        if merged.timer.phase == .idle {
            merged.timer.targetSeconds = merged.settings.duration(for: .focus)
            merged.timer.remainingSeconds = merged.timer.targetSeconds
        }
        let backupRoot = destination.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Backups/migration-\(UUID().uuidString)", isDirectory: true)
        for (offset, source) in sources.enumerated() {
            try source.backup(to: backupRoot.appendingPathComponent("source-\(offset)", isDirectory: true))
        }
        let targetImages = WorkImageStore(repository: destination)
        for image in merged.workRecords.flatMap(\.images) {
            let candidates = sources.map { WorkImageStore(repository: $0).url(for: image) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard let first = candidates.first else { throw DeepSeekError.missingImage }
            let bytes = try Data(contentsOf: first)
            for candidate in candidates.dropFirst() where try Data(contentsOf: candidate) != bytes {
                throw DataMergeError.conflict("成果图片", image.id)
            }
            try FileManager.default.createDirectory(at: targetImages.directory, withIntermediateDirectories: true)
            let target = targetImages.url(for: image)
            if FileManager.default.fileExists(atPath: target.path) {
                guard try Data(contentsOf: target) == bytes else { throw DataMergeError.conflict("成果图片", image.id) }
            } else { try bytes.write(to: target, options: .atomic) }
        }
        try destination.save(merged)
        print("已合并：\(merged.sessions.count) 轮记录、\(merged.todos.count) 条待办、\(merged.notes.count) 张便签；计时状态 \(merged.timer.phase.rawValue)")
        print("原始文件保持原位；备份：\(backupRoot.path)")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
