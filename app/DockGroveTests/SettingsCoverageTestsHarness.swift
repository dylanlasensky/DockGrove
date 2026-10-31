import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

/// Hosts a SwiftUI view in an offscreen borderless window and drives it with synthesized
/// AppKit events. SwiftUI places a `KeyViewProxy` NSView over every focusable control, which
/// gives each button, toggle and disclosure triangle a clickable frame.
@MainActor final class SettingsHarness {
    let window: NSWindow
    let host: NSView
    private var menuGuard: NSObjectProtocol?
    init<V: View>(_ view: V, width: CGFloat = 1080, height: CGFloat = 1400) {
        // A synthesized click that lands on a pop-up or menu button starts modal menu tracking,
        // which waits for a real mouse forever. Cancel any menu the moment it opens.
        menuGuard = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            (note.object as? NSMenu)?.cancelTrackingWithoutAnimation()
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        let rooted = view.environment(\.openURL, OpenURLAction { _ in .handled })
        let hosting = NSHostingView(rootView: rooted)
        hosting.sizingOptions = []
        host = hosting
        window.contentView = host
        window.setFrame(NSRect(x: 0, y: 0, width: width, height: height), display: false)
        host.setFrameSize(NSSize(width: width, height: height))
        window.orderFrontRegardless()
        settle(0.2)
    }
    func close() {
        if let menuGuard { NotificationCenter.default.removeObserver(menuGuard) }
        menuGuard = nil
        window.makeFirstResponder(nil); window.orderOut(nil); window.contentView = nil
    }

    /// Lets SwiftUI apply updates, then draws: key-view proxies move to new control frames
    /// only when the hosting view displays.
    func settle(_ seconds: TimeInterval = 0.05) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
        host.display()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func views<T: NSView>(_ type: T.Type) -> [T] { descendants(host).compactMap { $0 as? T } }

    /// Focusable control frames in window coordinates, in reading order.
    func controls() -> [CGRect] {
        window.recalculateKeyViewLoop()
        return descendants(host).filter { String(describing: Swift.type(of: $0)) == "KeyViewProxy" && !$0.isHidden }
            .map { $0.convert($0.bounds, to: nil) }
            .filter { $0.width > 0 && $0.height > 0 }
            .sorted { abs($0.maxY - $1.maxY) > 2 ? $0.maxY > $1.maxY : $0.minX < $1.minX }
    }

    func send(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
        window.sendEvent(event)
    }
    func click(_ point: CGPoint) {
        send(.leftMouseDown, point)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        send(.leftMouseUp, point)
        settle(0.03)
    }
    func click(_ rect: CGRect) { click(CGPoint(x: rect.midX, y: rect.midY)) }
    /// Clicks every focusable control whose frame passes `filter`, re-reading frames after each click.
    /// Text fields are skipped: focusing one summons AutoFill, whose remote view outlives the window.
    func clickAll(from start: Int = 0, limit: Int = 400, filter: (CGRect) -> Bool = { _ in true }) {
        var index = start
        while index < limit {
            let fields = textFields().map { $0.convert($0.bounds, to: nil) }
            let frames = controls().filter { frame in filter(frame) && !fields.contains { $0.intersects(frame) } }
            guard index < frames.count else { return }
            click(frames[index]); index += 1
        }
    }
    /// Clicks a column of points; for controls without a key-view proxy, such as link buttons.
    func scan(x: CGFloat, from low: CGFloat, to high: CGFloat, step: CGFloat = 5) {
        var y = low
        while y <= high { click(CGPoint(x: x, y: y)); y += step }
    }
    func source(_ value: String) -> NativeStudioDragSource.SourceView? {
        views(NativeStudioDragSource.SourceView.self).first { $0.item?.value == value }
    }
    func drag(from start: CGPoint, to end: CGPoint, steps: Int = 4) {
        send(.leftMouseDown, start)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            send(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        send(.leftMouseUp, end); settle(0.02)
    }
    /// The context menu SwiftUI would show for a right click at `point` (window coordinates).
    func contextMenu(at point: CGPoint) -> NSMenu? {
        guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return nil }
        let local = host.convert(point, from: nil)
        return (host.hitTest(host.superview?.convert(local, from: host) ?? local) ?? host).menu(for: event)
    }
    /// Performs every item in a menu and its submenus, rebuilding the menu before each one.
    func performAllMenuItems(at point: CGPoint) {
        guard let menu = contextMenu(at: point) else { return }
        func paths(_ menu: NSMenu, _ prefix: [Int]) -> [[Int]] {
            menu.items.enumerated().flatMap { i, item -> [[Int]] in
                if let sub = item.submenu { return paths(sub, prefix + [i]) }
                return item.isSeparatorItem ? [] : [prefix + [i]]
            }
        }
        for path in paths(menu, []) {
            guard var current = contextMenu(at: point) else { continue }
            for i in path.dropLast() { guard current.items.indices.contains(i), let sub = current.items[i].submenu else { break }; current = sub }
            if let last = path.last, current.items.indices.contains(last) { current.performActionForItem(at: last) }
            settle(0.02)
        }
    }

    func textFields() -> [NSTextField] { views(NSTextField.self).filter { $0.isEditable } }
    /// Edits a field the way AppKit reports typing to SwiftUI, without making it first
    /// responder (which would summon password AutoFill for secure fields).
    func type(_ text: String, into field: NSTextField, submit: Bool = false) {
        field.stringValue = text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field, userInfo: ["NSFieldEditor": NSTextView()])
        settle(0.02)
        if submit, let action = field.action { NSApp.sendAction(action, to: field.target, from: field); settle(0.02) }
    }
    func segments() -> [NSSegmentedControl] { views(NSSegmentedControl.self) }
    func select(_ index: Int, in control: NSSegmentedControl) {
        control.selectedSegment = index
        if let action = control.action { NSApp.sendAction(action, to: control.target, from: control) }
        settle(0.02)
    }
}

/// A DockModel backed by its own UserDefaults suite, removed when the test ends.
@MainActor func makeSettingsModel(_ test: XCTestCase, purchasesEnabled: Bool = false, configure: (UserDefaults) -> Void = { _ in }) -> DockModel {
    let name = "SettingsCoverage." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defaults.set([], forKey: "apps"); defaults.set([], forKey: "widgets")
    defaults.set(false, forKey: "showRunning"); defaults.set(false, forKey: "showClock"); defaults.set(false, forKey: "showUsageCard")
    configure(defaults)
    test.addTeardownBlock { defaults.removePersistentDomain(forName: name) }
    let model = DockModel(defaults: defaults, purchasesEnabled: purchasesEnabled)
    // Live launches, panels, pasteboard, network and music scripting all fail or no-op, so a
    // stray click (control positions vary with fonts and display scale) can never block on a
    // modal panel or touch the real system. Tests that exercise one of these replace it.
    widgetsIsolate(model)
    model.fetchUsage = { _ in throw UsageError.service }
    return model
}

extension StudioAccess {
    static func fixed(features: Bool = true, tier: AccessTier, purchases: Bool = true) -> StudioAccess {
        StudioAccess(purchasesEnabled: purchases, canUseFeatures: { _ in features }, canAccess: { _, kind in features && tier >= kind.requiredAccess }, canAccessAI: { _ in features && tier == .full })
    }
}

/// A purchase store with fixed state. It never talks to StoreKit.
@MainActor final class SettingsFakePurchaseStore: PurchaseStore {
    @Published var tier: AccessTier = .free
    @Published var hasLoadedEntitlements = true
    @Published var loadingProducts = false
    @Published var busy = false
    @Published var message: String?
    @Published var prices: [AccessTier: String] = [:]
    private(set) var calls: [String] = []
    var hasAllProducts: Bool { prices.count == AccessTier.productIDs.count }
    func displayPrice(for tier: AccessTier) -> String? { prices[tier] }
    func load() async { calls.append("load") }
    func loadProducts() async { calls.append("loadProducts") }
    func purchase(_ requested: AccessTier) async { calls.append("purchase:" + requested.title) }
    func restore() async { calls.append("restore") }
}

