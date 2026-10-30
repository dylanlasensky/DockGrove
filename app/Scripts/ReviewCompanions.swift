import AppKit
import AVFoundation

/// Compile with CompanionMotion.swift and CompanionDrawing.swift; exports the real
/// native renderer under a deterministic 180-second simulation, not a screen recording.
@main struct CompanionReview {
    static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1]:".build/companion-review")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        CompanionDrawing.assetDirectory=URL(fileURLWithPath:"Assets.xcassets/Companions")
        let names=["Miso","Black cat","Orange cat","Golden dog","Husky","Dragon","Cow","Rabbit","Fox"]
        var simulations=names.enumerated().map { CompanionMotion(seed:UInt64($0.offset+71)) }
        var activities=Array(repeating:Set<String>(),count:9)
        let width=960,height=720,fps=30,duration=180
        let url=root.appendingPathComponent("all-nine-companions.mp4")
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:3_000_000]])
        input.expectsMediaDataInRealTime=false
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        writer.add(input);guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime:.zero)
        // Keep the raster context stable so AppKit can reuse decoded image caches.
        // Each submitted encoder buffer remains independently owned by AVFoundation.
        let canvasRowBytes=width*4
        let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bitmapFormat:.alphaFirst,bytesPerRow:canvasRowBytes,bitsPerPixel:32)!
        let graphics=NSGraphicsContext(bitmapImageRep:canvas)!
        let ctx=graphics.cgContext
        ctx.scaleBy(x:0.8,y:0.8)
        for frameIndex in 0..<fps*duration {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:1_000_000) }
            try autoreleasepool {
                var pixel:CVPixelBuffer?;CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)
                let buffer=pixel!;CVPixelBufferLockBaseAddress(buffer,[])
                defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
                NSColor(calibratedWhite:0.12,alpha:1).setFill();NSRect(x:0,y:0,width:1200,height:900).fill()
                for (i,name) in names.enumerated() {
                    // Manual Rest occupies the final ten seconds, then each wakes.
                    let resting=frameIndex >= fps*165 && frameIndex < fps*175
                    simulations[i].advance(1.0/Double(fps),animal:name,resting:resting)
                    activities[i].insert(simulations[i].activity.rawValue)
                    let rect=CGRect(x:Double(i%3)*400+20,y:Double(2-i/3)*280+75,width:360,height:210)
                    CompanionDrawing.draw(animal:name,motion:simulations[i],in:rect)
                    (name as NSString).draw(at:CGPoint(x:rect.minX+20,y:rect.minY-18),withAttributes:[.foregroundColor:NSColor.white,.font:NSFont.systemFont(ofSize:18,weight:.semibold)])
                    ((name == "Dragon" && simulations[i].activity == .walk ? "fly" : name == "Dragon" && simulations[i].activity == .idle ? "hover" : simulations[i].activity.rawValue) as NSString).draw(at:CGPoint(x:rect.minX+210,y:rect.minY-18),withAttributes:[.foregroundColor:NSColor.lightGray,.font:NSFont.systemFont(ofSize:13)])
                }
                let time=Double(frameIndex)/Double(fps)
                (String(format:"DockGrove • Pixel pets • %.1f seconds",time) as NSString).draw(at:CGPoint(x:38,y:20),withAttributes:[.foregroundColor:NSColor.lightGray,.font:NSFont.systemFont(ofSize:15)])
                NSGraphicsContext.restoreGraphicsState()
                if frameIndex % (fps*30)==0,let image=ctx.makeImage() { let rep=NSBitmapImageRep(cgImage:image);try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("review-\(frameIndex/fps)s.png")) }
                let destination=CVPixelBufferGetBaseAddress(buffer)!,source=UnsafeMutableRawPointer(canvas.bitmapData!)
                let destinationRowBytes=CVPixelBufferGetBytesPerRow(buffer)
                for row in 0..<height {destination.advanced(by:row*destinationRowBytes).copyMemory(from:source.advanced(by:row*canvasRowBytes),byteCount:canvasRowBytes)}
                guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frameIndex),timescale:Int32(fps))) else { throw writer.error! }
            }
        }
        input.markAsFinished();await writer.finishWriting();guard writer.status == .completed else { throw writer.error! }
        for name in names {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:400,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            CompanionDrawing.draw(animal:name,motion:CompanionMotion(),in:CGRect(x:0,y:0,width:640,height:400))
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(CompanionDrawing.names[name]!+"-portrait.png"))
        }
        let report=names.enumerated().map { "\($0.element): \(activities[$0.offset].sorted().joined(separator:", "))" }.joined(separator:"\n")
        try report.write(to:root.appendingPathComponent("behaviors.txt"),atomically:true,encoding:.utf8)
        print("COMPLETE: \(url.path)\n\(report)")
    }
}
