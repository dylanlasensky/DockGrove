import AppKit
import SpriteKit

/// Textures are decoded once and shared between the Dock and Settings previews.
final class CompanionSpriteScene: SKScene {
    private static var textureCache: [String: [SKTexture]] = [:]
    let sprite = SKSpriteNode()
    private(set) var motion = CompanionMotion()
    private(set) var frameIndex = 8
    var animal = "Miso" { didSet { if animal != oldValue { motion = CompanionMotion(seed: Self.seed(animal)); lastTime = nil; renderPose() } } }
    var resting = false
    var reducedMotion = false
    private var lastTime: TimeInterval?
    private var lastPlayRequest: Int?
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
        guard textures.count == 16, let atlas = CompanionDrawing.rig(animal) else { sprite.isHidden = true; return }
        sprite.isHidden = false
        let scale = min(size.width * 0.66 / atlas.sharedBounds.width, size.height * 0.82 / atlas.sharedBounds.height)
        let width = atlas.sharedBounds.width * scale, height = atlas.sharedBounds.height * scale
        let travel = max(0, size.width - width - 8)
        let stride = animal == "Rabbit" ? 0.20 : animal == "Cow" ? 0.10 : 0.12
        let cycle = motion.travelDistance * travel / max(1, width * stride)
        frameIndex = CompanionDrawing.frameIndex(animal: animal, motion: motion, reducedMotion: reducedMotion, walkCycle: cycle)
        sprite.texture = textures[frameIndex]
        sprite.size = CGSize(width: width.rounded(), height: height.rounded())
        sprite.xScale = motion.facing < 0 ? -1 : 1
        sprite.position = CGPoint(x: (4 + travel * motion.x + width / 2).rounded(), y: (max(5, size.height * 0.07) + (reducedMotion ? 0 : motion.jump * min(14, size.height * 0.09))).rounded())
    }
}

/// SpriteKit owns the display loop and GPU rendering; AppKit owns visibility.
final class CompanionStage: SKView {
    let companionScene = CompanionSpriteScene(size: CGSize(width: 250, height: 180))
    var animal: String { get { companionScene.animal } set { companionScene.animal = newValue } }
    var resting: Bool { get { companionScene.resting } set { companionScene.resting = newValue } }
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
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshScene() })
        }
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
    // The companion is decorative; the enclosing widget owns clicks and drags.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func receivePlay(_ request: Int) { companionScene.receivePlay(request) }
    func refreshScene() {
        companionScene.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        preferredFramesPerSecond = companionScene.reducedMotion ? 1 : 60
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        let pause = !visible || isHiddenOrHasHiddenAncestor
        if pause != isPaused { companionScene.resetClock() }
        isPaused = pause
        companionScene.advance(0)
    }
}
