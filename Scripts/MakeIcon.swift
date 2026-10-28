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
        NSGradient(starting: NSColor(white: 0.25, alpha: 1), ending: NSColor(white: 0.055, alpha: 1))!.draw(in: box, angle: -65)
        NSColor(white: 1, alpha: 0.18).setStroke(); box.lineWidth = 2; box.stroke()
        NSColor(white: 0.97, alpha: 1).setStroke()
        for offset in [0.0, 175.0] {
            let wave = NSBezierPath(); wave.lineWidth = 53; wave.lineCapStyle = .round
            wave.move(to: NSPoint(x: 230, y: 510 + offset))
            wave.curve(to: NSPoint(x: 512, y: 448 + offset), controlPoint1: NSPoint(x: 355, y: 208 + offset), controlPoint2: NSPoint(x: 370, y: 600 + offset))
            wave.curve(to: NSPoint(x: 794, y: 535 + offset), controlPoint1: NSPoint(x: 660, y: 280 + offset), controlPoint2: NSPoint(x: 682, y: 420 + offset))
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
