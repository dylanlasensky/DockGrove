import AppKit
@main struct ReviewBenchmark {
 static func main() {
  CompanionDrawing.assetDirectory=URL(fileURLWithPath:"Assets.xcassets/Companions")
  for name in CompanionDrawing.names.keys.sorted() {
   precondition(CompanionDrawing.rig(name) != nil, "Missing rig")
   let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:360,pixelsHigh:160,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
   var m=CompanionMotion(seed:71);m.activity = .walk;m.weights=[.walk:1];m.destination=0.88;m.duration=20
   CompanionDrawing.draw(animal:name,motion:m,in:CGRect(x:0,y:0,width:360,height:160))
   precondition((bitmap.colorAt(x:180,y:80)?.alphaComponent ?? 0) > 0 || (bitmap.colorAt(x:200,y:90)?.alphaComponent ?? 0) > 0, "Render unexpectedly empty")
   var times:[Double]=[]
   for _ in 0..<240 {
    let start=ProcessInfo.processInfo.systemUptime
    autoreleasepool {
     NSGraphicsContext.current!.cgContext.clear(CGRect(x:0,y:0,width:360,height:160))
     m.advance(1.0/60,animal:name,resting:false)
     CompanionDrawing.draw(animal:name,motion:m,in:CGRect(x:0,y:0,width:360,height:160))
     NSGraphicsContext.current!.flushGraphics()
     precondition(bitmap.colorAt(x:180,y:80) != nil)
    }
    times.append((ProcessInfo.processInfo.systemUptime-start)*1000)
   }
   NSGraphicsContext.restoreGraphicsState();times.sort()
   print(String(format:"%@: offscreen Retina-size portrait render median %.2f ms, p95 %.2f ms (240 samples; not display FPS)",name,times[120],times[228]))
  }
 }
}
