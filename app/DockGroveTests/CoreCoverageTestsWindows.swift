import XCTest
import AppKit
import SwiftUI
import ApplicationServices
import Combine
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

/// A window whose display state can be exercised without minimizing a user's windows.
private final class WindowVisibilityFixture: NSWindow {
    var observedVisible = true
    var observedMiniaturized = false
    var observedOcclusion: NSWindow.OcclusionState = [.visible]
    override var isVisible: Bool { observedVisible }
    override var isMiniaturized: Bool { observedMiniaturized }
    override var occlusionState: NSWindow.OcclusionState { observedOcclusion }
}

/// Inert app identities keep discovery policy tests independent of the user's apps.
private final class WindowOwnerFixture: NSRunningApplication {
    var fixturePID: pid_t = 910_001
    var fixturePolicy: NSApplication.ActivationPolicy = .regular
    var fixtureName = "Window owner"
    override var processIdentifier: pid_t { fixturePID }
    override var activationPolicy: NSApplication.ActivationPolicy { fixturePolicy }
    override var localizedName: String? { fixtureName }
    override var isTerminated: Bool { false }
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

    @discardableResult private func host<V: View>(_ view: V, size: CGSize = CGSize(width: 640, height: 640)) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        windows.append(window)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    func testLiveClientsHandleUnavailableProcessWithoutMessagingOwnUI() async throws {
        let client = saved!
        _ = client.isTrusted()
        let pid = getpid()
        let result = await Task.detached { () -> (pid_t, Bool, Bool, AXError, AXError, Bool) in
            let own = client.application(pid)
            // Self-directed AX queries can make AppKit's HIE thread rebuild this test
            // host's main menu off the main thread. Production excludes its own PID.
            // An unavailable target exercises the live adapters without touching any UI.
            let missing = client.application(pid_t.max)
            client.setTimeout(missing, 0.2)
            let system = client.systemWide()
            _ = system
            let copied = client.copy(missing, "AXDockGroveCoverageProbe")
            let written = client.set(missing, "AXDockGroveCoverageProbe", kCFBooleanFalse)
            let performed = client.perform(missing, "AXDockGroveCoverageProbe")
            let hit = client.element(missing, CGPoint(x: -50_000, y: -50_000))
            client.pause(0)
            return (client.pid(own), client.runningApplications().isEmpty, copied == nil, written, performed, hit == nil)
        }.value
        XCTAssertEqual(result.0, pid)
        XCTAssertFalse(result.1)
        XCTAssertTrue(result.2)
        XCTAssertNotEqual(result.3, .success)
        XCTAssertNotEqual(result.4, .success)
        XCTAssertTrue(result.5)
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
        XCTAssertEqual(manager.windows.count, 1, "The continued full scan drops closed or terminated apps")
        XCTAssertFalse(manager.status.contains("Continuing"))

        fake.put(app, kAXWindowsAttribute, [] as CFArray)
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertTrue(manager.windows.isEmpty, "A completed app scan removes closed windows")
    }

    func testOverviewExcludesHelpersButScopedAccessoryWindowsRemainAvailable() async throws {
        let regular = WindowOwnerFixture(), accessory = WindowOwnerFixture(), prohibited = WindowOwnerFixture(), own = WindowOwnerFixture()
        accessory.fixturePID = 910_002; accessory.fixturePolicy = .accessory; accessory.fixtureName = "Menu-bar helper"
        prohibited.fixturePID = 910_003; prohibited.fixturePolicy = .prohibited
        own.fixturePID = ProcessInfo.processInfo.processIdentifier
        fake.apps = [regular, accessory, prohibited, own]
        for (index, owner) in fake.apps.enumerated() {
            let window = winElement(pid_t(75000 + index))
            fake.put(winElement(owner.processIdentifier), kAXWindowsAttribute, [window] as CFArray)
            fake.put(window, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString)
            fake.put(window, kAXTitleAttribute, "Document \(index)" as CFString)
        }
        let overview = WindowManager.discover(using: fake.client)
        XCTAssertEqual(overview.windows.map { $0.owner.processIdentifier }, [regular.fixturePID])
        XCTAssertEqual(overview.livePIDs, [regular.fixturePID])
        for excluded in [prohibited, own] {
            let scoped = WindowManager.discover(using: fake.client, appPID: excluded.processIdentifier)
            XCTAssertTrue(scoped.windows.isEmpty, "Prohibited apps and DockGrove itself stay excluded even when explicitly requested")
            XCTAssertTrue(scoped.livePIDs.isEmpty)
        }

        let manager = WindowManager()
        manager.refreshIfNeeded(for: accessory)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.map { $0.owner.processIdentifier }, [accessory.fixturePID], "A pinned accessory app may expose its own real windows")
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.map { $0.owner.processIdentifier }, [regular.fixturePID], "Opening the ordinary overview prunes helper windows cached by a scoped menu scan")
    }

    func testDiscoveryResumesThroughBusyAppsAndKeepsUntypedWindows() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier)
        let elements = (0..<12).map { winElement(pid_t(74200 + $0)) }
        fake.put(app, kAXWindowsAttribute, elements as CFArray)
        for (index, element) in elements.enumerated() {
            fake.put(element, kAXRoleAttribute, kAXWindowRole as CFString)
            if index > 0 { fake.put(element, kAXSubroleAttribute, (index == 1 ? "CustomWindow" : kAXStandardWindowSubrole) as CFString) }
            fake.put(element, kAXTitleAttribute, "Busy window \(index)" as CFString)
        }
        var now = 0.0
        var client = fake.client
        client.uptime = { now }
        client.copy = { [fake] element, attribute in
            now += 0.35
            return fake!.get(element, attribute)
        }
        var cursor: WindowManager.WindowDiscoveryCursor?
        var seen: Set<String> = []
        var slices = 0
        repeat {
            let result = WindowManager.discover(using: client, startingAt: cursor)
            seen.formUnion(result.windows.map(\.id))
            cursor = result.cursor
            slices += 1
            if cursor == nil { XCTAssertEqual(result.completedPIDs, [finder.processIdentifier]) }
        } while cursor != nil && slices < 20
        XCTAssertNil(cursor)
        XCTAssertGreaterThan(slices, 1)
        XCTAssertEqual(seen.count, elements.count, "Every window, including a window without AXSubrole, is eventually discovered")
    }

    func testScopedHoverContinuesAndPrunesOnlyAfterTheWholeAppIsRead() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier)
        let elements = (0..<10).map { winElement(pid_t(74220 + $0)) }
        fake.put(app, kAXWindowsAttribute, elements as CFArray)
        for element in elements { fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString) }
        var now = 0.0
        var slices = 0
        var client = fake.client
        client.uptime = { now }
        client.copy = { [fake] element, attribute in
            now += 0.4
            if attribute == kAXWindowsAttribute { slices += 1 }
            return fake!.get(element, attribute)
        }
        AccessibilityClient.current = client
        let manager = WindowManager()
        let other = ManagedWindow(id: "other-app", owner: .current, element: winElement(74239), title: "Other app")
        manager.windows = [try managed(74238, frame: nil), other]
        manager.refreshIfNeeded(for: finder)
        await winWait { !manager.loading }
        XCTAssertGreaterThan(slices, 1)
        XCTAssertEqual(Set(manager.windows.map(\.id)), Set(elements.map { "\(finder.processIdentifier):\(CFHash($0))" }).union([other.id]))
        XCTAssertFalse(manager.status.contains("Continuing"), "Scoped hover refresh must finish without another hover")

        // A new hover starts a new cycle and removes windows that have since closed.
        now += 4
        fake.put(app, kAXWindowsAttribute, [elements[0]] as CFArray)
        manager.refreshIfNeeded(for: finder)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertTrue(manager.windows.contains { $0.id == other.id })
        now += 4
        fake.put(app, kAXWindowsAttribute, nil)
        manager.refreshIfNeeded(for: finder)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, 2, "An unreadable app retains its last known windows")
        XCTAssertTrue(manager.status.contains("did not expose"))
    }

    func testCancelledScopedContinuationCannotOverwriteFreshOverviewResults() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier)
        let elements = (0..<8).map { winElement(pid_t(74240 + $0)) }
        fake.put(app, kAXWindowsAttribute, elements as CFArray)
        for element in elements { fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString) }
        let continued = expectation(description: "Scoped refresh reached its next slice")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var now = 0.0
        var slices = 0
        var client = fake.client
        client.uptime = { now }
        client.copy = { [fake] element, attribute in
            now += 0.4
            if attribute == kAXWindowsAttribute {
                slices += 1
                if slices == 2 { continued.fulfill(); _ = release.wait(timeout: .now() + 2) }
            }
            return fake!.get(element, attribute)
        }
        AccessibilityClient.current = client
        let manager = WindowManager()
        manager.refreshIfNeeded(for: finder)
        await fulfillment(of: [continued], timeout: 2)
        manager.cancelDiscovery()
        // Change scope while the cancelled worker is still unwinding. The full scan
        // must start at window zero and old scoped results must not prune its list.
        fake.put(app, kAXWindowsAttribute, [elements[0]] as CFArray)
        fake.put(elements[0], kAXTitleAttribute, "Fresh overview" as CFString)
        AccessibilityClient.current = fake.client
        manager.refresh()
        await winWait { !manager.loading }
        release.signal()
        await winSettle()
        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.windows.first?.menuTitle, "Fresh overview")
        XCTAssertFalse(manager.loading)
        XCTAssertFalse(manager.status.contains("Continuing"))
    }

    func testContinuationMakesProgressWhenAnAppExceedsItsMessagingTimeout() throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier)
        let elements = [winElement(74280), winElement(74281)]
        fake.put(app, kAXWindowsAttribute, elements as CFArray)
        for element in elements { fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString) }
        var now = 0.0
        var client = fake.client
        client.uptime = { now }
        client.copy = { [fake] element, attribute in
            if attribute == kAXWindowsAttribute { now += 4 }
            return fake!.get(element, attribute)
        }
        var cursor: WindowManager.WindowDiscoveryCursor?
        var seen: Set<String> = []
        for _ in 0..<4 {
            let result = WindowManager.discover(using: client, startingAt: cursor)
            cursor = result.cursor
            seen.formUnion(result.windows.map(\.id))
            if cursor == nil { break }
        }
        XCTAssertNil(cursor)
        XCTAssertEqual(seen.count, 2, "A slow app must not pin the scan to its first window forever")
    }

    func testFullRefreshContinuesWithoutAnotherClickAndReconcilesOnlyCompletedApps() async throws {
        let finder = try XCTUnwrap(winFinder)
        fake.apps = [finder]
        let app = winElement(finder.processIdentifier)
        let elements = (0..<10).map { winElement(pid_t(74300 + $0)) }
        fake.put(app, kAXWindowsAttribute, elements as CFArray)
        for element in elements { fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString) }
        var now = 0.0
        var client = fake.client
        client.uptime = { now }
        client.copy = { [fake] element, attribute in now += 0.4; return fake!.get(element, attribute) }
        AccessibilityClient.current = client
        let manager = WindowManager()
        manager.windows = [try managed(74399, frame: nil)]
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, elements.count)
        XCTAssertFalse(manager.windows.contains { $0.id == "w74399" })
        XCTAssertFalse(manager.status.contains("Continuing"))
        // An inaccessible app is different from one which successfully reports zero windows.
        fake.put(app, kAXWindowsAttribute, nil)
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.windows.count, elements.count)
        XCTAssertTrue(manager.status.contains("did not expose"))
        fake.put(app, kAXWindowsAttribute, [] as CFArray)
        manager.refresh()
        await winWait { !manager.loading }
        XCTAssertTrue(manager.windows.isEmpty)
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
        XCTAssertEqual(fake.get(window.element, kAXMinimizedAttribute) as? Bool, false)
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

    func testPlacementPreflightIsResponsiveAndPreservesOriginalWindow() async throws {
        let manager = WindowManager(), window = try managed(70104, frame: CGRect(x: 15, y: 25, width: 350, height: 250))
        manager.windows = [window]; manager.selectedID = window.id
        let started = expectation(description: "Background frame read")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var client = fake.client
        let read = client.copy
        var first = true
        client.copy = { element, attribute in
            XCTAssertFalse(Thread.isMainThread)
            if first { first = false; started.fulfill(); _ = release.wait(timeout: .now() + 2) }
            return read(element, attribute)
        }
        AccessibilityClient.current = client
        manager.place(.left)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(manager.loading)
        manager.cancelDiscovery()
        manager.place(.right)
        XCTAssertTrue(manager.loading)
        manager.selectedID = "changed while checking"
        release.signal()
        await winWait { !manager.loading }
        XCTAssertEqual(manager.status, "Window arranged. Undo is available.")
        XCTAssertEqual(manager.selectedID, "changed while checking")
        manager.selectedID = window.id
        manager.undoPlacement()
        await winWait { !manager.loading }
        AccessibilityClient.current = fake.client
        XCTAssertEqual(WindowManager.bounds(window.element), CGRect(x: 15, y: 25, width: 350, height: 250))
    }

    func testPlacementPreflightUnavailableAndRevokedAccess() async throws {
        let manager = WindowManager(), window = try managed(70105, frame: nil)
        manager.windows = [window]; manager.selectedID = window.id
        manager.place(.left)
        await winWait { !manager.loading }
        XCTAssertTrue(manager.status.hasPrefix("Window unavailable"))
        fake.trustedAnswers = [true, false]
        manager.place(.left)
        await winWait { !manager.loading }
        XCTAssertEqual(manager.status, "Accessibility permission was removed.")
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
        await winWait { !manager.loading }
        XCTAssertTrue(manager.status.hasPrefix("Leave native full screen"))
        fake.put(window.element, "AXFullScreen", kCFBooleanFalse)

        manager.place(.left, dockHeight: 30)
        await winWait { !manager.loading }
        XCTAssertGreaterThan(fake.activations, 0)
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

    func testMinimizeWaitsForConfirmedStateAndBoundsAnUnconfirmedAcknowledgement() async throws {
        let manager = WindowManager()
        let window = try managed(72907, frame: nil)
        manager.windows = [window]; manager.selectedID = window.id
        fake.put(window.element, kAXMinimizedAttribute, kCFBooleanFalse)
        fake.storeMinimized = false
        var pauses = 0
        var client = fake.client
        client.pause = { [fake] _ in
            pauses += 1
            if pauses == 2 { fake!.put(window.element, kAXMinimizedAttribute, kCFBooleanTrue) }
        }
        AccessibilityClient.current = client
        await manager.minimize()
        XCTAssertEqual(pauses, 2)
        XCTAssertEqual(manager.status, "Window minimized.")
        XCTAssertTrue(manager.windows[0].isMinimized)

        // A successful write alone must not turn an open or unreadable window into
        // a minimized card. Both cases get a short, finite confirmation period.
        AccessibilityClient.current = fake.client
        for value: CFTypeRef? in [kCFBooleanFalse, nil] {
            manager.windows = [window]
            fake.put(window.element, kAXMinimizedAttribute, value)
            let previousPauses = fake.pauses
            await manager.minimize()
            XCTAssertEqual(fake.pauses - previousPauses, 3)
            XCTAssertEqual(manager.status, "This window cannot be minimized.")
            XCTAssertFalse(manager.windows[0].isMinimized)
            XCTAssertFalse(manager.acting)
        }
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

    func testSuccessfulRaiseStillRequiresConfirmedUnminimizedState() async throws {
        let manager = WindowManager()
        var window = try managed(72906, frame: nil)
        window.isMinimized = true
        manager.windows = [window]; manager.selectedID = window.id
        fake.put(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
        fake.storeMinimized = false
        fake.performResult = .success
        let refused = await manager.focus()
        XCTAssertFalse(refused, "A successful AX acknowledgement is not proof that a minimized window was restored")
        XCTAssertTrue(manager.windows[0].isMinimized)
        XCTAssertTrue(manager.status.hasPrefix("This app could not restore"))
        XCTAssertEqual(fake.pauses, 3, "Settling retries are bounded")

        // The same acknowledgement may legitimately precede an asynchronous restore.
        var pauses = 0
        var client = fake.client
        client.pause = { [fake] _ in
            pauses += 1
            if pauses == 2 { fake!.put(window.element, kAXMinimizedAttribute, kCFBooleanFalse) }
        }
        AccessibilityClient.current = client
        let delayed = await manager.focus()
        XCTAssertTrue(delayed)
        XCTAssertEqual(pauses, 2)
        XCTAssertFalse(manager.windows[0].isMinimized)
        XCTAssertEqual(manager.status, "Window brought forward.")

        manager.windows = [window]
        fake.put(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
        fake.queue(kAXMinimizedAttribute, [.attributeUnsupported])
        let unsupported = await manager.focus()
        XCTAssertFalse(unsupported)
        XCTAssertTrue(manager.windows[0].isMinimized)
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
        let denied = host(WindowShelfView(manager: manager) { dismissed += 1 }, size: CGSize(width: 840, height: 620))
        await winSettle()
        XCTAssertGreaterThan(winPress(denied, "Allow Accessibility"), 0)
        XCTAssertGreaterThan(fake.prompts, 0)
        XCTAssertGreaterThan(winPress(denied, "Done"), 0)
        XCTAssertEqual(dismissed, 1)
        fake.trusted = true
        let empty = host(WindowShelfView(manager: manager) { dismissed += 1 }, size: CGSize(width: 840, height: 620))
        await winWait { !manager.loading }
        await winSettle()
        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertGreaterThan(winPress(empty, "Refresh windows"), 0)
        await winWait { !manager.loading }
        await winSettle()
        let previousEffect = DockSystemEffect.handler
        defer { DockSystemEffect.handler = previousEffect; manager.overviewWindow?.close() }
        var presented: [NSWindow] = []
        var opened: [URL] = []
        DockSystemEffect.handler = { effect in
            if case .present(let window) = effect { presented.append(window) }
            if case .open(let url) = effect { opened.append(url) }
        }
        XCTAssertGreaterThan(winPress(empty, "Mission Control"), 0)
        XCTAssertEqual(opened.map(\.path), ["/System/Applications/Mission Control.app"])
        let button = host(WindowShelfButton(manager: manager, enabled: true))
        await winSettle()
        XCTAssertGreaterThan(winPress(button, "Open and minimized windows"), 0)
        let overview = try XCTUnwrap(manager.overviewWindow)
        XCTAssertTrue(overview.canBecomeKey)
        XCTAssertTrue(overview.styleMask.contains(.resizable))
        XCTAssertTrue(overview.styleMask.contains(.miniaturizable))
        manager.showOverview()
        XCTAssertEqual(presented.count, 2)
        XCTAssertTrue(presented.allSatisfy { $0 === overview })
        overview.orderFrontRegardless()
        let content = try XCTUnwrap(overview.contentView)
        content.layoutSubtreeIfNeeded()
        await winWait { !manager.loading }
        await winSettle()
        XCTAssertGreaterThan(winPress(content, "Done"), 0)
        XCTAssertNil(manager.overviewWindow)
        XCTAssertNil(overview.contentView, "Closing releases the hosted timer and its window listing")
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
        enter("fixture")
        await winSettle()
        let beforeSubmit = dismissed
        let action = try XCTUnwrap(field.action)
        XCTAssertTrue(NSApp.sendAction(action, to: field.target, from: field))
        await winWait { dismissed > beforeSubmit }
        XCTAssertEqual(dismissed, beforeSubmit + 1, "Return restores the first visible search result")
        enter("no matching window")
        await winSettle()
        NSApp.sendAction(action, to: field.target, from: field)
        await winSettle()
        XCTAssertEqual(dismissed, beforeSubmit + 1, "Return with no results must not activate another app")
    }

    func testWindowOverviewGroupsAndSortsTitles() throws {
        var a = try managed(74901, frame: nil), b = try managed(74902, frame: nil)
        a = ManagedWindow(id: a.id, owner: a.owner, element: a.element, title: WindowManager.windowTitle(app: a.owner.localizedName, window: "Window 12", fallback: ""))
        b = ManagedWindow(id: b.id, owner: b.owner, element: b.element, title: WindowManager.windowTitle(app: b.owner.localizedName, window: "Window 2", fallback: ""))
        let groups = WindowShelfGroup.make(from: [a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].windows.map(\.menuTitle), ["Window 2", "Window 12"])
        XCTAssertTrue(WindowShelfGroup.make(from: []).isEmpty)
        let other = ManagedWindow(id: "test-host", owner: .current, element: winElement(74903), title: "Test host window")
        let multiple = WindowShelfGroup.make(from: [a, other, b])
        XCTAssertEqual(multiple.count, 2)
        XCTAssertEqual(multiple.map(\.name), multiple.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(multiple.first { $0.id == a.owner.processIdentifier }?.windows.map(\.id), [b.id, a.id])
    }

    func testWindowOverviewRefreshOnlyWhileVisible() async throws {
        let manager = WindowManager()
        let ticks = PassthroughSubject<Date, Never>()
        _ = host(WindowShelfView(manager: manager, refreshEvents: ticks.eraseToAnyPublisher()) {}, size: CGSize(width: 840, height: 620))
        await winWait { !manager.loading }
        let visibility = WindowVisibilityFixture(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        visibility.isReleasedWhenClosed = false
        manager.overviewWindow = visibility
        defer { manager.overviewWindow = nil; visibility.close() }
        for state in [(false, false, true), (true, true, true), (true, false, false)] {
            visibility.observedVisible = state.0
            visibility.observedMiniaturized = state.1
            visibility.observedOcclusion = state.2 ? [.visible] : []
            manager.status = "No background scans"
            ticks.send(Date())
            await winSettle()
            XCTAssertEqual(manager.status, "No background scans")
            XCTAssertFalse(manager.loading)
        }
        visibility.observedVisible = true; visibility.observedMiniaturized = false; visibility.observedOcclusion = [.visible]
        ticks.send(Date())
        await winWait { !manager.loading && manager.status.hasPrefix("No accessible windows") }
        XCTAssertTrue(manager.status.hasPrefix("No accessible windows"))
        manager.overviewWindow = nil
        manager.status = "Embedded overview"
        ticks.send(Date())
        await winWait { !manager.loading && manager.status.hasPrefix("No accessible windows") }
        XCTAssertTrue(manager.status.hasPrefix("No accessible windows"))
    }

    func testWindowOverviewCardsHoverWithoutActivatingApps() async throws {
        let finder = try XCTUnwrap(winFinder), element = winElement(74904)
        fake.apps = [finder]
        fake.put(winElement(finder.processIdentifier), kAXWindowsAttribute, [element] as CFArray)
        fake.put(element, kAXSubroleAttribute, kAXStandardWindowSubrole as CFString)
        fake.put(element, kAXTitleAttribute, "Hover fixture" as CFString)
        let manager = WindowManager()
        let view = DockHarness(WindowShelfView(manager: manager) {}, size: CGSize(width: 840, height: 620))
        defer { view.close() }
        await winWait { !manager.loading }
        view.spin()
        let window = try XCTUnwrap(manager.windows.first)
        let label = window.title + ", open. Restore window"
        let point = try XCTUnwrap(view.center(label))
        view.hover(point, entering: true)
        XCTAssertTrue(view.has(label))
        view.hover(point, entering: false)
        XCTAssertTrue(view.has(label))
        XCTAssertEqual(fake.activations, 0, "Hover must only highlight the card, not activate an app")
    }

    func testWindowShelfContextActionsMinimizeAndRestore() async throws {
        let manager = WindowManager(), window = try managed(72905, frame: nil)
        manager.windows = [window]
        let menu = host(WindowShelfActions(manager: manager, window: window))
        await winSettle()
        XCTAssertGreaterThan(winPress(menu, "Minimize window"), 0)
        await winWait { fake.get(window.element, kAXMinimizedAttribute) as? Bool == true && !manager.acting }
        XCTAssertEqual(manager.status, "Window minimized.")
        XCTAssertGreaterThan(winPress(menu, "Bring forward"), 0)
        await winWait { fake.get(window.element, kAXMinimizedAttribute) as? Bool == false && !manager.acting }
        XCTAssertEqual(manager.status, "Window brought forward.")
        var minimized = window; minimized.isMinimized = true
        fake.put(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
        let restore = host(WindowShelfActions(manager: manager, window: minimized))
        await winSettle()
        XCTAssertEqual(winPress(restore, "Minimize window"), 0)
        XCTAssertGreaterThan(winPress(restore, "Restore window"), 0)
        await winWait { fake.get(window.element, kAXMinimizedAttribute) as? Bool == false && !manager.acting }
        XCTAssertEqual(manager.selectedID, window.id)
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
        XCTAssertNil(snapper?.timer, "Disabled snapping does not poll the pointer")
        XCTAssertNil(keyHandler)
        snapper?.start() // idempotent
        model.snappingEnabled = true
        XCTAssertNotNil(snapper?.timer)
        XCTAssertNotNil(keyHandler)
        snapper?.timer?.fire()
        keyHandler?(key(0))
        keyHandler?(key(53))
        await winSettle()
        model.snappingEnabled = false
        XCTAssertNil(snapper?.timer)
        XCTAssertEqual(removed, 1)
        model.snappingEnabled = true
        XCTAssertNotNil(snapper?.timer)
        snapper = nil
        XCTAssertEqual(removed, 2)
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
