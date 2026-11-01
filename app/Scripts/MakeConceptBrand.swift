import AppKit
// Owner-selected three-bar Dock mark from the November landing-page concept.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor { NSColor(srgbRed:r/255,green:g/255,blue:b/255,alpha:1) }
func mark() {
    func pill(_ rect:NSRect,_ fill:NSColor,_ radius:CGFloat=5) { fill.setFill(); NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill() }
    pill(NSRect(x:8,y:15,width:14,height:24),color(31,38,44))
    pill(NSRect(x:25,y:15,width:14,height:34),color(61,132,249))
    pill(NSRect(x:42,y:15,width:14,height:22),color(185,195,207))
    let base=NSBezierPath();base.move(to:NSPoint(x:4,y:15));base.curve(to:NSPoint(x:14,y:4),controlPoint1:NSPoint(x:4,y:8),controlPoint2:NSPoint(x:7,y:4));base.line(to:NSPoint(x:50,y:4));base.curve(to:NSPoint(x:60,y:15),controlPoint1:NSPoint(x:57,y:4),controlPoint2:NSPoint(x:60,y:8));base.line(to:NSPoint(x:53,y:15));base.curve(to:NSPoint(x:48,y:11),controlPoint1:NSPoint(x:52,y:12),controlPoint2:NSPoint(x:51,y:11));base.line(to:NSPoint(x:16,y:11));base.curve(to:NSPoint(x:11,y:15),controlPoint1:NSPoint(x:13,y:11),controlPoint2:NSPoint(x:12,y:12));base.close();color(24,30,35).setFill();base.fill()
}
func render(_ width:Int,_ height:Int,_ output:String,_ drawing:()->Void) {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap);drawing();NSGraphicsContext.restoreGraphicsState()
    let url=root.appendingPathComponent(output);try! FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try! bitmap.representation(using:.png,properties:[:])!.write(to:url)
}
func icon(_ size:Int,_ path:String) {render(size,size,path) {
    let c=NSGraphicsContext.current!.cgContext;c.scaleBy(x:CGFloat(size)/128,y:CGFloat(size)/128)
    NSColor.white.setFill();NSBezierPath(roundedRect:NSRect(x:7,y:7,width:114,height:114),xRadius:25,yRadius:25).fill()
    color(224,229,235).setStroke();let border=NSBezierPath(roundedRect:NSRect(x:7,y:7,width:114,height:114),xRadius:25,yRadius:25);border.lineWidth=0.8;border.stroke()
    c.translateBy(x:19,y:23);c.scaleBy(x:1.4,y:1.4);mark()
}}
for n in [16,32,128,256,512] {for scale in [1,2] {icon(n*scale,"app/Assets.xcassets/AppIcon.appiconset/icon_\(n)x\(n)\(scale==2 ? "@2x":"").png")}}
for path in ["website/web/public/assets/DockGrove-icon.png","app/Assets.xcassets/Brand/DockGrove-icon.imageset/DockGrove-icon.png"] {icon(1024,path)}
for path in ["website/web/public/assets/DockGrove-wordmark.png","app/Assets.xcassets/Brand/DockGrove-wordmark.imageset/DockGrove-wordmark.png"] {render(840,200,path) {let c=NSGraphicsContext.current!.cgContext;c.scaleBy(x:3,y:3);c.translateBy(x:0,y:5);mark();("DockGrove" as NSString).draw(at:NSPoint(x:74,y:11),withAttributes:[.font:NSFont.systemFont(ofSize:36,weight:.bold),.foregroundColor:color(17,21,24),.kern:-1.5])}}
render(512,424,"app/Assets.xcassets/Brand/DockGrove-mark.imageset/DockGrove-mark.png") {NSGraphicsContext.current!.cgContext.scaleBy(x:8,y:8);mark()}
render(1000,340,"app/Assets.xcassets/Brand/DockGrove-brand-sheet.imageset/DockGrove-brand-sheet.png") {
    NSColor.white.setFill();NSRect(x:0,y:0,width:1000,height:340).fill()
    let c=NSGraphicsContext.current!.cgContext;c.translateBy(x:62,y:90);c.scaleBy(x:3,y:3);mark()
    ("DockGrove" as NSString).draw(at:NSPoint(x:74,y:11),withAttributes:[.font:NSFont.systemFont(ofSize:36,weight:.bold),.foregroundColor:color(17,21,24),.kern:-1.5])
}
