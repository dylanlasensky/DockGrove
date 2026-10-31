import XCTest
import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
@testable import DockGrove

// MARK: - Harness

/// Hosts SwiftUI in an offscreen borderless window that never becomes key, so synthesized
/// mouse events, accessibility presses and context menus drive real view code without focus.
@MainActor final class DockHarness {
    let window: NSWindow
    let host: NSView
    private static var accessibilityReady = false

    init(view host: NSView, size: CGSize) {
        if !Self.accessibilityReady {
            // Builds SwiftUI's accessibility tree in-process, as an assistive client would.
            _ = NSApp.perform(Selector(("setAccessibilityEnhancedUserInterface:")), with: NSNumber(value: true))
            Self.accessibilityReady = true
        }
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        self.host = host
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        spin(0.15)
    }

    convenience init<V: View>(_ view: V, size: CGSize = CGSize(width: 900, height: 400)) {
        self.init(view: NSHostingView(rootView: view), size: size)
    }

    func spin(_ seconds: TimeInterval = 0.05) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
    }

    func resize(_ size: CGSize) {
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        spin(0.1)
    }

    func close() { window.orderOut(nil); window.contentView = nil; window.close() }

    // Accessibility

    nonisolated static func get(_ node: NSObject, _ key: String) -> Any? {
        let selector = NSSelectorFromString(key)
        guard node.responds(to: selector) else { return nil }
        if key == "accessibilityFrame" { return node.value(forKey: key) }
        return node.perform(selector)?.takeUnretainedValue()
    }
    nonisolated private static func label(_ node: NSObject) -> String {
        (get(node, "accessibilityLabel") as? String) ?? ""
    }
    func nodes() -> [NSObject] {
        var result: [NSObject] = []
        func walk(_ any: Any, _ depth: Int) {
            guard depth < 40, let node = any as? NSObject else { return }
            result.append(node)
            for child in (Self.get(node, "accessibilityChildren") as? [Any]) ?? [] { walk(child, depth + 1) }
        }
        walk(host, 0)
        return result
    }
    func labels() -> [String] { nodes().map(Self.label).filter { !$0.isEmpty } }
    func node(_ label: String) -> NSObject? {
        let all = nodes()
        return all.first { Self.label($0) == label } ?? all.first { Self.label($0).hasPrefix(label + ",") }
    }
    func has(_ label: String) -> Bool { node(label) != nil }

    @discardableResult func press(_ label: String, index: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let all = nodes()
        let matches = all.filter { Self.label($0) == label } + all.filter { Self.label($0).hasPrefix(label + ",") }
        guard matches.indices.contains(index) else {
            XCTFail("No accessibility element labelled \(label). Have: \(labels())", file: file, line: line); return false
        }
        _ = matches[index].perform(Selector(("accessibilityPerformPress")))
        spin()
        return true
    }

    /// Converts a SwiftUI global (top-left origin) point into window coordinates.
    func windowPoint(_ global: CGPoint) -> CGPoint { host.convert(global, to: nil) }

    @discardableResult func act(_ name: String, at index: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let actions = nodes().flatMap { (Self.get($0, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? [] }.filter { $0.name == name }
        guard actions.indices.contains(index) else {
            XCTFail("No accessibility action \(name)", file: file, line: line); return false
        }
        _ = actions[index].handler?()
        spin()
        return true
    }

    /// The element's frame in window coordinates (origin bottom-left).
    func frame(_ label: String) -> CGRect? {
        guard let node = node(label), let screen = (Self.get(node, "accessibilityFrame") as? NSValue)?.rectValue else { return nil }
        return window.convertFromScreen(screen)
    }

    func center(_ label: String) -> CGPoint? { frame(label).map { CGPoint(x: $0.midX, y: $0.midY) } }
    func frame(of node: NSObject) -> CGRect? {
        if let view = node as? NSView { return view.convert(view.bounds, to: nil) }
        return (Self.get(node, "accessibilityFrame") as? NSValue).map { window.convertFromScreen($0.rectValue) }
    }

    /// Moves a virtual pointer over `point`, driving SwiftUI hover tracking.
    func hover(_ point: CGPoint, entering: Bool) {
        var areas: [NSTrackingArea] = []
        func collect(_ view: NSView) { areas += view.trackingAreas; view.subviews.forEach(collect) }
        collect(host)
        let moved = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        for area in areas {
            guard let owner = area.owner as? NSObject else { continue }
            let tracking = Int(bitPattern: Unmanaged.passUnretained(area).toOpaque())
            let crossing = NSEvent.enterExitEvent(with: entering ? .mouseEntered : .mouseExited, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: tracking, userData: nil)!
            let enter = #selector(NSResponder.mouseEntered(with:)), exit = #selector(NSResponder.mouseExited(with:)), move = #selector(NSResponder.mouseMoved(with:))
            for (selector, event) in entering ? [(enter, crossing), (move, moved)] : [(move, moved), (exit, crossing)] where owner.responds(to: selector) {
                owner.perform(selector, with: event)
            }
        }
        window.sendEvent(moved)
        spin(0.1)
    }

    // Context menus

    func menu(at point: CGPoint) -> NSMenu? {
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let target = host.hitTest(host.convert(point, from: nil)) ?? host
        return target.menu(for: event) ?? host.menu(for: event)
    }

    @discardableResult func choose(_ title: String, inMenuAt point: CGPoint, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let menu = menu(at: point) else { XCTFail("No context menu at \(point)", file: file, line: line); return false }
        guard let index = menu.items.firstIndex(where: { $0.title == title }) else {
            XCTFail("No menu item \(title) in \(menu.items.map(\.title))", file: file, line: line); return false
        }
        menu.performActionForItem(at: index)
        spin()
        return true
    }

    func menuTitles(at point: CGPoint) -> [String] { menu(at: point)?.items.map(\.title) ?? [] }

    /// Scans the window for the first context menu offering `title`, then chooses it.
    @discardableResult func chooseAnywhere(_ title: String, skip: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        var skipped = 0
        let bounds = host.bounds
        for y in stride(from: bounds.minY + 3, to: bounds.maxY, by: 6) {
            for x in stride(from: bounds.minX + 3, to: bounds.maxX, by: 6) {
                let point = host.convert(CGPoint(x: x, y: y), to: nil)
                guard let menu = menu(at: point), let index = menu.items.firstIndex(where: { $0.title == title }) else { continue }
                if skipped < skip { skipped += 1; continue }
                menu.performActionForItem(at: index)
                spin()
                return true
            }
        }
        XCTFail("No context menu offers \(title)", file: file, line: line)
        return false
    }

    // Mouse

    func mouse(_ type: NSEvent.EventType, _ point: CGPoint) {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        window.sendEvent(event)
    }

    func click(_ point: CGPoint) { mouse(.leftMouseDown, point); mouse(.leftMouseUp, point); spin() }

    /// Drags in small steps; `hold` keeps the button down at the end so timers can observe it.
    func drag(from start: CGPoint, to end: CGPoint, steps: Int = 6, hold: TimeInterval = 0, release: Bool = true) {
        mouse(.leftMouseDown, start)
        spin(0.02)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            mouse(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            spin(0.02)
        }
        if hold > 0 {
            let until = Date().addingTimeInterval(hold)
            while Date() < until { mouse(.leftMouseDragged, end); spin(0.05) }
        }
        if release { mouse(.leftMouseUp, end); spin() }
    }

    // Text

    func textFields() -> [NSTextField] {
        var found: [NSTextField] = []
        func walk(_ view: NSView) { if let field = view as? NSTextField, field.isEditable { found.append(field) }; view.subviews.forEach(walk) }
        walk(host)
        return found
    }

    func enter(_ text: String, intoField index: Int = 0) {
        let fields = textFields()
        guard fields.indices.contains(index) else { XCTFail("No text field \(index)"); return }
        let field = fields[index]
        field.stringValue = text
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        field.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        spin()
    }

    func popUps() -> [NSPopUpButton] {
        var found: [NSPopUpButton] = []
        func walk(_ view: NSView) { if let popup = view as? NSPopUpButton { found.append(popup) }; view.subviews.forEach(walk) }
        walk(host)
        return found
    }
}

/// A drag that never touches the system drag server.
final class DockFakeDrag: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    var location: CGPoint
    weak var window: NSWindow?
    init(pasteboard: NSPasteboard, location: CGPoint = .zero, window: NSWindow? = nil) { self.pasteboard = pasteboard; self.location = location; self.window = window }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for (index, item) in (pasteboard.pasteboardItems ?? []).enumerated() {
            block(NSDraggingItem(pasteboardWriter: item), index, &stop)
            if stop.boolValue { break }
        }
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    // Private hooks AppKit and SwiftUI call on real dragging infos.
    @objc func _lastDragDestinationOperation() -> NSDragOperation { .copy }
    @objc func _setLastDragDestinationOperation(_ operation: NSDragOperation) {}
    func resetSpringLoading() {}
}

/// A display with a camera housing, placed far offscreen so nothing ever appears to the user.
final class DockFakeNotchScreen: NSScreen {
    static let origin = CGPoint(x: -30000, y: -30000)
    override var frame: NSRect { NSRect(x: Self.origin.x, y: Self.origin.y, width: 1512, height: 982) }
    override var visibleFrame: NSRect { NSRect(x: Self.origin.x, y: Self.origin.y, width: 1512, height: 950) }
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0) }
    override var __auxiliaryTopLeftArea: NSRect { NSRect(x: Self.origin.x, y: Self.origin.y + 950, width: 663.5, height: 32) }
    override var __auxiliaryTopRightArea: NSRect { NSRect(x: Self.origin.x + 848.5, y: Self.origin.y + 950, width: 663.5, height: 32) }
    override var localizedName: String { "Fake Notch Display" }
}

/// Records open-panel requests and answers them without any panel.
final class DockFakeOpenPanel {
    var response: NSApplication.ModalResponse = .OK
    var chosen: [URL] = []
    var message: String?
    func choose(_ message: String) -> [URL]? { self.message = message; return response == .OK ? chosen : nil }
}

final class DockFakeSharingService: NSSharingService {
    var performable = true
    var performed: [[Any]] = []
    override func canPerform(withItems items: [Any]?) -> Bool { performable }
    override func perform(withItems items: [Any]) { performed.append(items) }
}

@MainActor final class DockFakeWindows: AppWindowListing {
    @Published var windows: [ManagedWindow] = []
    @Published var status = "Fake status"
    @Published var trusted = false
    @Published var selectedID = ""
    var calls: [String] = []
    func requestAccess() { calls.append("request") }
    func refresh() { calls.append("refresh") }
    func focus() { calls.append("focus:" + selectedID) }
}

final class DockRecordingSource: NativeStudioDragSource.SourceView {
    var sessions: [[NSDraggingItem]] = []
    override func startSession(_ items: [NSDraggingItem], event: NSEvent) { sessions.append(items) }
}

// MARK: - Tests

@MainActor final class DockCoverageTests: XCTestCase {
    private var suites: [String] = []
    private var effects: [DockSystemEffect] = []
    private var scratch: URL!
    private var savedHandler: ((DockSystemEffect) -> Void)?

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("DockCoverage." + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        savedHandler = DockSystemEffect.handler
        DockSystemEffect.handler = { [weak self] in self?.effects.append($0) }
    }

    override func tearDownWithError() throws {
        if let savedHandler { DockSystemEffect.handler = savedHandler }
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        try? FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    /// Spins the main run loop (where main-actor tasks run) until `condition` holds.
    private func wait(timeout: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    private var openFileEffects: [((NSRunningApplication?, Error?) -> Void)] {
        effects.compactMap { if case .openFiles(_, _, let completion) = $0 { return completion }; return nil }
    }

    private func defaults(_ configure: (UserDefaults) -> Void = { _ in }) -> UserDefaults {
        let suite = "DockCoverageTests." + UUID().uuidString
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set([], forKey: "apps"); defaults.set(false, forKey: "showRunning")
        configure(defaults)
        return defaults
    }

    private func model(_ configure: (UserDefaults) -> Void = { _ in }) -> DockModel {
        let model = DockModel(defaults: defaults(configure))
        model.openApplication = { _ in }
        model.fetchUsage = { _ in throw UsageError.service }
        model.toolkit.applicationRoots = []
        return model
    }

    private func file(_ name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    private func filePasteboard(_ urls: [URL]) -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    private func notchController(_ model: DockModel, airDrop: (([URL]) -> Bool)? = nil) -> NotchController {
        let controller = NotchController(model: model, airDropAction: airDrop)
        controller.compatibleDisplay = { DockFakeNotchScreen() }
        controller.mouseLocation = { CGPoint(x: -1, y: -1) }
        controller.chooseFiles = { _ in nil }
        addTeardownBlock { controller.hide() }
        return controller
    }

    // MARK: Notch controller

    func testDefaultSystemEffectHandler() {
        // Unhiding the visible test host is a no-op, so the live handler can run here.
        savedHandler?(.setHidden(.current, false))
        XCTAssertFalse(NSRunningApplication.current.isHidden)
    }

    func testNotchDefaultHooksAreSideEffectFree() {
        let controller = NotchController(model: model())
        XCTAssertNotNil(controller.makeAirDropService())
        _ = controller.compatibleDisplay()
        XCTAssertGreaterThan(controller.clock(), 0)
        _ = controller.mouseLocation()
        let screen = NSScreen.screens[0]
        _ = NotchController.fullscreen(on: screen)
        XCTAssertNotNil(BrandIcon.loadArtwork("DockGrove-icon"))
        XCTAssertEqual(NotchFileIntake.urls(from: NSPasteboard.withUniqueName()), [])
        let local = URL(string: "file://localhost" + scratch.path)!
        XCTAssertEqual(NotchFileIntake.existingURLs([local, URL(string: "file://elsewhere" + scratch.path)!]).count, 1)
        let zone = DockHarness(NotchDropZone(destination: .tray, controller: controller), size: CGSize(width: 300, height: 100))
        zone.close()
    }

    func testNotchFullscreenDetection() {
        let screen = DockFakeNotchScreen()
        let me = ProcessInfo.processInfo.processIdentifier
        let other: pid_t = me + 1
        let top = screen.frame.maxY + 1000
        let frame = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        func window(_ pid: pid_t, layer: Int = 0, alpha: Double? = 1, bounds: CGRect? = frame) -> [String: Any] {
            var info: [String: Any] = [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer]
            if let alpha { info[kCGWindowAlpha as String] = alpha }
            if let bounds { info[kCGWindowBounds as String] = bounds.dictionaryRepresentation }
            return info
        }
        XCTAssertFalse(NotchController.fullscreen(on: screen, frontmost: nil, primaryTop: top, windows: [window(other)]))
        XCTAssertFalse(NotchController.fullscreen(on: screen, frontmost: me, primaryTop: top, windows: [window(me)]))
        XCTAssertTrue(NotchController.fullscreen(on: screen, frontmost: other, primaryTop: top, windows: [window(other)]))
        XCTAssertTrue(NotchController.fullscreen(on: screen, frontmost: other, primaryTop: top, windows: [window(other, alpha: nil)]))
        XCTAssertFalse(NotchController.fullscreen(on: screen, frontmost: other, primaryTop: top, windows: [window(me), window(other, layer: 3), window(other, alpha: 0), window(other, bounds: nil)]))
        XCTAssertFalse(NotchController.fullscreen(on: screen, frontmost: other, primaryTop: nil, windows: nil))
    }

    func testNotchUpdateFollowsHoverAndDisplay() {
        let model = model()
        model.notchEnabled = true
        let controller = notchController(model)
        XCTAssertEqual(controller.expandedWidth, CGFloat(NotchGeometry.normalizedWidth(model.notchWidth)))
        var now: TimeInterval = 100
        controller.clock = { now }
        controller.update(suppressed: false)
        let geometry = try? XCTUnwrap(controller.geometry)
        XCTAssertNotNil(geometry)
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertGreaterThan(controller.expandedWidth, 600)
        // Hovering the housing for longer than the delay expands; leaving collapses.
        let housing = geometry!.housing
        controller.mouseLocation = { CGPoint(x: housing.midX, y: housing.midY) }
        controller.update(suppressed: false)
        now += 0.3
        controller.update(suppressed: false)
        XCTAssertTrue(controller.expanded)
        controller.mouseLocation = { CGPoint(x: -1, y: -1) }
        now += 1
        controller.update(suppressed: false)
        controller.update(suppressed: false)
        XCTAssertFalse(controller.expanded)
        controller.selectedWidget = .focus
        controller.update(suppressed: false)
        XCTAssertEqual(controller.selectedWidget, .focus)
        controller.compatibleDisplay = { nil }
        controller.update(suppressed: false)
        XCTAssertNil(controller.geometry)
        XCTAssertFalse(controller.panel.isVisible)
    }

    func testNotchAirDropAndPicker() throws {
        let model = model()
        let controller = notchController(model)
        let fixture = try file("Share.txt")
        let service = DockFakeSharingService(title: "Fake", image: NSImage(), alternateImage: nil, handler: {})
        controller.makeAirDropService = { nil }
        XCTAssertFalse(controller.startAirDrop())
        XCTAssertEqual(controller.airDropMessage, "Add files before choosing a device.")
        controller.airDropFiles = [fixture]
        XCTAssertFalse(controller.startAirDrop())
        XCTAssertEqual(controller.airDropMessage, "AirDrop is unavailable for these files.")
        service.performable = false
        controller.makeAirDropService = { service }
        XCTAssertFalse(controller.startAirDrop())
        service.performable = true
        XCTAssertTrue(controller.startAirDrop())
        XCTAssertEqual(service.performed.count, 1)
        XCTAssertTrue(controller.airDropBusy)
        var scope = NSSharingService.SharingContentScope.item
        XCTAssertTrue(controller.sharingService(service, sourceWindowForShareItems: [], sharingContentScope: &scope) === controller.panel)
        // Busy AirDrop keeps its selection and refuses new AirDrop work.
        controller.clearAirDropFiles(); controller.removeAirDropFile(fixture)
        XCTAssertEqual(controller.airDropFiles, [fixture.standardizedFileURL])
        XCTAssertFalse(controller.canAccept(.airDrop))
        controller.activateDropZone(.airDrop)
        controller.addFiles(to: .airDrop)
        controller.sharingService(service, didFailToShareItems: [], error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        XCTAssertEqual(controller.airDropMessage, "AirDrop cancelled. Drop to try again.")
        XCTAssertTrue(controller.startAirDrop())
        controller.sharingService(service, didFailToShareItems: [], error: NSError(domain: NSCocoaErrorDomain, code: 1))
        XCTAssertEqual(controller.airDropMessage, "AirDrop did not finish. Try again.")

        // The drop zones open review first, then choose files through the open panel.
        let panel = DockFakeOpenPanel()
        panel.chosen = [try file("Picked.txt")]
        controller.chooseFiles = panel.choose
        controller.airDropReview = false
        controller.activateDropZone(.airDrop)
        XCTAssertTrue(controller.airDropReview && controller.expanded && controller.showingFiles)
        XCTAssertEqual(controller.defaultDropDestination, .airDrop)
        controller.activateDropZone(.airDrop)
        XCTAssertEqual(panel.message, "Choose files to share with AirDrop.")
        XCTAssertTrue(controller.airDropFiles.contains(panel.chosen[0].standardizedFileURL))
        controller.activateDropZone(.tray)
        XCTAssertEqual(panel.message, "Choose files to keep in the tray.")
        XCTAssertEqual(model.toolkit.files, [panel.chosen[0].standardizedFileURL.path])
        panel.response = .cancel
        controller.addFiles()
        XCTAssertEqual(model.toolkit.files.count, 1)
    }

    func testNotchDropViews() throws {
        let model = model()
        let controller = notchController(model)
        let fixture = try file("Drop.txt")
        let files = filePasteboard([fixture])
        let text = NSPasteboard.withUniqueName(); text.clearContents(); text.setString("plain", forType: .string)
        addTeardownBlock { text.releaseGlobally() }
        let host = try XCTUnwrap(controller.panel.contentView as? NotchDropHostingView)
        XCTAssertEqual(host.draggingEntered(DockFakeDrag(pasteboard: text)), [])
        XCTAssertEqual(host.draggingEntered(DockFakeDrag(pasteboard: files)), .copy)
        XCTAssertTrue(controller.fileDragActive && controller.showingFiles)
        XCTAssertEqual(host.draggingUpdated(DockFakeDrag(pasteboard: files)), .copy)
        XCTAssertEqual(controller.activeDropDestination, .tray)
        host.draggingExited(nil)
        XCTAssertFalse(controller.fileDragActive)
        XCTAssertTrue(host.prepareForDragOperation(DockFakeDrag(pasteboard: files)))
        XCTAssertTrue(host.performDragOperation(DockFakeDrag(pasteboard: files)))
        XCTAssertEqual(model.toolkit.files, [fixture.standardizedFileURL.path])
        controller.fileDragActive = true
        host.concludeDragOperation(nil)
        XCTAssertFalse(controller.fileDragActive)
        // Without a controller the stable host declines everything.
        let orphan = NotchDropHostingView(rootView: NotchShelfView(model: model, controller: controller))
        XCTAssertEqual(orphan.draggingUpdated(DockFakeDrag(pasteboard: files)), [])
        XCTAssertFalse(orphan.performDragOperation(DockFakeDrag(pasteboard: files)))
        XCTAssertFalse(orphan.prepareForDragOperation(DockFakeDrag(pasteboard: files)))
        controller.makeAirDropService = { DockFakeSharingService(title: "Fake", image: NSImage(), alternateImage: nil, handler: {}) }
        controller.airDropFiles = [fixture]
        XCTAssertTrue(controller.startAirDrop())
        controller.expanded = true; controller.showingFiles = true; controller.airDropReview = true
        XCTAssertEqual(host.draggingUpdated(DockFakeDrag(pasteboard: files)), [])

        // The per-zone native targets.
        let target = NotchDropTargetView(frame: .zero)
        target.controller = controller
        target.destination = .airDrop
        XCTAssertEqual(target.draggingEntered(DockFakeDrag(pasteboard: files)), [])
        XCTAssertEqual(target.draggingUpdated(DockFakeDrag(pasteboard: files)), [])
        XCTAssertFalse(target.prepareForDragOperation(DockFakeDrag(pasteboard: files)))
        target.destination = .tray
        XCTAssertEqual(target.draggingEntered(DockFakeDrag(pasteboard: text)), [])
        XCTAssertEqual(target.draggingEntered(DockFakeDrag(pasteboard: files)), .copy)
        XCTAssertEqual(target.draggingUpdated(DockFakeDrag(pasteboard: files)), .copy)
        XCTAssertEqual(controller.activeDropDestination, .tray)
        target.draggingExited(nil)
        XCTAssertNil(controller.activeDropDestination)
        controller.activeDropDestination = .airDrop; controller.fileDragActive = true
        target.concludeDragOperation(nil)
        XCTAssertTrue(controller.fileDragActive, "Another zone's highlight stays")
        XCTAssertTrue(target.prepareForDragOperation(DockFakeDrag(pasteboard: files)))
        XCTAssertTrue(target.performDragOperation(DockFakeDrag(pasteboard: filePasteboard([try file("Second.txt")]))))
        XCTAssertEqual(model.toolkit.files.count, 2)
        let panel = DockFakeOpenPanel(); panel.response = .cancel
        controller.chooseFiles = panel.choose
        target.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        XCTAssertEqual(panel.message, "Choose files to keep in the tray.")
        target.controller = nil
        XCTAssertFalse(target.accept(files))
    }

    // MARK: Notch views

    func testNotchShelfInteractions() throws {
        let model = model { $0.set(["focus", "notes", "search"], forKey: "widgets") }
        let controller = notchController(model)
        let harness = DockHarness(NotchShelfView(model: model, controller: controller), size: CGSize(width: 1100, height: 160))
        defer { harness.close() }
        harness.press("Expand DockGrove notch")
        XCTAssertTrue(controller.expanded)
        harness.spin(0.2)
        XCTAssertTrue(harness.has("Collapse notch"), "\(harness.labels())")
        harness.press("Open Focus from notch")
        XCTAssertEqual(controller.selectedWidget, .focus)
        harness.spin(0.3)
        harness.press("Close Focus controls")
        XCTAssertNil(controller.selectedWidget)
        harness.press("Open App search from notch")
        XCTAssertEqual(controller.selectedWidget, .search)
        controller.selectedWidget = nil
        harness.press("Files notch tab")
        XCTAssertTrue(controller.showingFiles)
        harness.spin(0.1)
        controller.airDropReview = true
        harness.spin(0.1)
        controller.fileDragActive = true
        harness.spin(0.1)
        controller.fileDragActive = false
        harness.press("Home notch tab")
        XCTAssertFalse(controller.showingFiles)
        harness.enter("Fo")
        harness.enter("zzzz-no-widget")
        harness.spin(0.1)
        controller.showingFiles = true
        harness.spin(0.1)
        controller.showingFiles = false
        harness.spin(0.1)
        harness.enter("")
        harness.spin(0.1)
        controller.showingFiles = true
        harness.spin(0.1)
        controller.showingFiles = false
        harness.spin(0.1)
        // With housing geometry known, the shelf mirrors its measurements.
        controller.update(suppressed: false)
        controller.setExpanded(true)
        harness.spin(0.1)
        harness.press("Collapse notch")
        XCTAssertFalse(controller.expanded)
    }

    func testNotchHomeTrayAndAirDropViews() throws {
        let model = model()
        let controller = notchController(model)
        let existing = try file("Existing.txt")
        model.toolkit.files = [existing.path, scratch.appendingPathComponent("Gone.txt").path]
        controller.setExpanded(true); controller.showingFiles = true
        let harness = DockHarness(NotchTrayView(model: model, kit: model.toolkit, controller: controller), size: CGSize(width: 1800, height: 120))
        defer { harness.close() }
        XCTAssertTrue(harness.has("File tray drop zone"), "\(harness.labels())")
        let panel = DockFakeOpenPanel(); panel.response = .cancel
        controller.chooseFiles = panel.choose
        harness.press("File tray drop zone")
        XCTAssertEqual(panel.message, "Choose files to keep in the tray.")
        harness.press("AirDrop drop zone")
        XCTAssertTrue(controller.airDropReview)
        harness.spin(0.1)
        // Review with nothing selected, then with files.
        XCTAssertTrue(harness.has("Close AirDrop review"), "\(harness.labels())")
        controller.airDropFiles = [existing, try file("Other.txt")]
        harness.spin(0.1)
        harness.act("Remove from AirDrop")
        XCTAssertEqual(controller.airDropFiles.count, 1)
        harness.chooseAnywhere("Remove from AirDrop")
        XCTAssertTrue(controller.airDropFiles.isEmpty)
        controller.airDropFiles = [existing]
        harness.spin(0.1)
        harness.chooseAnywhere("Clear selection")
        controller.airDropFiles = [existing]
        harness.spin(0.1)
        harness.act("Clear selection")
        XCTAssertTrue(controller.airDropFiles.isEmpty)
        controller.airDropFiles = [existing]
        harness.spin(0.1)
        let service = DockFakeSharingService(title: "Fake", image: NSImage(), alternateImage: nil, handler: {})
        controller.makeAirDropService = { service }
        harness.press("Choose device")
        XCTAssertEqual(service.performed.count, 1)
        harness.spin(0.1)
        controller.sharingService(service, didShareItems: [])
        harness.spin(0.1)
        harness.press("Add files to AirDrop")
        harness.press("Close AirDrop review")
        XCTAssertFalse(controller.airDropReview)

        // Tray items: open, reveal, remove; clearing keeps originals.
        harness.press("Existing.txt")
        if case .open(let url)? = effects.last { XCTAssertEqual(url.path, existing.path) } else { XCTFail("Tray item should open its file") }
        let itemPoint = try XCTUnwrap(harness.center("Existing.txt"))
        harness.choose("Reveal in Finder", inMenuAt: itemPoint)
        if case .reveal(let urls)? = effects.last { XCTAssertEqual(urls.map(\.path), [existing.path]) } else { XCTFail("Reveal should go through effects") }
        harness.choose("Remove shortcut", inMenuAt: itemPoint)
        XCTAssertEqual(controller.trayMessage, "Shortcut removed. Original file is unchanged.")
        harness.act("Remove shortcut")
        XCTAssertTrue(model.toolkit.files.isEmpty)
        model.toolkit.files = [existing.path]
        harness.spin(0.1)
        harness.chooseAnywhere("Clear tray")
        XCTAssertTrue(model.toolkit.files.isEmpty)
        model.toolkit.files = [existing.path]
        harness.spin(0.1)
        harness.act("Clear tray")
        XCTAssertTrue(model.toolkit.files.isEmpty)
        XCTAssertEqual(controller.trayMessage, "Original files are unchanged.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))

        let locked = DockHarness(NotchLockedTray(), size: CGSize(width: 300, height: 100))
        locked.close()
        let placeholder = DockHarness(NotchFocusPlaceholder(), size: CGSize(width: 400, height: 100))
        placeholder.close()
    }

    func testNotchHomeAndMusicCard() throws {
        let model = model()
        let controller = notchController(model)
        var opened: [ToolKind?] = []
        model.settingsAction = { opened.append(model.connectionSettingsKind) }
        let harness = DockHarness(NotchHomeView(model: model, kit: model.toolkit, controller: controller), size: CGSize(width: 700, height: 100))
        defer { harness.close() }
        harness.press("Open Apple Music connection settings")
        XCTAssertEqual(opened, [.appleMusic])
        harness.press("Start focus")
        XCTAssertNotNil(model.toolkit.focusEnd)
        harness.press("Pause focus")
        XCTAssertNil(model.toolkit.focusEnd)

        let player = MusicPlayer(name: "Fake Player", bundleID: "com.example.dockgrove.not-installed")
        var settings = 0
        let card = DockHarness(NotchMusicCard(player: player, openSettings: { settings += 1 }), size: CGSize(width: 400, height: 100))
        defer { card.close() }
        card.press("Open Fake Player connection settings")
        XCTAssertEqual(settings, 1)
        player.connected = true
        player.track = TrackSnapshot(title: "Song", artist: "Artist", playing: true)
        player.artwork = NSImage(size: NSSize(width: 8, height: 8))
        card.spin(0.1)
        card.press("Previous track")
        player.connected = true; card.spin()
        card.press("Play or pause music")
        player.connected = true; card.spin()
        card.press("Next track")
        XCTAssertFalse(player.connected, "A player that is not running disconnects instead of running AppleScript")
    }

    func testNotchSettingsView() {
        let model = model()
        var opened = 0
        model.openNotchAction = { opened += 1 }
        let changes = PassthroughSubject<Notification, Never>()
        var name: String? = nil
        let harness = DockHarness(NotchSettingsView(model: model, displayLookup: { name }, screenChanges: changes.eraseToAnyPublisher()), size: CGSize(width: 700, height: 500))
        defer { harness.close() }
        harness.press("Compact"); XCTAssertEqual(model.notchWidth, 640)
        harness.press("Wide"); XCTAssertEqual(model.notchWidth, 1000)
        harness.press("Balanced"); XCTAssertEqual(model.notchWidth, 760)
        name = "Built-in Display"
        changes.send(Notification(name: NSApplication.didChangeScreenParametersNotification))
        harness.spin(0.1)
        model.notchEnabled = true
        harness.spin(0.1)
        harness.press("Open notch")
        XCTAssertEqual(opened, 1)
        let live = DockHarness(NotchSettingsView(model: model), size: CGSize(width: 700, height: 500))
        live.close()
    }

    // MARK: Dock views

    private func studioPasteboard(_ item: DockStudioItem) throws -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let entry = NSPasteboardItem()
        entry.setData(try JSONEncoder().encode(item), forType: NSPasteboard.PasteboardType(UTType.dockStudioItem.identifier))
        pasteboard.writeObjects([entry])
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    /// Delivers a fake drop to whatever SwiftUI drop target sits under `point` (window coordinates).
    @discardableResult private func drop(_ pasteboard: NSPasteboard, at point: CGPoint, in harness: DockHarness, perform: Bool = true) -> Bool {
        let info = DockFakeDrag(pasteboard: pasteboard, location: point, window: harness.window)
        // SwiftUI registers one platform view per drop destination; deliver to the topmost under the point.
        var targets: [NSView] = []
        func collect(_ view: NSView) {
            if !view.registeredDraggedTypes.isEmpty, !view.isHiddenOrHasHiddenAncestor, view.convert(view.bounds, to: nil).contains(point) { targets.append(view) }
            view.subviews.forEach(collect)
        }
        collect(harness.host)
        guard let host = targets.last as? NSDraggingDestination else { XCTFail("No drop destination at \(point)"); return false }
        let entered = host.draggingEntered?(info)
        let updated = host.draggingUpdated?(info)
        _ = (entered, updated)
        harness.spin(0.05)
        guard perform else { host.draggingExited?(info); harness.spin(); return false }
        _ = host.prepareForDragOperation?(info)
        let accepted = host.performDragOperation?(info) ?? false
        host.concludeDragOperation?(info)
        harness.spin(0.3)
        return accepted
    }

    private var hostApp: DockApp { DockApp(url: Bundle.main.bundleURL) }

    private func dockModel(widgets: [String]) -> DockModel {
        let apps = ["/System/Library/CoreServices/Finder.app", "/System/Applications/Calculator.app", Bundle.main.bundlePath].filter { FileManager.default.fileExists(atPath: $0) }
        let model = model { defaults in
            defaults.set(apps, forKey: "apps")
            defaults.set(widgets, forKey: "widgets")
            defaults.set(0.35, forKey: "widthFraction")
        }
        return model
    }

    func testDockViewPagingDragsAndDrops() throws {
        let model = dockModel(widgets: ["focus", "notes", "tasks", "spacer", "separator", "stopwatch", "water", "habits", "progress", "clocks", "converter"])
        var settings = 0
        model.settingsAction = { settings += 1 }
        let harness = DockHarness(DockView(model: model), size: CGSize(width: 900, height: 160))
        defer { harness.close() }
        let fitting = harness.host.fittingSize
        harness.resize(CGSize(width: max(400, fitting.width), height: fitting.height))
        harness.press("DockGrove settings")
        XCTAssertEqual(settings, 1)
        harness.press("Next Dock page")
        harness.press("Next Dock page")
        harness.press("Previous Dock page")
        harness.press("Previous Dock page")

        // Reordering by dragging one tile onto another.
        harness.spin(0.2)
        let frames = model.tileFrames.filter { $0.key.hasPrefix("app:") }.sorted { $0.value.minX < $1.value.minX }
        XCTAssertGreaterThanOrEqual(frames.count, 2, "\(model.tileFrames)")
        if frames.count >= 2 {
            let before = model.orderedEntries.map(\.id)
            harness.drag(from: harness.windowPoint(CGPoint(x: frames[0].value.midX, y: frames[0].value.midY)), to: harness.windowPoint(CGPoint(x: frames[1].value.midX, y: frames[1].value.midY)))
            XCTAssertNotEqual(model.orderedEntries.map(\.id), before)
        }
        // A drag that starts away from every tile does nothing.
        harness.drag(from: CGPoint(x: 2, y: 2), to: CGPoint(x: 60, y: 2))

        // Releasing a tile on the next arrow sends it to the next page.
        harness.spin(0.1)
        if let next = harness.center("Next Dock page"), let first = model.tileFrames.filter({ $0.key.hasPrefix("app:") }).min(by: { $0.value.minX < $1.value.minX }) {
            harness.drag(from: harness.windowPoint(CGPoint(x: first.value.midX, y: first.value.midY)), to: next)
            harness.press("Previous Dock page"); harness.press("Previous Dock page")
            // Holding over the arrow turns pages, then releasing drops onto the turned page.
            harness.spin(0.1)
            if let tile = model.tileFrames.filter({ $0.key.hasPrefix("app:") }).min(by: { $0.value.minX < $1.value.minX }) {
                harness.drag(from: harness.windowPoint(CGPoint(x: tile.value.midX, y: tile.value.midY)), to: next, hold: 0.8)
            }
            harness.press("Previous Dock page"); harness.press("Previous Dock page")
            if let prev = harness.center("Previous Dock page"), let tile = model.tileFrames.filter({ $0.key.hasPrefix("app:") }).min(by: { $0.value.minX < $1.value.minX }) {
                harness.drag(from: harness.windowPoint(CGPoint(x: tile.value.midX, y: tile.value.midY)), to: prev)
            }
        } else { XCTFail("Dock arrows missing: \(harness.labels())") }

        // Moving the Dock by its handle.
        let handle = harness.windowPoint(CGPoint(x: harness.host.bounds.midX, y: 16 + 9))
        model.toolkit.edge = "Bottom"
        harness.drag(from: handle, to: CGPoint(x: handle.x + 40, y: handle.y + 20))
        XCTAssertEqual(model.toolkit.edge, "Floating")
        model.toolkit.edge = "Top"
        harness.drag(from: handle, to: CGPoint(x: handle.x - 40, y: handle.y - 20))
        harness.drag(from: handle, to: CGPoint(x: handle.x - 30, y: handle.y - 10))
        model.replacingDock = true
        harness.drag(from: handle, to: CGPoint(x: handle.x + 30, y: handle.y))
        model.replacingDock = false

        // Studio items dropped on tiles, arrows and the bar.
        let widget = try studioPasteboard(DockStudioItem(kind: .widget, value: "calculator"))
        harness.spin(0.1)
        let notes = try XCTUnwrap(model.tileFrames["notes"] ?? model.tileFrames.values.first)
        drop(widget, at: harness.windowPoint(CGPoint(x: notes.minX + 4, y: notes.midY)), in: harness, perform: false)
        drop(widget, at: harness.windowPoint(CGPoint(x: notes.minX + 4, y: notes.midY)), in: harness)
        let clock = try studioPasteboard(DockStudioItem(kind: .clock))
        if let tile = model.tileFrames.values.first { drop(clock, at: harness.windowPoint(CGPoint(x: tile.maxX - 3, y: tile.midY)), in: harness) }
        if let add = model.tileFrames["add"] { drop(try studioPasteboard(DockStudioItem(kind: .widget, value: "github")), at: harness.windowPoint(CGPoint(x: add.midX, y: add.midY)), in: harness) }
        if let next = harness.center("Next Dock page") { drop(try studioPasteboard(DockStudioItem(kind: .widget, value: "weather")), at: next, in: harness) }
        if let prev = harness.center("Previous Dock page") { drop(try studioPasteboard(DockStudioItem(kind: .widget, value: "colors")), at: prev, in: harness) }
        if let settingsPoint = harness.center("DockGrove settings") { drop(try studioPasteboard(DockStudioItem(kind: .widget, value: "controls")), at: CGPoint(x: settingsPoint.x - 20, y: settingsPoint.y), in: harness) }

        // Layout changes move tiles and arrows; removing entries clamps the page.
        harness.resize(CGSize(width: harness.window.frame.width + 120, height: harness.window.frame.height + 10))
        harness.press("Next Dock page")
        model.toolkit.enabled = ["focus"]
        harness.spin(0.2)
        model.theme = "Pearl"
        harness.spin(0.1)
    }

    func testDockViewWithoutScreenAndTiles() throws {
        let model = dockModel(widgets: ["focus"])
        let harness = DockHarness(DockView(model: model, screenLookup: { _ in nil }), size: CGSize(width: 1500, height: 160))
        defer { harness.close() }
        let fitting = harness.host.fittingSize
        harness.resize(CGSize(width: fitting.width, height: fitting.height))
        let handle = harness.windowPoint(CGPoint(x: harness.host.bounds.midX, y: 16 + 9))
        let alignment = model.alignment
        harness.drag(from: handle, to: CGPoint(x: handle.x + 50, y: handle.y))
        XCTAssertEqual(model.alignment, alignment, "Without a screen the handle cannot move the Dock")

        let activate = DockHarness(DockActivateButton(model: model, locked: true), size: CGSize(width: 200, height: 40))
        var settings = 0
        model.settingsAction = { settings += 1 }
        activate.press("Activate DockGrove")
        XCTAssertEqual(settings, 1)
        activate.close()
    }

    func testAppTileActions() throws {
        let model = dockModel(widgets: [])
        var launched: [URL] = []
        model.openApplication = { launched.append($0) }
        let app = hostApp
        let harness = DockHarness(AppTile(app: app, model: model), size: CGSize(width: 80, height: 80))
        defer { harness.close() }
        harness.click(CGPoint(x: 40, y: 45))
        XCTAssertEqual(launched, [app.url])
        harness.window.acceptsMouseMovedEvents = true
        harness.hover(CGPoint(x: 40, y: 45), entering: true)
        harness.hover(CGPoint(x: 200, y: 200), entering: false)
        let point = CGPoint(x: 40, y: 45)
        let titles = harness.menuTitles(at: point)
        XCTAssertTrue(titles.contains("Windows…"), "\(titles)")
        harness.choose("Windows…", inMenuAt: point)
        if case .present(let window)? = effects.last { XCTAssertEqual(window.title, "App windows") } else { XCTFail("Windows… should present a window") }
        model.appPickerWindow?.close()
        harness.choose("Replace app…", inMenuAt: point)
        if case .present(let window)? = effects.last { XCTAssertEqual(window.title, "Choose an application") } else { XCTFail("Replace app… should present the picker") }
        model.appPickerWindow?.close()
        harness.choose("Open " + app.name, inMenuAt: point)
        XCTAssertEqual(launched.count, 2)
        harness.choose("Move left", inMenuAt: point)
        harness.choose("Move right", inMenuAt: point)
        harness.choose(titles.contains("Hide app") ? "Hide app" : "Show app", inMenuAt: point)
        if case .setHidden(let running, _)? = effects.last { XCTAssertEqual(running.processIdentifier, ProcessInfo.processInfo.processIdentifier) } else { XCTFail("Hide should go through effects") }
        harness.choose("Show in Finder", inMenuAt: point)
        if case .reveal(let urls)? = effects.last { XCTAssertEqual(urls, [app.url]) } else { XCTFail("Reveal should go through effects") }
        harness.choose("Quit app", inMenuAt: point)
        if case .terminate(let running)? = effects.last { XCTAssertEqual(running.processIdentifier, ProcessInfo.processInfo.processIdentifier) } else { XCTFail("Quit should go through effects") }
        harness.choose("Unpin", inMenuAt: point)
        XCTAssertFalse(model.apps.contains(app))
        harness.spin(0.1)
        harness.choose("Undo app change", inMenuAt: point)
        XCTAssertTrue(model.apps.contains(app))
        harness.spin(0.1)
        harness.choose("Unpin", inMenuAt: point)
        harness.spin(0.1)
        harness.choose("Pin to Dock", inMenuAt: point)
        XCTAssertTrue(model.apps.contains(app))

        // Dropping a file opens it with the app.
        let fixture = try file("Dropped.txt")
        drop(filePasteboard([fixture]), at: point, in: harness)
        wait { !openFileEffects.isEmpty }
        XCTAssertEqual(openFileEffects.count, 1)
    }

    func testAcceptFilesAndAppWindows() throws {
        let model = dockModel(widgets: [])
        let app = hostApp
        let fixture = try file("Doc.txt")
        XCTAssertFalse(model.acceptFiles([NSItemProvider(object: "text" as NSString)], for: app))
        let data = NSItemProvider()
        data.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { done in done(fixture.dataRepresentation, nil); return nil }
        let remote = NSItemProvider()
        remote.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { done in done(URL(string: "https://example.com/a")!.dataRepresentation, nil); return nil }
        XCTAssertTrue(model.acceptFiles([NSItemProvider(contentsOf: fixture)!, data, remote], for: app))
        wait { openFileEffects.count >= 2 }
        let opens = openFileEffects
        XCTAssertEqual(opens.count, 2)
        if case .openFiles(let urls, let application, _)? = effects.first { XCTAssertEqual(urls.map(\.path), [fixture.path]); XCTAssertEqual(application, app.url) }
        opens.first?(nil, nil)
        opens.last?(nil, NSError(domain: NSCocoaErrorDomain, code: 1))
        wait { model.systemError != nil }
        XCTAssertEqual(model.systemError, "This app could not open the dropped file.")

        model.showAppWindows(app)
        model.showAppWindows(app)
        XCTAssertEqual(model.appPickerWindow?.title, "App windows")
        model.appPickerWindow?.close()

        let manager = DockFakeWindows()
        manager.windows = [ManagedWindow(id: "main", owner: .current, element: AXUIElementCreateApplication(getpid()), title: "Main window")]
        let harness = DockHarness(AppWindowsView(manager: manager, app: app), size: CGSize(width: 440, height: 400))
        defer { harness.close() }
        XCTAssertEqual(manager.calls.first, "refresh")
        harness.press("Allow Accessibility")
        harness.press("Refresh")
        var tables: [NSTableView] = []
        func collect(_ view: NSView) { if let table = view as? NSTableView { tables.append(table) }; view.subviews.forEach(collect) }
        collect(harness.host)
        let table = try XCTUnwrap(tables.first)
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        var pressed = false
        func walk(_ any: Any, _ depth: Int) {
            guard !pressed, depth < 30, let node = any as? NSObject else { return }
            if (DockHarness.get(node, "accessibilityLabel") as? String) == "Main window" || (DockHarness.get(node, "accessibilityTitle") as? String) == "Main window" {
                _ = node.perform(Selector(("accessibilityPerformPress"))); pressed = true; return
            }
            for child in (DockHarness.get(node, "accessibilityChildren") as? [Any]) ?? [] { walk(child, depth + 1) }
        }
        walk(table, 0)
        if !pressed { walk(cell, 0) }
        if !pressed {
            let rowFrame = table.convert(table.rect(ofRow: 0), to: nil)
            harness.click(CGPoint(x: rowFrame.minX + 30, y: rowFrame.midY))
        }
        harness.spin()
        XCTAssertEqual(manager.calls.suffix(3), ["request", "refresh", "focus:main"])
        manager.trusted = true
        harness.spin(0.1)
        XCTAssertFalse(harness.has("Allow Accessibility"))
    }

    func testUsageTileAndDetails() throws {
        let model = dockModel(widgets: [])
        func window(_ used: Double, mins: Int?) -> LimitWindow { LimitWindow(usedPercent: used, windowDurationMins: mins, resetsAt: Date().addingTimeInterval(3600).timeIntervalSince1970) }
        let both = LimitBucket(limitId: "codex", limitName: nil, primary: window(20, mins: 300), secondary: window(90, mins: 10080), planType: "plus")
        let secondaryOnly = LimitBucket(limitId: "other", limitName: "Other", primary: nil, secondary: window(50, mins: 60), planType: nil)
        let tile = DockHarness(UsageTile(model: model), size: CGSize(width: 220, height: 90))
        defer { tile.close() }
        model.fetching = true; tile.spin()
        model.fetching = false; model.usageError = "Offline"; tile.spin()
        model.usageError = nil; tile.spin()
        model.usage = UsageResponse(rateLimits: secondaryOnly, rateLimitsByLimitId: nil); tile.spin()
        model.usage = UsageResponse(rateLimits: nil, rateLimitsByLimitId: ["codex": both, "other": secondaryOnly]); tile.spin()
        model.toolkit.edge = "Top"; model.toolkit.richWidgets = false; tile.spin()
        tile.click(CGPoint(x: 110, y: 45))
        tile.spin(0.3)
        tile.click(CGPoint(x: 110, y: 45))
        tile.spin(0.2)

        model.fetchUsage = { _ in throw UsageError.service }
        var settings = 0
        model.settingsAction = { settings += 1 }
        model.refreshed = Date()
        model.usageError = "Stale"
        let details = DockHarness(UsageDetails(model: model), size: CGSize(width: 335, height: 400))
        defer { details.close() }
        details.press("Account settings")
        XCTAssertEqual(settings, 1)
        XCTAssertTrue(model.codexConnectionSelected)
        details.press("Refresh")
        model.fetching = true; model.usageError = nil; details.spin()
        model.fetching = false; model.usage = nil; model.refreshed = nil; details.spin()
        let bare = DockHarness(UsageDetails(model: model, showAccountSettings: false), size: CGSize(width: 335, height: 300))
        XCTAssertFalse(bare.has("Account settings"))
        bare.close()
    }

    // MARK: Workspace, design and drag source

    func testDockWorkspaceLifecycle() throws {
        let store = defaults()
        let workspace = DockWorkspace(defaults: store, testing: true)
        XCTAssertEqual(DockWorkspace(defaults: store, testing: false).prefix, "com.wavedock.development.extra.")
        workspace.restore()
        XCTAssertTrue(workspace.docks.isEmpty)
        var configured: [String] = []
        workspace.configure = { configured.append($0.id) }
        let first = UUID().uuidString
        let preset = UUID().uuidString
        UserDefaults(suiteName: workspace.prefix + preset)!.set("Named", forKey: "dockName")
        for id in [first, preset, UUID().uuidString, UUID().uuidString] { suites.append(workspace.prefix + id) }
        store.set([first, first, preset, "not-a-uuid"], forKey: "additionalDocks")
        workspace.restore()
        XCTAssertEqual(workspace.docks.map(\.id), [first, preset])
        XCTAssertEqual(workspace.docks[0].model.toolkit.edge, "Top")
        XCTAssertEqual(workspace.docks[1].model.dockName, "Named")
        workspace.add()
        suites.append(workspace.prefix + workspace.docks[2].id)
        XCTAssertEqual(workspace.docks[2].model.toolkit.edge, "Floating")
        workspace.add()
        XCTAssertEqual(workspace.docks.count, 3)
        XCTAssertEqual(configured.count, 3)
        let dock = workspace.docks[0]
        dock.model.dockName = "Renamed"
        dock.model.settingsAction?()
        if case .present(let window)? = effects.last { XCTAssertTrue(window === dock.settings); XCTAssertEqual(window.title, "Renamed") } else { XCTFail("Settings should present") }
        dock.model.closeSettingsAction?()

        let primary = model()
        var customized = 0
        primary.settingsAction = { customized += 1 }
        let harness = DockHarness(DockWorkspaceView(workspace: workspace, primary: primary), size: CGSize(width: 540, height: 700))
        defer { harness.close() }
        harness.press("Customize", index: 0)
        XCTAssertEqual(customized, 1)
        harness.press("Customize", index: 1)
        harness.enter("Desk", intoField: 0)
        harness.press("Visible")
        harness.press("Remove")
        XCTAssertEqual(workspace.docks.count, 2)
        harness.press("Add a Dock")
        XCTAssertEqual(workspace.docks.count, 3)
        suites.append(workspace.prefix + workspace.docks[2].id)
        workspace.remove("missing")
        XCTAssertEqual(store.stringArray(forKey: "additionalDocks"), workspace.docks.map(\.id))
    }

    func testDockAppearanceSettings() {
        let model = model()
        var manage = 0
        model.manageDocksAction = { manage += 1 }
        model.toolkit.edge = "Floating"
        let harness = DockHarness(DockAppearanceSettings(model: model), size: CGSize(width: 600, height: 500))
        defer { harness.close() }
        harness.press("Manage all docks…")
        XCTAssertEqual(manage, 1)
        harness.press("Reset position")
        XCTAssertEqual(model.toolkit.edge, "Bottom")
        model.isAdditionalDock = true
        harness.press("Reset position")
        XCTAssertEqual(model.toolkit.edge, "Top")
        DockAppearanceSettings(model: model).edge.wrappedValue = "Floating"
        XCTAssertEqual(model.toolkit.edge, "Floating")
        harness.spin(0.1)
        model.replacingDock = true
        harness.spin(0.1)
    }

    func testDesignHelpers() throws {
        XCTAssertNotNil(BrandIcon.loadArtwork("dockgrove-missing-image").size)
        _ = AccentPalette.color("#FF8800")
        _ = AccentPalette.color("not a color")
        _ = AccentPalette.color("Mint")
        XCTAssertEqual(AccentPalette.hex(Color(red: 1, green: 0, blue: 0)), "#FF0000")
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 2, height: 2)))
        XCTAssertEqual(AccentPalette.hex(Color(nsColor: pattern)), "#FFFFFF")
        let menu = BrandIcon.menuImage
        XCTAssertNotNil(menu.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let harness = DockHarness(VStack {
            BrandIcon().frame(width: 20, height: 20)
            Sparkline(values: [1, 4, 2, 8], color: .blue).frame(width: 80, height: 20)
            Sparkline(values: [], color: .blue).frame(width: 80, height: 20)
            RingMetric(value: 0.4, label: "40", color: .green).frame(width: 40, height: 40)
            ShapedWidgetFace(kind: .weather, style: .pill, caption: "72°", accent: .blue, weatherAttribution: true).frame(width: 160, height: 60)
            ShapedWidgetFace(kind: .weather, style: .circle, caption: "72°", accent: .blue, weatherAttribution: true).frame(width: 70, height: 70)
        }, size: CGSize(width: 200, height: 300))
        harness.close()
    }

    func testNativeStudioDragSource() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let source = DockRecordingSource(frame: NSRect(x: 20, y: 20, width: 100, height: 50))
        container.addSubview(source)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        var clicks = 0
        source.clicked = { clicks += 1 }
        XCTAssertTrue(source.acceptsFirstMouse(for: nil))
        source.mouseDown(with: event(.leftMouseDown, 40, 40))
        source.mouseDragged(with: event(.leftMouseDragged, 50, 50))
        XCTAssertTrue(source.sessions.isEmpty, "Without an item there is nothing to drag")
        source.item = DockStudioItem(kind: .widget, value: "focus")
        source.mouseDragged(with: event(.leftMouseDragged, 41, 41))
        XCTAssertTrue(source.sessions.isEmpty, "Small movements stay clicks")
        source.mouseDragged(with: event(.leftMouseDragged, 60, 60))
        source.mouseDragged(with: event(.leftMouseDragged, 70, 70))
        XCTAssertEqual(source.sessions.count, 1)
        source.mouseUp(with: event(.leftMouseUp, 70, 70))
        XCTAssertEqual(clicks, 0)
        let session = unsafeBitCast(NSObject(), to: NSDraggingSession.self)
        XCTAssertEqual(source.draggingSession(session, sourceOperationMaskFor: .outsideApplication), .copy)
        source.draggingSession(session, endedAt: .zero, operation: .copy)
        source.mouseDown(with: event(.leftMouseDown, 40, 40))
        source.mouseUp(with: event(.leftMouseUp, 40, 40))
        XCTAssertEqual(clicks, 1)
        source.mouseDown(with: event(.leftMouseDown, 40, 40))
        source.mouseUp(with: event(.leftMouseUp, 190, 95))
        source.mouseUp(with: event(.leftMouseUp, 40, 40))
        XCTAssertEqual(clicks, 1)
        let orphan = DockRecordingSource(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        orphan.item = DockStudioItem(kind: .clock)
        orphan.mouseDown(with: event(.leftMouseDown, 0, 0))
        orphan.mouseDragged(with: event(.leftMouseDragged, 30, 30))
        XCTAssertEqual(orphan.sessions.count, 1)
    }
}
