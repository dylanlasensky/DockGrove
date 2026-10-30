import AppKit
import AVFoundation
@main struct VerifyCompanionVideo {
    static func main() async throws {
        let url=URL(fileURLWithPath:CommandLine.arguments[1])
        let asset=AVURLAsset(url:url)
        let duration=try await asset.load(.duration)
        let track=try await asset.loadTracks(withMediaType:.video).first!
        let size=try await track.load(.naturalSize)
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output);guard reader.startReading() else { throw reader.error! }
        var count=0
        while let sample=output.copyNextSampleBuffer() {
            if count == 2730, let pixel=CMSampleBufferGetImageBuffer(sample) {
                let ci=CIImage(cvPixelBuffer:pixel)
                let cg=CIContext().createCGImage(ci,from:ci.extent)!
                try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:url.deletingLastPathComponent().appendingPathComponent("sequential-91.png"))
            }
            count+=1
        }
        guard reader.status == .completed else { throw reader.error! }
        precondition(count==5400 && abs(duration.seconds-180)<0.1)
        let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        for seconds in [0.0,37,91,166,177] {
            let image=try generator.copyCGImage(at:CMTime(seconds:seconds,preferredTimescale:600),actualTime:nil)
            let rep=NSBitmapImageRep(cgImage:image)
            try rep.representation(using:.png,properties:[:])!.write(to:url.deletingLastPathComponent().appendingPathComponent("decoded-\(Int(seconds)).png"))
        }
        print("PASS full H.264 decode: \(count) frames; \(duration.seconds) seconds; \(Int(size.width))×\(Int(size.height)); five decoded stills exported")
    }
}
