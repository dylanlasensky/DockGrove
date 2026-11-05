import XCTest
import AppKit
import SwiftUI
import ApplicationServices
@testable import DockGrove

// MARK: - Fakes

/// In-memory Accessibility server. Elements are inert tokens; nothing reaches another process.
private final class WinFakeAX: @unchecked Sendable {
    private let lock = NSLock()
    private var attributes: [String: CFTypeRef] = [:]
    private var setQueues: [String: [AXError]] = [:]
    var trustedAnswers: [Bool] = []
    var trusted = true
    var prompts = 0
    var defaultSet: AXError = .success
    var performResult: AXError = .success
    var storeFrames = true
    var storeMinimized = true
    var sizeClamp: CGSize?
    var apps: [NSRunningApplication] = []
    var hit: AXUIElement?
    var pids: [String: pid_t] = [:]
    var runningApp: NSRunningApplication?
    var activations = 0
    var pauses = 0
    var timeouts: [Float] = []

    func key(_ element: AXUIElement, _ attribute: String) -> String { "\(CFHash(element)):\(attribute)" }
    func put(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef?) {
        lock.lock(); defer { lock.unlock() }
        attributes[key(element, attribute)] = value
    }
    func get(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        lock.lock(); defer { lock.unlock() }
        return attributes[key(element, attribute)]
    }
    func queue(_ attribute: String, _ results: [AXError]) {
        lock.lock(); defer { lock.unlock() }
        setQueues[attribute] = results
    }
    func frame(_ element: AXUIElement, _ rect: CGRect) {
        put(element, kAXPositionAttribute, winPoint(rect.origin))
        put(element, kAXSizeAttribute, winSize(rect.size))
    }
    private func nextSet(_ attribute: String) -> AXError {
        lock.lock(); defer { lock.unlock() }
        if var queued = setQueues[attribute], !queued.isEmpty {
            let result = queued.removeFirst(); setQueues[attribute] = queued; return result
        }
        return defaultSet
    }
    func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        let result = nextSet(attribute)
        guard result == .success else { return result }
        if attribute == kAXMinimizedAttribute && !storeMinimized { return result }
        if attribute == kAXSizeAttribute || attribute == kAXPositionAttribute {
            guard storeFrames else { return result }
            if attribute == kAXSizeAttribute, let clamp = sizeClamp { put(element, attribute, winSize(clamp)); return result }
        }
        put(element, attribute, value)
        return result
    }
    func isTrusted() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !trustedAnswers.isEmpty { return trustedAnswers.removeFirst() }
        return trusted
    }
    var client: AccessibilityClient {
        var c = AccessibilityClient()
        c.isTrusted = { [unowned self] in self.isTrusted() }
        c.promptForTrust = { [unowned self] in self.prompts += 1 }
        c.application = { winElement($0) }
        c.systemWide = { winElement(1) }
        c.setTimeout = { [unowned self] _, value in self.timeouts.append(value) }
        c.copy = { [unowned self] in self.get($0, $1) }
        c.set = { [unowned self] in self.set($0, $1, $2) }
        c.perform = { [unowned self] _, _ in self.performResult }
        c.element = { [unowned self] _, _ in self.hit }
        c.pid = { [unowned self] element in self.pids["\(CFHash(element))"] ?? 0 }
        c.runningApplications = { [unowned self] in self.apps }
        c.runningApplication = { [unowned self] _ in self.runningApp }
        c.activate = { [unowned self] _ in self.activations += 1 }
        c.pause = { [unowned self] _ in self.pauses += 1 }
        return c
    }
}

private func winElement(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }
private func winPoint(_ point: CGPoint) -> AXValue { var p = point; return AXValueCreate(.cgPoint, &p)! }
private func winSize(_ size: CGSize) -> AXValue { var s = size; return AXValueCreate(.cgSize, &s)! }
private var winFinder: NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
}

@MainActor private func winWait(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
}
@MainActor private func winSettle(_ seconds: TimeInterval = 0.1) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

/// SwiftUI only builds its accessibility tree once an accessibility client has talked to
/// the process; a read-only query of our own application element is enough.
private func winWakeAccessibility() async {
    let pid = getpid()
    await Task.detached {
        let own = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(own, 1)
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(own, kAXChildrenAttribute as CFString, &value)
    }.value
}

/// Walks the accessibility tree of a hosted SwiftUI view and presses buttons matching `label`
/// (or every button when nil). Returns the number of presses.
@MainActor @discardableResult func winPress(_ view: NSView, _ label: String? = nil) -> Int {
    var presses = 0
    func visit(_ element: Any, depth: Int) {
        guard depth < 50, let object = element as? NSObject else { return }
        if object.responds(to: #selector(NSAccessibilityProtocol.accessibilityRole)),
           (object.value(forKey: "accessibilityRole") as? NSAccessibility.Role) == .button {
            let names = ["accessibilityLabel", "accessibilityTitle"].compactMap { key -> String? in
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) as? String : nil
            }
            if label == nil || names.contains(label!),
               object.responds(to: #selector(NSAccessibilityProtocol.accessibilityPerformPress)) {
                _ = object.perform(#selector(NSAccessibilityProtocol.accessibilityPerformPress)); presses += 1
            }
        }
        if object.responds(to: #selector(NSAccessibilityProtocol.accessibilityChildren)),
           let children = object.perform(#selector(NSAccessibilityProtocol.accessibilityChildren))?.takeUnretainedValue() as? [Any] {
            for child in children { visit(child, depth: depth + 1) }
        }
    }
    visit(view, depth: 0)
    return presses
}

// MARK: - WindowManager / WindowFrameWriter

@MainActor final class CoreCoverageTestsWindows: XCTestCase {
    private var fake: WinFakeAX!
    private var saved: AccessibilityClient!
    private var windows: [NSWindow] = []

    override func setUp() async throws {
        await winWakeAccessibility()
        saved = AccessibilityClient.current
        fake = WinFakeAX()
        AccessibilityClient.current = fake.client
    }
    override func tearDown() async throws {
        AccessibilityClient.current = saved
        for window in windows { window.orderOut(nil); window.close() }
        windows = []
    }

    private func model() -> DockModel { DockModel(defaults: UserDefaults(suiteName: "core.windows." + UUID().uuidString)!) }

    private func managed(_ pid: pid_t, frame: CGRect?) throws -> ManagedWindow {
        let element = winElement(pid)
        if let frame { fake.frame(element, frame) }
        let owner = try XCTUnwrap(winFinder)
        return ManagedWindow(id: "w\(pid)", owner: owner, element: element, title: "Window \(pid)")
    }

    @discardableResult private func host<V: View>(_ view: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        windows.append(window)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    func testLiveClientsAreInertAgainstOwnProcess() async throws {
        let client = saved!
        _ = client.isTrusted()
        let pid = getpid()
        let result = await Task.detached { () -> (pid_t, Bool) in
            let own = client.application(pid)
            client.setTimeout(own, 0.2)
            let system = client.systemWide()
            _ = system
            _ = client.copy(own, "AXDockGroveCoverageProbe")
            _ = client.set(own, "AXDockGroveCoverageProbe", kCFBooleanFalse)
            _ = client.perform(own, "AXDockGroveCoverageProbe")
            _ = client.element(own, CGPoint(x: -50_000, y: -50_000))
            client.pause(0)
            return (client.pid(own), client.runningApplications().isEmpty)
        }.value
        XCTAssertEqual(result.0, pid)
        XCTAssertFalse(result.1)
        XCTAssertEqual(client.runningApplication(pid)?.processIdentifier, pid)
        client.activate(NSRunningApplication.current)

        let input = SnapInput()
        _ = input.buttons(); _ = input.location(); _ = input.modifiers()
        XCTAssertFalse(input.screens().isEmpty)
        if let monitor = input.addKeyMonitor({ _ in }) { input.removeMonitor(monitor) }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { $0 }
        if let local { input.removeMonitor(local) }
    }

    func testPlacementAndZoneTables() {
        let usable = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for placement in DockGrove.WindowPlacement.allCases {
            XCTAssertTrue(usable.contains(placement.frame(in: usable, current: CGRect(x: 0, y: 0, width: 2000, height: 300))))
        }
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let cases: [(CGPoint, DockGrove.WindowPlacement?)] = [
            (CGPoint(x: 5, y: 790), .topLeft), (CGPoint(x: 995, y: 790), .topRight),
            (CGPoint(x: 5, y: 10), .bottomLeft), (CGPoint(x: 995, y: 10), .bottomRight),
            (CGPoint(x: 5, y: 400), .left), (CGPoint(x: 995, y: 400), .right),
            (CGPoint(x: 500, y: 795), .maximize), (CGPoint(x: 500, y: 5), .bottom),
            (CGPoint(x: 500, y: 400), nil), (CGPoint(x: -50, y: 400), nil)]
        for (point, expected) in cases { XCTAssertEqual(SnapZone.placement(at: point, screen: screen), expected) }
        let model = model()
        model.rememberApps(); model.apps = []
        model.undoAppChange(); model.undoAppChange()
    }

    func testHelpersAndPlacementGeometry() {
        XCTAssertEqual(WindowManager.windowTitle(app: nil, window: nil, fallback: "Window"), "App · Window")
        XCTAssertEqual(WindowManager.windowTitle(app: "Mail", window: "Inbox", fallback: "x"), "Mail · Inbox")
        XCTAssertEqual(WindowManager.globalTop([]), 0)
        XCTAssertEqual(WindowManager.globalTop(), NSScreen.screens.first?.frame.maxY ?? 0)
        XCTAssertEqual(DockGrove.WindowPlacement.left.id, "Left half")
        let screen = NSScreen.screens[0]
        let usable = WindowManager.usableFrame(screen: screen, dockHeight: 40)
        XCTAssertGreaterThanOrEqual(usable.height, 100)
    }

    func testRefreshDiscoversAndHandlesPermission() async throws {
        let manager = WindowManager()
        fake.trusted = false
        manager.refresh()
        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertTrue(manager.status.contains("required"))
        XCTAssertFalse(manager.trusted)
        manager.requestAccess()
        XCTAssertEqual(fake.prompts, 1)

        let finder = try XCTUnwrap(winFinder)
        let other = NSWorkspace.shared.runningApplications.first { $0.processIdentifier != finder.processIdentifier && $0 != .current }
        fake.apps = [NSRunningApplication.current, finder] + (other.map { [$0] } ?? [])
        let app = winElement(finder.processIdentifier)
        let w1 = winElement(70001), w2 = winElement(70002), w3 = winElement(70003), w4 = winElement(70004)
        fake.put(app, kAXWindowsAttribute, [w1, w2, w3, w4] as CFArray)
        fake.put(w1, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString); fake.put(w1, kAXTitleAttribute, "Beta" as CFString)
        fake.put(w2, kAXSubroleAttribute, kAXDialogSubrole as CFString); fake.put(w2, kAXTitleAttribute, "" as CFString)
        fake.put(w1, kAXMinimizedAttribute, kCFBooleanTrue)
        fake.put(w4, kAXSubroleAttribute, "AXFloatingWindow" as CFString)
        fake.trusted = true
        manager.refresh()
        manager.refresh() // ignored while loading
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertEqual(manager.windows.filter { $0.isMinimized }.count, 1)
        XCTAssertTrue(manager.windows.contains { $0.title.hasSuffix("Untitled window") })
        XCTAssertEqual(manager.selectedID, manager.windows.first?.id)
        XCTAssertNotNil(manager.selected)
        let kept = manager.windows[1].id
        manager.selectedID = kept
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.selectedID, kept)

        fake.apps = []
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.selectedID, "")
        XCTAssertTrue(manager.status.hasPrefix("No accessible windows"))

        fake.trustedAnswers = [true, false]
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertTrue(manager.status.contains("removed"))
    }

    func testDiscoveryBudgetsAndScopedHoverCache() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier), element = winElement(70100)
        fake.put(app, kAXWindowsAttribute, [element] as CFArray)
        fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString)
        fake.put(element, kAXTitleAttribute, "Budget" as CFString)
        // Expiration is checked before each potentially slow attribute request.
        for values in [[0.0, 4], [0, 0, 4], [0, 0, 0, 4], [0, 0, 0, 0, 4]] {
            var times = values
            var client = fake.client
            client.uptime = { times.count > 1 ? times.removeFirst() : times[0] }
            let result = WindowManager.discover(using: client)
            XCTAssertTrue(result.partial)
        }
        var now = 0.0
        var client = fake.client; client.uptime = { now }
        AccessibilityClient.current = client
        let manager = WindowManager()
        let other = ManagedWindow(id: "other", owner: .current, element: winElement(70101), title: "Other")
        manager.windows = [other]
        manager.refreshIfNeeded(for: finder)
        manager.refreshIfNeeded(for: finder) // one scan per app, even during the same hover
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertTrue(manager.windows.contains { $0.id == "other" })
        manager.refreshIfNeeded(for: finder)
        XCTAssertFalse(manager.loading)
        now = 4
        manager.refreshIfNeeded(for: finder)
        XCTAssertTrue(manager.loading)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2)
        var times = [0.0, 4]
        client.uptime = { times.count > 1 ? times.removeFirst() : times[0] }
        AccessibilityClient.current = client
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertTrue(manager.status.contains("took too long"))
        XCTAssertEqual(manager.windows.count, 2, "Partial scans retain known windows")
    }

    func testCancelledDiscoveryCannotOverwriteNewerState() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let started = expectation(description: "Background discovery started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var client = fake.client
        client.copy = { _, _ in
            XCTAssertFalse(Thread.isMainThread)
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return nil
        }
        AccessibilityClient.current = client
        let manager = WindowManager()
        manager.refresh()
        await fulfillment(of: [started], timeout: 2)
        manager.cancelDiscovery()
        manager.status = "Newer action"
        release.signal()
        await winSettle()
        XCTAssertFalse(manager.loading)
        XCTAssertEqual(manager.status, "Newer action")
        // A cancelled worker also stops before issuing any new AX calls.
        let task = Task.detached { () -> WindowManager.WindowDiscovery in
            while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.001) }
            return WindowManager.discover(using: client)
        }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.partial)
    }

    func testScanCancellationCannotUnlockAnArrangement() async throws {
        let manager = WindowManager(), window = try managed(70103, frame: CGRect(x: 10, y: 20, width: 300, height: 300))
        manager.windows = [window]; manager.selectedID = window.id
        fake.storeFrames = false
        let started = expectation(description: "Arrangement settling")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var first = true
        var client = fake.client
        client.pause = { _ in
            if first { first = false; started.fulfill(); _ = release.wait(timeout: .now() + 2) }
        }
        AccessibilityClient.current = client
        manager.place(.left)
        await fulfillment(of: [started], timeout: 2)
        manager.cancelDiscovery() // shelf dismissal only cancels discovery
        XCTAssertTrue(manager.loading)
        let focused = await manager.focus()
        XCTAssertFalse(focused)
        await manager.minimize()
        manager.undoPlacement()
        XCTAssertTrue(manager.loading)
        XCTAssertNil(fake.get(window.element, kAXMinimizedAttribute))
        manager.selectedID = "another selection"
        release.signal()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.selectedID, "another selection")
    }

    func testFocusLeavesMainActorResponsiveAndRechecksPermission() async throws {
        let manager = WindowManager(), window = try managed(70102, frame: nil)
        manager.windows = [window]; manager.selectedID = window.id
        let started = expectation(description: "Background focus started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var client = fake.client
        client.copy = { _, _ in
            XCTAssertFalse(Thread.isMainThread)
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return kCFBooleanFalse
        }
        AccessibilityClient.current = client
        let action = Task { await manager.focus() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(manager.acting)
        let duplicate = await manager.focus()
        XCTAssertFalse(duplicate)
        await manager.minimize()
        manager.refresh()
        manager.refreshIfNeeded(for: window.owner)
        XCTAssertFalse(manager.loading)
        fake.trusted = false
        release.signal()
        let result = await action.value
        XCTAssertFalse(result)
        XCTAssertFalse(manager.acting)
        XCTAssertTrue(manager.status.contains("removed"))
        XCTAssertEqual(fake.activations, 0)
    }

    func testPlaceSnapUndoAndArrangeResults() async throws {
        let manager = WindowManager()
        manager.place(.left)
        XCTAssertTrue(manager.status.hasPrefix("Window unavailable"))

        let window = try managed(71001, frame: CGRect(x: 10, y: 40, width: 500, height: 400))
        manager.windows = [window]; manager.selectedID = window.id
        fake.put(window.element, "AXFullScreen", kCFBooleanTrue)
        manager.place(.left)
        XCTAssertTrue(manager.status.hasPrefix("Leave native full screen"))
        fake.put(window.element, "AXFullScreen", kCFBooleanFalse)

        manager.place(.left, dockHeight: 30)
        XCTAssertGreaterThan(fake.activations, 0)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.status, "Window arranged. Undo is available.")

        manager.usableFrameProvider = { _ in CGRect(x: 0, y: 0, width: 1000, height: 800) }
        fake.sizeClamp = CGSize(width: 900, height: 900)
        manager.place(.right)
        await winWait { !manager.loading }
        XCTAssertTrue(manager.status.hasPrefix("This app limits its window to 900 × 900"))

        fake.sizeClamp = nil
        fake.defaultSet = .cannotComplete
        manager.place(.top)
        await winWait { !manager.loading }
        XCTAssertTrue(manager.status.hasPrefix("The app refused"))
        fake.defaultSet = .success

        manager.undoPlacement()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.status, "Previous layout restored.")
        manager.undoPlacement()
        XCTAssertEqual(manager.status, "No previous layout for this window.")

        let dragged = try managed(71002, frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        fake.trusted = false
        manager.snap(dragged, target: CGRect(x: 0, y: 0, width: 200, height: 200), original: .zero)
        XCTAssertEqual(manager.windows.count, 1)
        fake.trusted = true
        manager.snap(dragged, target: CGRect(x: 0, y: 0, width: 200, height: 200), original: CGRect(x: 0, y: 0, width: 300, height: 300))
        manager.snap(dragged, target: .zero, original: .zero) // ignored while loading
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertEqual(manager.selectedID, dragged.id)
        manager.snap(dragged, target: CGRect(x: 0, y: 0, width: 250, height: 250), original: .zero)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2)
    }

    func testFocusAndMinimize() async throws {
        let manager = WindowManager()
        await manager.minimize()
        await manager.focus()
        XCTAssertEqual(manager.status, "Select a window first.")
        fake.trusted = false
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("Allow Accessibility"))
        fake.trusted = true
        let window = try managed(72001, frame: nil)
        manager.windows = [window]; manager.selectedID = window.id
        await manager.focus()
        XCTAssertEqual(manager.status, "Window brought forward.")
        XCTAssertEqual(fake.timeouts.last, 0.5, "busy windows have bounded Accessibility calls")
        fake.queue(kAXMinimizedAttribute, [.attributeUnsupported])
        await manager.focus()
        XCTAssertEqual(manager.status, "Window brought forward.")
        fake.queue(kAXMinimizedAttribute, [.failure])
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
        fake.performResult = .failure
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
        manager.status = ""
        await manager.minimize()
        XCTAssertEqual(manager.status, "Window minimized.")
        XCTAssertEqual(fake.timeouts.last, 0.5)
        fake.queue(kAXMinimizedAttribute, [.failure])
        await manager.minimize()
        XCTAssertEqual(manager.status, "This window cannot be minimized.")
    }

    func testWindowShelfFiltersAndPermissionRevocation() async throws {
        XCTAssertEqual(AppIndexYAML.decode("apps:\n  - name: \"Unterminated\n    path: /Apps/U.app\n").first?.name, "")
        let window = try managed(72901, frame: nil)
        var minimized = window
        minimized.isMinimized = true
        for candidate in [window, minimized] { XCTAssertTrue(WindowShelfFilter.all.includes(candidate)) }
        XCTAssertTrue(WindowShelfFilter.open.includes(window))
        XCTAssertFalse(WindowShelfFilter.open.includes(minimized))
        XCTAssertTrue(WindowShelfFilter.minimized.includes(minimized))
        XCTAssertFalse(WindowShelfFilter.minimized.includes(window))
        let manager = WindowManager()
        manager.windows = [window]; manager.selectedID = window.id
        fake.trusted = false
        await manager.minimize()
        XCTAssertNil(fake.get(window.element, kAXMinimizedAttribute))
        XCTAssertEqual(fake.activations, 0)
        XCTAssertTrue(manager.status.contains("Allow Accessibility"))
    }

    func testRestoreConfirmsStateWhenRaiseFails() async throws {
        let manager = WindowManager()
        var window = try managed(72903, frame: nil)
        window.isMinimized = true
        manager.windows = [window]; manager.selectedID = window.id
        fake.performResult = .cannotComplete
        fake.put(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
        await manager.focus()
        XCTAssertEqual(fake.get(window.element, kAXMinimizedAttribute) as? Bool, false)
        XCTAssertEqual(manager.status, "Window restored.")

        // An app can acknowledge a write without changing its state. Do not claim success.
        fake.storeMinimized = false
        fake.put(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
        fake.put(window.element, kAXMinimizedAttribute, nil)
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
        fake.queue(kAXMinimizedAttribute, [.cannotComplete])
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
    }

    func testRestoreUsesCurrentMinimizedStateAfterDockAction() async throws {
        let manager = WindowManager()
        let window = try managed(72904, frame: nil)
        manager.windows = [window]; manager.selectedID = window.id
        XCTAssertFalse(manager.selected!.isMinimized)
        await manager.minimize()
        XCTAssertEqual(fake.get(window.element, kAXMinimizedAttribute) as? Bool, true)
        fake.performResult = .cannotComplete
        await manager.focus()
        XCTAssertEqual(fake.get(window.element, kAXMinimizedAttribute) as? Bool, false)
        XCTAssertEqual(manager.status, "Window restored.")

        // A stale 'minimized' snapshot must not claim a new restore for an already-open window.
        var stale = window; stale.isMinimized = true
        manager.windows = [stale]
        await manager.focus()
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
    }

    func testWindowShelfPermissionAndEmptyStates() async throws {
        let manager = WindowManager()
        fake.trusted = false
        var dismissed = 0
        let denied = host(WindowShelfView(manager: manager) { dismissed += 1 })
        await winSettle()
        XCTAssertGreaterThan(winPress(denied, "Allow Accessibility"), 0)
        XCTAssertGreaterThan(fake.prompts, 0)
        XCTAssertGreaterThan(winPress(denied, "Done"), 0)
        XCTAssertEqual(dismissed, 1)
        fake.trusted = true
        let empty = host(WindowShelfView(manager: manager) { dismissed += 1 })
        await winWait { !manager.loading }
        await winSettle()
        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertGreaterThan(winPress(empty, "Refresh windows"), 0)
        let button = host(WindowShelfButton(manager: manager, enabled: true))
        await winSettle()
        XCTAssertGreaterThan(winPress(button, "Open and minimized windows"), 0)
    }

    func testWindowShelfRestoresAListedWindow() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier), element = winElement(72902)
        fake.put(app, kAXWindowsAttribute, [element] as CFArray)
        fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString)
        fake.put(element, kAXTitleAttribute, "Shelf restore fixture" as CFString)
        fake.put(element, kAXMinimizedAttribute, kCFBooleanTrue)
        fake.performResult = .cannotComplete
        let manager = WindowManager()
        var dismissed = 0
        let view = host(WindowShelfView(manager: manager) { dismissed += 1 })
        await winWait { !manager.loading && !manager.windows.isEmpty }
        await winSettle(0.3)
        XCTAssertEqual(manager.windows.count, 1)
        let label = manager.windows[0].title + ", minimized. Restore window"
        XCTAssertGreaterThan(winPress(view, label), 0)
        await winWait { dismissed == 1 }
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(manager.status, "Window restored.")
        XCTAssertEqual(fake.get(element, kAXMinimizedAttribute) as? Bool, false)
        XCTAssertGreaterThan(fake.activations, 0)
        fake.performResult = .success
        manager.refresh()
        await winWait { !manager.loading }
        await winSettle(0.3)
        XCTAssertFalse(manager.windows[0].isMinimized)
        XCTAssertGreaterThan(winPress(view, manager.windows[0].title + ", open. Restore window"), 0)
        await winSettle()
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? view.subviews.flatMap(fields)
        }
        let field = try XCTUnwrap(fields(view).first)
        func enter(_ query: String) {
            field.stringValue = query
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        for query in ["fixture", "  fixture  ", "fíxture", "ＦＩＸＴＵＲＥ", "   "] {
            enter(query)
            await winSettle()
            XCTAssertGreaterThan(winPress(view, manager.windows[0].title + ", open. Restore window"), 0, query)
            await winSettle()
        }
        enter("no window matches this query")
        await winSettle()
        XCTAssertEqual(winPress(view, manager.windows[0].title + ", open. Restore window"), 0)
        enter("")
        await winSettle()
    }

    func testFrameWriterApply() {
        let window = winElement(73001), pid: pid_t = 73999
        let app = winElement(pid)
        let target = CGRect(x: 20, y: 30, width: 400, height: 300)
        fake.put(app, "AXEnhancedUserInterface", kCFBooleanTrue)
        // First size write fails, the second succeeds: still accepted.
        fake.queue(kAXSizeAttribute, [.failure, .success])
        guard case .arranged = WindowFrameWriter.apply(target, window: window, pid: pid) else { return XCTFail("not arranged") }
        XCTAssertEqual(fake.get(app, "AXEnhancedUserInterface") as? Bool, true)

        fake.put(app, "AXEnhancedUserInterface", nil)
        fake.sizeClamp = CGSize(width: 100, height: 100)
        guard case .constrained(let actual) = WindowFrameWriter.apply(target, window: window, pid: pid) else { return XCTFail("not constrained") }
        XCTAssertEqual(actual.size, CGSize(width: 100, height: 100))
        XCTAssertGreaterThan(fake.pauses, 0)

        fake.sizeClamp = nil
        fake.queue(kAXPositionAttribute, [.failure, .failure, .failure])
        fake.storeFrames = false
        guard case .unavailable = WindowFrameWriter.apply(CGRect(x: 1, y: 1, width: 2, height: 2), window: window, pid: pid) else { return XCTFail("not unavailable") }

        // Wrong AXValue types are rejected.
        let odd = winElement(73002)
        fake.put(odd, kAXPositionAttribute, winSize(.zero)); fake.put(odd, kAXSizeAttribute, winPoint(.zero))
        XCTAssertNil(WindowManager.bounds(odd))
        fake.put(odd, kAXPositionAttribute, "x" as CFString)
        XCTAssertNil(WindowManager.bounds(odd))
        XCTAssertNil(WindowManager.bounds(winElement(73003)))
    }

    func testWindowManagerViewStates() async throws {
        let model = model()
        let manager = model.toolkit.windows
        fake.trusted = false
        let untrusted = host(WindowManagerView(manager: manager, model: model))
        winPress(untrusted, "Allow Accessibility")
        XCTAssertEqual(fake.prompts, 1)

        fake.trusted = true
        let window = try managed(74001, frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        fake.apps = []
        let view = host(WindowManagerView(manager: manager, model: model))
        await winWait { !manager.loading }
        manager.windows = [window]; manager.selectedID = window.id
        model.replacingDock = true; model.toolkit.autoHide = false
        manager.displayIndex = min(max(0, model.toolkit.screenIndex), NSScreen.screens.count - 1)
        view.layoutSubtreeIfNeeded()
        await winSettle()
        view.layoutSubtreeIfNeeded()
        for label in ["Left half", "Focus", "Minimize", "Undo layout"] {
            await winWait { !manager.loading }
            view.layoutSubtreeIfNeeded()
            winPress(view, label)
        }
        await winWait { !manager.loading }
        model.replacingDock = false
        view.layoutSubtreeIfNeeded()
        winPress(view, "Right half")
        await winWait { !manager.loading }
        winPress(view, "Refresh windows")
        manager.loading = true
        view.layoutSubtreeIfNeeded()
        await winWait { !manager.loading }
        manager.loading = false
    }
}

// MARK: - WindowSnapper

@MainActor final class CoreCoverageTestsWindowsSnapper: XCTestCase {
    private var fake: WinFakeAX!
    private var saved: AccessibilityClient!
    private var buttons = 0
    private var location = CGPoint.zero
    private var modifiers: NSEvent.ModifierFlags = []
    private var screens: [NSScreen] = NSScreen.screens
    private var keyHandler: ((NSEvent) -> Void)?
    private var removed = 0

    override func setUp() async throws {
        await winWakeAccessibility()
        saved = AccessibilityClient.current
        fake = WinFakeAX()
        AccessibilityClient.current = fake.client
    }
    override func tearDown() async throws { AccessibilityClient.current = saved }

    private var input: SnapInput {
        var input = SnapInput()
        input.buttons = { [unowned self] in self.buttons }
        input.location = { [unowned self] in self.location }
        input.modifiers = { [unowned self] in self.modifiers }
        input.screens = { [unowned self] in self.screens }
        input.addKeyMonitor = { [unowned self] handler in self.keyHandler = handler; return NSObject() }
        input.removeMonitor = { [unowned self] _ in self.removed += 1 }
        return input
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: code)!
    }

    /// Prepares a fake title-bar hit at the left edge of the primary screen.
    private func prepareWindow(pid: pid_t) throws -> AXUIElement {
        let screen = NSScreen.screens[0].frame
        location = CGPoint(x: screen.minX + 5, y: screen.midY)
        let axY = WindowManager.globalTop() - location.y
        let element = winElement(pid)
        fake.hit = element
        fake.put(element, kAXRoleAttribute, kAXWindowRole as CFString)
        fake.pids["\(CFHash(element))"] = 4242
        fake.runningApp = try XCTUnwrap(winFinder)
        fake.frame(element, CGRect(x: 300, y: axY - 10, width: 600, height: 400))
        return element
    }

    func testStartKeyMonitorTimerAndDeinit() async throws {
        let model = DockModel(defaults: UserDefaults(suiteName: "core.snap." + UUID().uuidString)!)
        var snapper: WindowSnapper? = WindowSnapper(model: model, input: input)
        snapper?.start()
        XCTAssertNotNil(keyHandler)
        snapper?.timer?.fire()
        keyHandler?(key(0))
        keyHandler?(key(53))
        await winSettle()
        snapper?.timer?.invalidate()
        snapper = nil
        XCTAssertEqual(removed, 1)
    }

    func testDragToEdgePreviewsAndSnaps() async throws {
        let model = DockModel(defaults: UserDefaults(suiteName: "core.snap." + UUID().uuidString)!)
        let snapper = WindowSnapper(model: model, input: input)
        snapper.tick() // snapping disabled
        model.snappingEnabled = true
        model.snapRequiresOption = true
        modifiers = [.option]
        let element = try prepareWindow(pid: 75001)
        let original = try XCTUnwrap(WindowManager.bounds(element))

        buttons = 1
        snapper.tick()
        await winSettle(0.2)
        snapper.tick() // starts dwell
        // Simulate the drag moving the window.
        fake.frame(element, original.offsetBy(dx: 60, dy: 0))
        try await Task.sleep(nanoseconds: 220_000_000)
        snapper.tick()
        await winWait { snapper.preview?.isVisible == true }
        XCTAssertEqual(snapper.preview?.isVisible, true)
        snapper.tick() // dwell still ready: rebuilds preview with the existing panel
        await winSettle()

        buttons = 0
        snapper.tick()
        await winWait { !model.toolkit.windows.loading && model.toolkit.windows.selectedID.hasPrefix("4242:") }
        XCTAssertTrue(model.toolkit.windows.selectedID.hasPrefix("4242:"))
        await winWait { !model.toolkit.windows.loading }
    }

    func testDragGuardsAndCancellation() async throws {
        let model = DockModel(defaults: UserDefaults(suiteName: "core.snap." + UUID().uuidString)!)
        model.snappingEnabled = true
        model.snapRequiresOption = true
        let snapper = WindowSnapper(model: model, input: input)
        snapper.start()
        snapper.timer?.invalidate()
        let element = try prepareWindow(pid: 76001)
        let original = try XCTUnwrap(WindowManager.bounds(element))

        // No window under the pointer.
        fake.hit = nil
        buttons = 1; snapper.tick(); await winSettle(0.15)
        snapper.tick()
        buttons = 0; snapper.tick()
        fake.hit = element

        // Option missing, then pointer away from edges / off screen.
        screens = []
        buttons = 1; snapper.tick(); await winSettle(0.15)
        screens = NSScreen.screens
        modifiers = []
        snapper.tick()
        modifiers = [.option]
        let saved = location
        location = CGPoint(x: NSScreen.screens[0].frame.midX, y: NSScreen.screens[0].frame.midY)
        snapper.tick()
        location = CGPoint(x: -100_000, y: -100_000)
        snapper.tick()
        location = saved

        // Window did not move: preview is withheld.
        snapper.tick()
        try await Task.sleep(nanoseconds: 220_000_000)
        snapper.tick()
        await winSettle(0.15)
        XCTAssertNil(snapper.preview)
        // Released without a target: no snap.
        buttons = 0; snapper.tick()

        // Escape cancels an in-progress drag.
        fake.frame(element, original)
        buttons = 1; snapper.tick(); await winSettle(0.15)
        keyHandler?(key(53))
        await winSettle()
        snapper.tick()
        buttons = 0; snapper.tick()

        // Released while the pointer left the target zone, and with Option released.
        buttons = 1; snapper.tick(); await winSettle(0.15)
        snapper.tick()
        fake.frame(element, original.offsetBy(dx: 60, dy: 0))
        try await Task.sleep(nanoseconds: 220_000_000)
        snapper.tick()
        await winWait { snapper.preview?.isVisible == true }
        modifiers = []
        buttons = 0; snapper.tick()
        XCTAssertEqual(model.toolkit.windows.selectedID, "")

        // Button released before the hit test returns.
        buttons = 1; snapper.tick(); buttons = 0
        await winSettle(0.15)
        snapper.cancel()

        // Snapping turned off while dragging.
        model.snappingEnabled = false
        buttons = 1; snapper.tick()
        buttons = 0
    }

    func testWindowAtGuards() throws {
        let point = CGPoint(x: 500, y: 110)
        fake.hit = nil
        XCTAssertNil(WindowSnapper.windowAt(point))

        let hit = winElement(77001), window = winElement(77002)
        fake.hit = hit
        XCTAssertNil(WindowSnapper.windowAt(point)) // not a window, no window attribute
        fake.put(hit, kAXWindowAttribute, "nope" as CFString)
        XCTAssertNil(WindowSnapper.windowAt(point))
        fake.put(hit, kAXWindowAttribute, window)
        fake.pids["\(CFHash(window))"] = getpid()
        XCTAssertNil(WindowSnapper.windowAt(point)) // own process
        fake.pids["\(CFHash(window))"] = 4243
        XCTAssertNil(WindowSnapper.windowAt(point)) // no running app
        fake.runningApp = NSRunningApplication.current
        XCTAssertNil(WindowSnapper.windowAt(point)) // accessory app
        fake.runningApp = try XCTUnwrap(winFinder)
        XCTAssertNil(WindowSnapper.windowAt(point)) // no bounds
        fake.frame(window, CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNil(WindowSnapper.windowAt(point)) // below the title bar
        fake.frame(window, CGRect(x: 0, y: 100, width: 800, height: 600))
        fake.put(window, "AXFullScreen", kCFBooleanTrue)
        XCTAssertNil(WindowSnapper.windowAt(point))
        fake.put(window, "AXFullScreen", nil)
        let found = try XCTUnwrap(WindowSnapper.windowAt(point))
        XCTAssertTrue(found.0.title.hasSuffix(" · Window"))
        XCTAssertEqual(found.1, CGRect(x: 0, y: 100, width: 800, height: 600))
        fake.put(window, kAXTitleAttribute, "Docs" as CFString)
        XCTAssertTrue(try XCTUnwrap(WindowSnapper.windowAt(point)).0.title.hasSuffix(" · Docs"))
    }

    func testSnapSettings() async {
        let model = DockModel(defaults: UserDefaults(suiteName: "core.snap." + UUID().uuidString)!)
        for trusted in [false, true] {
            fake.trusted = trusted
            let hosting = NSHostingView(rootView: SnapSettings(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            await winSettle(0.05)
            hosting.layoutSubtreeIfNeeded()
            winPress(hosting, "Allow Accessibility")
            window.close()
        }
        XCTAssertEqual(fake.prompts, 1)
    }
}
