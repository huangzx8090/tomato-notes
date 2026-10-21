import Foundation
import ImageIO
import TomatoCore
import UniformTypeIdentifiers

public enum ImageImportError: LocalizedError {
    case tooLarge, unsupported, encodeFailed
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "单张图片不能超过 25 MB，请先缩小图片。"
        case .unsupported: "无法读取这张图片，请使用 PNG、JPEG、HEIC 或 WebP。"
        case .encodeFailed: "图片保存失败，请重试。"
        }
    }
}

public struct WorkImageStore: Sendable {
    public let directory: URL
    public init(repository: LocalRepository) {
        directory = repository.fileURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    }
    public func url(for image: WorkImage) -> URL { directory.appendingPathComponent(image.fileName) }

    public func importImages(at urls: [URL]) throws -> [WorkImage] {
        var imported: [WorkImage] = []
        do {
            for url in urls { imported.append(try importImage(at: url)) }
            return imported
        } catch {
            for image in imported { try? FileManager.default.removeItem(at: self.url(for: image)) }
            throw error
        }
    }

    public func importImage(at url: URL) throws -> WorkImage {
        let resources = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (resources.fileSize ?? 0) <= 25 * 1024 * 1024 else { throw ImageImportError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw ImageImportError.unsupported }
        let record = WorkImage(name: url.lastPathComponent)
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw ImageImportError.encodeFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageImportError.encodeFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (bytes as Data).write(to: self.url(for: record), options: .atomic)
        return record
    }
}
