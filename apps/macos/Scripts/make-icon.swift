import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("用法：swift Scripts/make-icon.swift <输出 iconset 目录>\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Packaging/AppIcon.png")
guard let sourceImage = NSImage(contentsOf: sourceURL),
      sourceImage.size.width > 0,
      sourceImage.size.width == sourceImage.size.height else {
    fputs("无法读取正方形图标原图：\(sourceURL.path)\n", stderr)
    exit(1)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func render(_ pixels: Int, name: String) throws {
    let side = CGFloat(pixels)
    let canvas = NSRect(x: 0, y: 0, width: side, height: side)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(canvas)

    // 原图保留完整材质，统一裁出圆角与透明边距，避免抠图杂点进入各尺寸图标。
    let iconBounds = canvas.insetBy(dx: side * 0.07, dy: side * 0.07)
    NSBezierPath(roundedRect: iconBounds, xRadius: side * 0.20, yRadius: side * 0.20).addClip()
    sourceImage.draw(in: iconBounds, from: .zero, operation: .copy, fraction: 1)

    try bitmap.representation(using: .png, properties: [:])!
        .write(to: destination.appendingPathComponent(name), options: .atomic)
}

for size in [16, 32, 128, 256, 512] {
    try render(size, name: "icon_\(size)x\(size).png")
    try render(size * 2, name: "icon_\(size)x\(size)@2x.png")
}
