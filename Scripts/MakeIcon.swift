import AppKit
let folder = CommandLine.arguments[1]
var entries = Data()
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let box = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.24, alpha: 1), ending: NSColor(calibratedRed: 0.035, green: 0.07, blue: 0.10, alpha: 1))!.draw(in: box, angle: -70)
        NSColor(calibratedRed: 0.40, green: 0.95, blue: 0.78, alpha: 1).setStroke()
        for y in [360.0, 510.0, 660.0] {
            let wave = NSBezierPath(); wave.lineWidth = 58; wave.lineCapStyle = .round
            wave.move(to: NSPoint(x: 240, y: y))
            wave.curve(to: NSPoint(x: 512, y: y), controlPoint1: NSPoint(x: 355, y: y + 125), controlPoint2: NSPoint(x: 395, y: y - 125))
            wave.curve(to: NSPoint(x: 784, y: y), controlPoint1: NSPoint(x: 630, y: y + 125), controlPoint2: NSPoint(x: 670, y: y - 125))
            wave.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: folder + "/icon_\(size)x\(size)\(suffix).png"))
        let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"], 256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
        entries.append(Data(types[size]![scale - 1].utf8))
        entries.append(bigEndian(png.count + 8))
        entries.append(png)
    }
}

var icon = Data("icns".utf8)
icon.append(bigEndian(entries.count + 8))
icon.append(entries)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
