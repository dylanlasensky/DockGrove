import AppKit
@main struct CompanionAssetAudit {
 static func main() {
  CompanionDrawing.assetDirectory=URL(fileURLWithPath:"Assets/Companions")
  let requested=Array(CommandLine.arguments.dropFirst())
  for name in CompanionDrawing.names.keys.sorted() where requested.isEmpty || requested.contains(name) {
   guard let atlas=CompanionDrawing.rig(name) else {preconditionFailure("Missing/malformed 4x4 pixel atlas: \(name)")}
   precondition(atlas.cells.count==16 && atlas.frames.count==16)
   for (index,cell) in atlas.cells.enumerated() {
    let b=NSBitmapImageRep(cgImage:cell),w=cell.width,h=cell.height
    var edges=0,ink=0
    for y in 0..<h {for x in 0..<w {if (b.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.4 {ink+=1;if x<2 || y<2 || x>=w-2 || y>=h-2 {edges+=1}}}}
    precondition(ink>40,"Empty pixel pose \(name) \(index)")
    precondition(edges==0,"Pixel pose crosses fixed cell boundary: \(name) \(index), \(edges) pixels")
    precondition(atlas.frames[index].width==atlas.frames[0].width && atlas.frames[index].height==atlas.frames[0].height,"Per-frame scaling would wobble")
   }
   for index in 0..<16 {
    var m=CompanionMotion();m.gait=Double(index)*2 * .pi/8;m.velocity=index<8 ? 0.05:0;m.total=Double(max(0,index-8))/3
    if index>=12 {m.activity = .sleep;m.weights=[.sleep:index==12 ? 0.25:index==13 ? 0.6:1];m.total=Double(index-14)/1.2+2}
    let scale=min(256*0.66/atlas.sharedBounds.width,192*0.82/atlas.sharedBounds.height)
    let width=atlas.sharedBounds.width*scale,span=256-width-8
    let strideFraction=name=="Rabbit" ? 0.20:name=="Cow" ? 0.10:0.12
    m.travelDistance=Double(index%8)/8*width*strideFraction/span
    if name=="Dragon" && index<8 {m.total=Double(index)/9}
    let chosen=CompanionDrawing.frameIndex(animal:name,motion:m)
    precondition((0..<16).contains(chosen))
    for facing in [-1.0,1.0] {
     m.facing=facing;m.x=facing<0 ? 0.12:0.88
     let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:256,pixelsHigh:192,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
     NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:image)
     CompanionDrawing.draw(animal:name,motion:m,in:CGRect(x:0,y:0,width:256,height:192));NSGraphicsContext.restoreGraphicsState()
     var edge=0
     for x in 0..<256 {for y in [0,191] {if (image.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.4 {edge+=1}}}
     for y in 0..<192 {for x in [0,255] {if (image.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.4 {edge+=1}}}
     precondition(edge==0,"Clipped native pixel render \(name) pose\(index) facing\(facing)")
    }
   }
   print("PASS \(name): 16 complete pixel poses, clear fixed cell boundaries, shared crop and scale; 32 native mirrored render bounds")
  }
 }
}
