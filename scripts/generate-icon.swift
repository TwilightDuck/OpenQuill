import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let s = CGFloat(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.055, green: 0.15, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84), xRadius: s * 0.19, yRadius: s * 0.19).fill()
    NSColor(calibratedRed: 0.45, green: 0.93, blue: 0.77, alpha: 1).setFill()
    for (i, height) in [0.15, 0.28, 0.45, 0.59, 0.39, 0.25, 0.12].enumerated() {
        let width = s * 0.055
        NSBezierPath(roundedRect: NSRect(x: s * (0.245 + Double(i) * 0.077), y: s * (0.5 - height / 2), width: width, height: s * height), xRadius: width / 2, yRadius: width / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
