import AppKit
import SpriteKit
@testable import DockGrove

@MainActor func runAssetCatalogTests(output: URL? = nil) throws {
    for name in ["DockGrove-icon", "DockGrove-mark", "DockGrove-wordmark", "DockGrove-brand-sheet"] {
        precondition(NSImage(named: name) != nil, "Missing catalog image: \(name)")
    }
    for icon in FontAwesomeIcon.allCases {
        precondition(NSImage(named: icon.assetName) != nil, "Missing Font Awesome vector: \(icon.assetName)")
    }
    precondition(Bundle.main.url(forResource: "FontAwesome-LICENSE", withExtension: "txt") != nil, "Missing Font Awesome attribution")
    precondition(Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil, "Missing compiled app icon")
    for pack in AccentPalette.packs {
        for name in pack.colors {
            precondition(NSColor(named: AccentPalette.assetName(name)) != nil, "Missing color \(name)")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    let color = NSColor(AccentPalette.color(name)).usingColorSpace(.sRGB)!
                    precondition(color.alphaComponent == 1 && color.redComponent.isFinite)
                }
            }
        }
    }
    if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    let view = SKView(frame: CGRect(x: 0, y: 0, width: 250, height: 180))
    view.allowsTransparency = true
    for animal in Companion.animals {
        precondition(CompanionArtwork.frames(animal).count == 6, "Missing legacy sheet")
        let textures = CompanionSpriteScene.textures(for: animal)
        precondition(textures.count == 16 && textures.allSatisfy { $0.filteringMode == .nearest })
        precondition(textures[0] === CompanionSpriteScene.textures(for: animal)[0], "Textures must be reused")
        let scene = CompanionSpriteScene(size: view.bounds.size)
        scene.animal = animal
        view.presentScene(scene)
        view.isPaused = true
        var frames = Set<Int>(), positions = Set<Int>()
        for _ in 0..<18000 {
            scene.advance(1.0 / 60)
            frames.insert(scene.frameIndex)
            positions.insert(Int(scene.sprite.position.x))
            let rect = scene.sprite.calculateAccumulatedFrame()
            precondition(rect.minX >= 0 && rect.maxX <= 251 && rect.minY >= 0 && rect.maxY <= 181, "Clipped sprite: \(animal)")
        }
        precondition(frames.count > 2 && positions.count > 2, "Companion does not animate: \(animal)")
        scene.reducedMotion = true
        scene.advance(0)
        let position = scene.sprite.position, total = scene.motion.total
        scene.advance(10)
        precondition(scene.sprite.position == position && scene.motion.total == total && scene.frameIndex == 8)
        scene.resting = true
        scene.advance(0)
        precondition(scene.frameIndex == 14, "Reduce Motion must reflect manual rest")
        scene.resting = false
        scene.advance(0)
        guard let image = view.texture(from: scene)?.cgImage() else { preconditionFailure("SpriteKit rendering unavailable") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        var ink = 0, clear = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            if alpha > 0.5 { ink += 1 } else if alpha < 0.01 { clear += 1 }
        } }
        precondition(ink > 50 && clear > 50, "Empty or opaque sprite rendering: \(animal)")
        if let output, let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: output.appendingPathComponent("sprite-\(CompanionDrawing.names[animal]!).png"))
        }
    }
    view.presentScene(nil)
    print("PASS: compiled app icon, 22 catalog images, \(FontAwesomeIcon.allCases.count) Font Awesome vectors and bundled attribution, \(AccentPalette.packs.reduce(0) { $0 + $1.colors.count }) palette colors in light/dark, nine SpriteKit renders, animation bounds, texture reuse, and Reduce Motion/rest")
}
