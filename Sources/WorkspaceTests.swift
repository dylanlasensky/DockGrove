import AppKit
import SwiftUI

@MainActor func runWorkspaceTests() throws {
    let screen=CGRect(x:-1440,y:-200,width:1440,height:900), visible=CGRect(x:-1440,y:-200,width:1440,height:870)
    for edge in ["Top","Bottom","Floating"] { for alignment in [0.0,0.5,1.0] { for height in [0.0,0.5,1.0] {
        let rect=DockGeometry.frame(size:CGSize(width:600,height:112),screen:screen,visible:visible,edge:edge,alignment:alignment,elevation:height,replacing:false)
        precondition(screen.contains(rect),"Dock escaped display")
        if edge == "Top" { precondition(rect.maxY == visible.maxY) }
    } } }
    let reserved=DockGeometry.reserve(visible,docks:[CGRect(x:-1400,y:-200,width:500,height:100),CGRect(x:-1300,y:570,width:500,height:100),CGRect(x:-1200,y:50,width:500,height:100)])
    precondition(reserved.minY == -100 && reserved.maxY == 570,"Edge reservations must ignore floating docks")
    for (point,placement) in [(CGPoint(x:-1440,y:100),WindowPlacement.left),(CGPoint(x:-1,y:100),.right),(CGPoint(x:-1440,y:699),.topLeft),(CGPoint(x:-1,y:-200),.bottomRight),(CGPoint(x:-700,y:699),.maximize),(CGPoint(x:-700,y:-200),.bottom)] {
        precondition(SnapZone.placement(at:point,screen:screen)==placement)
    }
    precondition(SnapZone.placement(at:CGPoint(x:-700,y:100),screen:screen)==nil)
    precondition(SnapZone.placement(at:CGPoint(x:50,y:100),screen:screen)==nil)
    var dwell=SnapDwell(); let now=Date()
    precondition(!dwell.ready("left",now:now)); precondition(dwell.ready("left",now:now.addingTimeInterval(0.2)))
    precondition(!dwell.ready("right",now:now.addingTimeInterval(0.21))); precondition(!dwell.ready(nil,now:now.addingTimeInterval(0.5)))
    for fraction in [CGFloat(0.35),0.5,1.0] { for width in [CGFloat(640),1440,2560] {
        let widths=ToolKind.allCases.map { DockEntry.tool($0).width(iconSize:64) }
        let configured=min(width,max((widths.max() ?? 236)+DockPageLayout.chrome+44,width*fraction))
        let capacity=DockPageLayout.bodyWidth(screenWidth:configured,naturalWidth:10000)-DockPageLayout.chrome
        for page in DockPageLayout.pages(widths:widths,available:capacity) { precondition(page.map { widths[$0] }.reduce(0,+)+CGFloat(max(0,page.count-1))*DockPageLayout.gap <= capacity) }
    } }
    var pet=CompanionState(); let baseline=pet.fullness; pet.advance(to:pet.lastUpdate.addingTimeInterval(86400*30)); precondition(pet.fullness >= baseline-0.4)
    for _ in 0..<20 { pet.feed(); pet.play() }; precondition(pet.fullness==100 && pet.joy==100 && pet.energy >= 25)
    pet.resting=true; let energy=pet.energy; pet.play(); precondition(pet.energy==energy)
    for _ in 0..<3 { pet.reward() }; precondition(pet.level==2 && pet.sessions==3)
    let restoredPet=try JSONDecoder().decode(CompanionState.self,from:JSONEncoder().encode(pet)); precondition(restoredPet == pet)
    let suite="WaveDock-workspace-tests-"+UUID().uuidString, defaults=UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let model=DockModel(defaults:defaults); model.theme="Pearl"; model.widthFraction=0.5; model.alignment=0; model.showUsageCard=false
    let restored=DockModel(defaults:defaults); precondition(restored.theme=="Pearl" && restored.widthFraction==0.5 && restored.alignment==0 && !restored.showUsageCard)
    let kit=model.toolkit; let sessions=kit.pet.state.sessions; kit.focusEnd=Date().addingTimeInterval(-1); kit.tickNow(); kit.tickNow(); precondition(kit.pet.state.sessions==sessions+1,"Reward exactly once")
    precondition(AlbumArtwork.allowed(URL(string:"https://i.scdn.co/image/sample")!))
    for url in ["http://i.scdn.co/image/sample","https://localhost/private","https://i.scdn.co.evil.example/x","file:///private/file"] { precondition(!AlbumArtwork.allowed(URL(string:url)!)) }
    precondition(AlbumArtwork.appleData(Data("«data JPEGFFD8FF»".utf8)) == Data([255,216,255]))
    precondition(AlbumArtwork.appleData(Data("«data JPEGxyz»".utf8)) == nil)
    precondition(AlbumArtwork.decode(Data("not an image".utf8)) == nil)
    let image=NSImage(size:NSSize(width:40,height:40),flipped:false) { rect in NSColor.systemBlue.setFill(); rect.fill(); return true }
    let png=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    let decoded=AlbumArtwork.decode(png); precondition(decoded != nil)
    let tint=NSColor(AlbumArtwork.tint(decoded!)).usingColorSpace(.sRGB)!
    precondition(max(tint.redComponent,tint.greenComponent,tint.blueComponent) <= 0.321, "Artwork must stay dark enough for white labels")
    let player=MusicPlayer(name:"Fixture",bundleID:"example.fixture"); player.artwork=image; player.disconnect(); precondition(player.artwork==nil)
    let track=try TrackSnapshot.decode(Data("playing\u{1e}Song\u{1e}Artist\u{1e}https://i.scdn.co/image/sample".utf8)); precondition(track.artworkReference.hasPrefix("https://"))
    print("PASS: snapping zones/dwell, negative-display dock positions, multi-edge reservations, narrow custom widths, theme persistence, pet care/focus reward, artwork validation")
}
