import CoreGraphics
import Foundation
import ImageIO
import Testing
import TomatoCore
import TomatoSystem
import UniformTypeIdentifiers

struct ImageStoreTests {
    @Test func importsBoundedImageWithoutLocationMetadataAndBacksUpAssets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: 3200, height: 1000, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3200, height: 1000))
        let image = try #require(context.makeImage())
        let sourceURL = root.appendingPathComponent("input.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(sourceURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10.0, kCGImagePropertyGPSLongitude: 20.0]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let repository = LocalRepository(fileURL: root.appendingPathComponent("data/data.json"))
        let store = WorkImageStore(repository: repository)
        let imported = try store.importImage(at: sourceURL)
        let saved = try #require(CGImageSourceCreateWithURL(store.url(for: imported) as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(saved, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1600)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 500)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        var data = AppData()
        var record = WorkRecord(localDay: "2026-10-21")
        record.images = [imported]
        data.workRecords = [record]
        try repository.save(data)
        let backup = try #require(try repository.backup())
        let asset = backup.deletingPathExtension().appendingPathExtension("assets").appendingPathComponent("Attachments/\(imported.fileName)")
        #expect(try Data(contentsOf: asset) == Data(contentsOf: store.url(for: imported)))
    }
}
