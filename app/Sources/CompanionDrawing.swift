import AppKit

/// Coherent whole-body pixel poses. All cells share one crop, scale and baseline;
/// no independently transformed body parts or blended ghost frames are drawn.
enum CompanionDrawing {
    static let names=["Miso":"miso","Black cat":"black-cat","Orange cat":"orange-cat","Golden dog":"golden-dog","Husky":"husky","Dragon":"dragon","Cow":"cow","Rabbit":"rabbit","Fox":"fox"]
    static var assetDirectory:URL? { didSet { cache.removeAll() } }
    struct Sheet { var frames:[NSImage];var maximum:CGSize }
    struct PixelAtlas { var cells:[CGImage];var frames:[CGImage];var sharedBounds:CGRect;var cellSize:CGSize }
    private static var cache:[String:PixelAtlas]=[:]
    static func rig(_ animal:String)->PixelAtlas? {
        guard let key=names[animal] else{return nil}
        if let cached=cache[key] {return cached}
        let source: NSImage?
        if let directory = assetDirectory {
            let flat = directory.appendingPathComponent(key + "-pixel.png")
            let catalog = directory.appendingPathComponent("Companion-" + key + "-pixel.imageset/" + key + "-pixel.png")
            source = NSImage(contentsOf: FileManager.default.fileExists(atPath: flat.path) ? flat : catalog)
        } else { source = NSImage(named: "Companion-" + key + "-pixel") }
        guard let source, let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
        let w=Int(ceil(Double(cg.width)/4)),h=Int(ceil(Double(cg.height)/4))
        var cells:[CGImage]=[],cellBounds:[CGRect]=[],union=CGRect.null
        for i in 0..<16 {
            let left=Int((Double(i%4)*Double(cg.width)/4).rounded()),right=Int((Double(i%4+1)*Double(cg.width)/4).rounded())
            let top=Int((Double(i/4)*Double(cg.height)/4).rounded()),bottom=Int((Double(i/4+1)*Double(cg.height)/4).rounded())
            guard let raw=cg.cropping(to:CGRect(x:left,y:top,width:right-left,height:bottom-top)),let canvas=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
            canvas.interpolationQuality = .none
            canvas.draw(raw,in:CGRect(x:0,y:h-raw.height,width:raw.width,height:raw.height))
            guard let cell=canvas.makeImage() else{return nil}
            cells.append(cell)
            let bitmap=NSBitmapImageRep(cgImage:cell)
            var minX=w,minY=h,maxX = -1,maxY = -1
            for y in 0..<h {for x in 0..<w { if let color=bitmap.colorAt(x:x,y:y), color.alphaComponent>0.08 {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)} }}
            guard maxX>=minX,maxY>=minY else{return nil}
            let bounds=CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)
            cellBounds.append(bounds);union=union.union(bounds)
        }
        // Register whole activity rows to the walking floor; retain all eight
        // walking poses' original lift differences. No per-frame scale changes.
        let floor=cellBounds.prefix(8).map(\.maxY).max()!
        let idleFloor=cellBounds[8..<12].map(\.maxY).max()!
        let restFloor=cellBounds[12..<16].map(\.maxY).max()!
        let offsets=(0..<16).map { $0<8 ? 0.0:$0<12 ? floor-idleFloor:floor-restFloor }
        union = .null
        for i in 0..<16 {union=union.union(cellBounds[i].offsetBy(dx:0,dy:offsets[i]))}
        let bounds=union.insetBy(dx:-2,dy:-2).intersection(CGRect(x:0,y:0,width:w,height:h)).integral
        let registered=cells.enumerated().compactMap { i,cell -> CGImage? in
            guard let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
            context.interpolationQuality = .none;context.draw(cell,in:CGRect(x:0,y:-offsets[i],width:CGFloat(w),height:CGFloat(h)));return context.makeImage()
        }
        // Quantize once at decode to a coherent logical pixel grid. Every frame
        // uses the same resolution; animation rendering allocates no new images.
        let pixelScale=80/max(bounds.width,bounds.height)
        let pixelWidth=max(1,Int((bounds.width*pixelScale).rounded())),pixelHeight=max(1,Int((bounds.height*pixelScale).rounded()))
        let frames=registered.compactMap { cell -> CGImage? in
            guard let crop=cell.cropping(to:bounds),let pixels=CGContext(data:nil,width:pixelWidth,height:pixelHeight,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
            pixels.interpolationQuality = .none;pixels.draw(crop,in:CGRect(x:0,y:0,width:pixelWidth,height:pixelHeight));return pixels.makeImage()
        }
        guard frames.count==16 else{return nil}
        let atlas=PixelAtlas(cells:cells,frames:frames,sharedBounds:bounds,cellSize:CGSize(width:w,height:h));cache[key]=atlas;return atlas
    }
    static func frameIndex(animal:String,motion m:CompanionMotion,reducedMotion:Bool=false,walkCycle:Double?=nil)->Int {
        if reducedMotion {return m.sleeping ? 14:8}
        let sleep=m.weight(.sleep)
        if sleep>0.12 || m.sleeping {
            if sleep<0.45 {return 12}
            if sleep<0.85 {return 13}
            return 14+Int(m.total*1.2)%2
        }
        if animal=="Dragon" {return Int(m.total*(abs(m.velocity)>0.002 ? 9:6))%8}
        if abs(m.velocity)>0.002 || m.weight(.walk)>0.12 {return Int((walkCycle ?? m.gait/(2 * .pi))*8)%8}
        let offset=Double((names[animal] ?? "").utf8.reduce(0){$0+Int($1)}%41)/10
        let blink=(m.total+offset).truncatingRemainder(dividingBy:5.3)
        if blink>4.98 && blink<5.10 {return 10}
        if blink>=5.10 && blink<5.22 {return 11}
        return 8+Int(m.total*(animal=="Cow" ? 0.75:1.0))%2
    }
    static func draw(animal:String,motion m:CompanionMotion,in rect:CGRect,reducedMotion:Bool=false) {
        guard let context=NSGraphicsContext.current?.cgContext,let atlas=rig(animal) else{return}
        let scale=min(rect.width*0.66/atlas.sharedBounds.width,rect.height*0.82/atlas.sharedBounds.height)
        let width=atlas.sharedBounds.width*scale,height=atlas.sharedBounds.height*scale
        let travelSpan=max(0,rect.width-width-8)
        let strideFraction=animal=="Rabbit" ? 0.20:animal=="Cow" ? 0.10:0.12
        let cycle=m.travelDistance*travelSpan/max(1,width*strideFraction)
        let frame=atlas.frames[frameIndex(animal:animal,motion:m,reducedMotion:reducedMotion,walkCycle:cycle)]
        let left=rect.minX+4+travelSpan*m.x
        let lift=reducedMotion ? 0:m.jump*min(14,rect.height*0.09)
        let bottom=rect.minY+max(5,rect.height*0.07)+lift
        context.saveGState();defer{context.restoreGState()}
        context.clip(to:rect);context.interpolationQuality = .none;context.setShouldAntialias(false)
        context.translateBy(x:(left+(m.facing<0 ? width:0)).rounded(),y:bottom.rounded())
        context.scaleBy(x:m.facing<0 ? -1:1,y:1)
        context.draw(frame,in:CGRect(x:0,y:0,width:width.rounded(),height:height.rounded()))
    }
    static func sheet(_ animal:String)->Sheet? {
        guard let atlas=rig(animal) else{return nil}
        return Sheet(frames:atlas.frames.map{NSImage(cgImage:$0,size:atlas.sharedBounds.size)},maximum:atlas.sharedBounds.size)
    }
}
