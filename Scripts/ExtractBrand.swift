// Exact crops from the owner's supplied DockGroveLOGO.png; no generated or redrawn artwork.
import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let brand = root.appendingPathComponent("Assets/Brand")
let source = NSImage(contentsOf: brand.appendingPathComponent("DockGrove-brand-sheet.png"))!
var bounds = CGRect(origin: .zero, size: source.size)
let full = source.cgImage(forProposedRect: &bounds, context: nil, hints: nil)!
func crop(_ name: String, _ rect: CGRect, radius: CGFloat = 0) throws {
    let cropped = full.cropping(to: rect)!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cropped.width, pixelsHigh: cropped.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if radius > 0 { NSBezierPath(roundedRect: CGRect(x:0,y:0,width:cropped.width,height:cropped.height), xRadius:radius,yRadius:radius).addClip() }
    NSGraphicsContext.current!.cgContext.draw(cropped, in: CGRect(x:0,y:0,width:cropped.width,height:cropped.height))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:brand.appendingPathComponent(name))
}
try crop("DockGrove-icon.png", CGRect(x:637,y:489,width:262,height:266), radius:51)
try crop("DockGrove-wordmark.png", CGRect(x:150,y:120,width:1255,height:300))
try crop("DockGrove-mark.png", CGRect(x:158,y:499,width:274,height:254))
