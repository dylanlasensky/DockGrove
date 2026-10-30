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
        // Resample the exact owner's icon crop into standard macOS icon sizes.
        let source = NSImage(contentsOfFile: "Assets.xcassets/Brand/DockGrove-icon.imageset/DockGrove-icon.png")!
        source.draw(in: NSRect(x:40,y:40,width:944,height:944), from:.zero, operation:.sourceOver, fraction:1)
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
