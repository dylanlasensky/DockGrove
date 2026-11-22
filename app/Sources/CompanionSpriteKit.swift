import AppKit
import SpriteKit

struct CompanionSceneRequest: Equatable {
    let id = UUID()
    var destination: Double
    var arrival: CompanionMotion.Activity = .look
}

struct CompanionSceneGeometry {
    let spriteSize: CGSize
    let travel: CGFloat
    let floor: CGFloat
    func x(at destination: Double) -> CGFloat { 4 + travel * destination + spriteSize.width / 2 }
}

/// Textures are decoded once and shared between the Dock and Settings previews.
final class CompanionSpriteScene: SKScene {
    private static var textureCache: [String: [SKTexture]] = [:]
    let sprite = SKSpriteNode()
    private(set) var motion = CompanionMotion()
    private(set) var frameIndex = 8
    var animal = "Miso" { didSet { if animal != oldValue { motion = CompanionMotion(seed: Self.seed(animal)); lastTime = nil; renderPose() } } }
    var resting = false
    var reducedMotion = false
    var playroom = false
    private var lastTime: TimeInterval?
    private var lastPlayRequest: Int?
    private var lastSceneRequest: UUID?
    static func seed(_ name: String) -> UInt64 { name.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }
    static func textures(for animal: String) -> [SKTexture] {
        if let cached = textureCache[animal] { return cached }
        guard let atlas = CompanionDrawing.rig(animal) else { return [] }
        let textures = atlas.frames.map { image -> SKTexture in
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            return texture
        }
        textureCache[animal] = textures
        return textures
    }
    static func geometry(for animal: String, size: CGSize, playroom: Bool) -> CompanionSceneGeometry? {
        guard let atlas = CompanionDrawing.rig(animal) else { return nil }
        let availableWidth = playroom ? min(220, size.width * 0.42) : size.width * 0.66
        let availableHeight = playroom ? min(190, size.height * 0.65) : size.height * 0.82
        let scale = min(availableWidth / atlas.sharedBounds.width, availableHeight / atlas.sharedBounds.height)
        let spriteSize = CGSize(width: (atlas.sharedBounds.width * scale).rounded(), height: (atlas.sharedBounds.height * scale).rounded())
        return CompanionSceneGeometry(spriteSize: spriteSize, travel: max(0, size.width - spriteSize.width - 8), floor: max(5, size.height * (playroom ? 0.20 : 0.07)))
    }
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(sprite)
        renderPose()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didChangeSize(_ oldSize: CGSize) { renderPose() }
    func resetClock() { lastTime = nil }
    func receivePlay(_ request: Int) {
        defer { lastPlayRequest = request }
        if let lastPlayRequest, request != lastPlayRequest, !resting { motion.play() }
    }
    func receive(_ request: CompanionSceneRequest?) {
        guard let request, request.id != lastSceneRequest else { return }
        lastSceneRequest = request.id
        guard !resting, !reducedMotion else { return }
        motion.move(to: request.destination, then: request.arrival)
    }
    override func update(_ currentTime: TimeInterval) {
        let delta = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        advance(delta)
    }
    func advance(_ delta: TimeInterval) {
        motion.advance(delta, animal: animal, resting: resting, reducedMotion: reducedMotion)
        renderPose()
    }
    private func renderPose() {
        let textures = Self.textures(for: animal)
        guard textures.count == 16, let geometry = Self.geometry(for: animal, size: size, playroom: playroom) else { sprite.isHidden = true; return }
        sprite.isHidden = false
        let stride = animal == "Rabbit" ? 0.20 : animal == "Cow" ? 0.10 : 0.12
        let cycle = motion.travelDistance * geometry.travel / max(1, geometry.spriteSize.width * stride)
        frameIndex = CompanionDrawing.frameIndex(animal: animal, motion: motion, reducedMotion: reducedMotion, walkCycle: cycle)
        sprite.texture = textures[frameIndex]
        sprite.size = geometry.spriteSize
        sprite.xScale = motion.facing < 0 ? -1 : 1
        // Keep the feet anchored; subtle breathing replaces mismatched idle poses.
        sprite.yScale = reducedMotion ? 1 : 1 + sin(motion.total * 1.8) * 0.008 * (1 - motion.weight(.walk))
        sprite.position = CGPoint(x: geometry.x(at: motion.x), y: geometry.floor + (reducedMotion ? 0 : motion.jump * min(14, size.height * 0.09)))
    }

    func destination(at x: CGFloat) -> Double {
        let travel = max(1, size.width - sprite.size.width - 8)
        return Double(min(0.88, max(0.12, (x - 4 - sprite.size.width / 2) / travel)))
    }
}

/// SpriteKit owns the display loop and GPU rendering; AppKit owns visibility.
final class CompanionStage: SKView {
    let companionScene = CompanionSpriteScene(size: CGSize(width: 250, height: 180))
    var animal: String { get { companionScene.animal } set { companionScene.animal = newValue } }
    var resting: Bool { get { companionScene.resting } set { companionScene.resting = newValue } }
    var onSelectDestination: ((Double) -> Void)?
    private var observers: [NSObjectProtocol] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        allowsTransparency = true
        ignoresSiblingOrder = true
        preferredFramesPerSecond = 60
        presentScene(companionScene)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshScene() })
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshScene() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, note.object as? NSWindow === self.window else { return }
            self.companionScene.resetClock()
            self.isPaused = true
        })
        isPaused = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshScene() }
    override func viewDidHide() { super.viewDidHide(); refreshScene() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshScene() }
    override func layout() { super.layout(); companionScene.size = bounds.size; refreshScene() }
    // The Dock stays decorative; only the dedicated room captures clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { onSelectDestination == nil ? nil : super.hitTest(point) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onSelectDestination != nil }
    override func mouseDown(with event: NSEvent) {
        onSelectDestination?(companionScene.destination(at: convert(event.locationInWindow, from: nil).x))
    }
    func receivePlay(_ request: Int) { companionScene.receivePlay(request) }
    func refreshScene() {
        companionScene.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        preferredFramesPerSecond = companionScene.reducedMotion ? 1 : 60
        // Floating Dock panels can remain visibly on screen while AppKit omits the
        // occlusion flag. Their own visibility is the authoritative hide signal.
        let visible = window.map { $0.isVisible && ($0.level > .normal || $0.occlusionState.contains(.visible)) } ?? false
        let pause = !visible || isHiddenOrHasHiddenAncestor
        if pause != isPaused { companionScene.resetClock() }
        isPaused = pause
        companionScene.advance(0)
    }
}
