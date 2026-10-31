import AppKit
import SwiftUI
import ImageIO

enum AlbumArtwork {
    static func allowed(_ url:URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host=url.host?.lowercased() else { return false }
        return host == "i.scdn.co" || host == "mosaic.scdn.co" || host == "image-cdn-ak.spotifycdn.com"
    }
    static func decode(_ data:Data) -> NSImage? {
        guard data.count <= 2_000_000, let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:160,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
    }
    static func appleData(_ output:Data) -> Data? {
        let text=String(decoding:output,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        guard text.hasPrefix("«data "),text.hasSuffix("»") else { return nil }
        let raw=String(text.dropFirst(10).dropLast())
        guard raw.count <= 4_000_000, raw.count.isMultiple(of:2),raw.allSatisfy(\.isHexDigit) else { return nil }
        var data=Data(); var index=raw.startIndex
        while index < raw.endIndex { let next=raw.index(index,offsetBy:2); guard let byte=UInt8(raw[index..<next],radix:16) else { return nil }; data.append(byte); index=next }
        return data
    }
    static func tint(_ image:NSImage) -> Color {
        // Average the actual pixels, then constrain the background luminance for white text.
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:8,pixelsHigh:8,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0), let context=NSGraphicsContext(bitmapImageRep:bitmap) else { return Color(white:0.12) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
        image.draw(in:NSRect(x:0,y:0,width:8,height:8)); NSGraphicsContext.restoreGraphicsState()
        var r=0.0,g=0.0,b=0.0
        for y in 0..<8 { for x in 0..<8 { if let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) { r+=color.redComponent; g+=color.greenComponent; b+=color.blueComponent } } }
        return Color(red:r/64*0.32,green:g/64*0.32,blue:b/64*0.32)
    }
    static func fetch(_ url:URL, configuration:URLSessionConfiguration = .ephemeral) async throws -> Data {
        guard allowed(url) else { throw UsageError.service }
        let guardrail=ArtworkRedirectGuard()
        let session=URLSession(configuration:configuration,delegate:guardrail,delegateQueue:nil); defer { session.invalidateAndCancel() }
        var request=URLRequest(url:url); request.timeoutInterval=12
        let (bytes,response)=try await session.bytes(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.mimeType?.hasPrefix("image/") == true, response.expectedContentLength <= 2_000_000 else { throw UsageError.service }
        var data=Data()
        for try await byte in bytes { guard data.count < 2_000_000 else { throw UsageError.service }; data.append(byte) }
        return data
    }
}
private final class ArtworkRedirectGuard:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) { completionHandler(request.url.map(AlbumArtwork.allowed) == true ? request : nil) }
}
struct MusicArtworkView:View {
    @ObservedObject var player:MusicPlayer
    var size:CGFloat=44
    var body:some View {
        Group { if let image=player.artwork { Image(nsImage:image).resizable().scaledToFill() } else { ZStack { Color.primary.opacity(0.07); Image(systemName:"music.note").font(.system(size:size*0.4)).foregroundStyle(.secondary) } } }
            .frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:size*0.19)).accessibilityHidden(true)
    }
}
