import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func render(_ pixels: Int, name: String) throws {
    let side = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(srgbRed: 0.965, green: 0.949, blue: 0.917, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: side * 0.07, y: side * 0.07, width: side * 0.86, height: side * 0.86),
                 xRadius: side * 0.20, yRadius: side * 0.20).fill()
    NSColor(srgbRed: 0.659, green: 0.275, blue: 0.196, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: side * 0.23, y: side * 0.20, width: side * 0.54, height: side * 0.55)).fill()
    NSColor(srgbRed: 0.322, green: 0.439, blue: 0.365, alpha: 1).setFill()
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: side * 0.49, y: side * 0.69))
    leaf.curve(to: NSPoint(x: side * 0.68, y: side * 0.81),
               controlPoint1: NSPoint(x: side * 0.47, y: side * 0.83),
               controlPoint2: NSPoint(x: side * 0.59, y: side * 0.83))
    leaf.curve(to: NSPoint(x: side * 0.49, y: side * 0.69),
               controlPoint1: NSPoint(x: side * 0.67, y: side * 0.69),
               controlPoint2: NSPoint(x: side * 0.58, y: side * 0.66))
    leaf.fill()
    NSColor(srgbRed: 1, green: 0.988, blue: 0.965, alpha: 1).setStroke()
    let hands = NSBezierPath()
    hands.lineWidth = side * 0.035
    hands.lineCapStyle = .round
    hands.move(to: NSPoint(x: side * 0.50, y: side * 0.62))
    hands.line(to: NSPoint(x: side * 0.50, y: side * 0.47))
    hands.line(to: NSPoint(x: side * 0.61, y: side * 0.40))
    hands.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    try render(size, name: "icon_\(size)x\(size).png")
    try render(size * 2, name: "icon_\(size)x\(size)@2x.png")
}
