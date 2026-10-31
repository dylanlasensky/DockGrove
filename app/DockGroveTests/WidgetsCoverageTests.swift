import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

/// Records widget effects instead of performing them.
@MainActor final class WidgetEffectLog {
    var effects: [WidgetEffect] = []
    var openResult = true
    var handler: WidgetEffects { WidgetEffects { [unowned self] effect in self.effects.append(effect); if case .open = effect { return self.openResult }; return true } }
    var names: [String] { effects.map(Self.name) }
    static func name(_ effect: WidgetEffect) -> String {
        switch effect {
        case .open(let url): return "open:" + url.absoluteString
        case .reveal(let urls): return "reveal:" + urls.map(\.path).joined(separator: ",")
        case .copy(let text): return "copy:" + text
        case .characterPalette: return "palette"
        case .launch(_, let app): return "launch:" + app.id
        case .exportProfiles: return "export"
        case .importProfiles: return "import"
        case .setLogin(_, let on): return "login:\(on)"
        case .browse(_, let url): return "browse:" + url.path
        case .chooseFolder: return "chooseFolder"
        case .screenshot: return "screenshot"
        case .pickColor: return "pickColor"
        case .loadReminders: return "loadReminders"
        case .completeReminder: return "completeReminder"
        case .addFiles: return "addFiles"
        case .fetchWeather: return "fetchWeather"
        case .refreshGitHub: return "refreshGitHub"
        case .music(_, let command): return "music:" + command.rawValue
        }
    }
}

final class WidgetsKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts a SwiftUI view in an offscreen borderless window and drives it through AppKit and accessibility.
@MainActor final class WidgetHost {
    let window: NSWindow
    let host: NSView
    /// SwiftUI only builds its accessibility tree once an assistive client asks for it.
    static func enableAccessibility() {
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
    }
    init<V: View>(_ view: V, width: CGFloat = 380, height: CGFloat = 760, scheme: ColorScheme = .light) {
        let hosting = NSHostingView(rootView: view.frame(width: width, height: height).environment(\.colorScheme, scheme))
        // One window, ordered on screen once and reused: re-ordering fresh windows after a text field
        // has shown the system completion list trips an AppKit remote-view assertion.
        window = Self.shared
        window.makeFirstResponder(nil)
        window.setContentSize(NSSize(width: width, height: height))
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting; host = hosting
        hosting.setFrameSize(NSSize(width: width, height: height))
        window.orderFront(nil)
        pump(0.1)
        Self.enableAccessibility()
        pump(0.2)
    }
    static let shared: NSWindow = {
        let window = WidgetsKeyWindow(contentRect: NSRect(x: -12000, y: -12000, width: 380, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = false
        window.initialFirstResponder = nil
        return window
    }()
    deinit { let window = window, host = host; MainActor.assumeIsolated { if window.contentView === host { window.makeFirstResponder(nil); window.contentView = NSView() } } }
    func pump(_ seconds: TimeInterval = 0.08) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
        host.display()
        resignTextFocus()
    }
    /// Never leaves a text field editing: a focused field summons the AutoFill view service,
    /// whose remote view trips an AppKit assertion when it is torn down.
    func resignTextFocus() {
        if window.firstResponder is NSText || window.firstResponder is NSTextField { window.makeFirstResponder(nil) }
    }
    func close() { window.makeFirstResponder(nil); window.contentView = NSView() }

    // MARK: Accessibility (SwiftUI nodes answer the informal NSAccessibility messages only)
    static func ax<T>(_ object: NSObject, _ name: String) -> T? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? T
    }
    static func axBool(_ object: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return false }
        typealias Call = @convention(c) (NSObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Call.self)(object, selector)
    }
    func elements() -> [NSObject] {
        var out: [NSObject] = []
        func walk(_ object: NSObject, _ depth: Int) {
            guard depth < 40 else { return }
            out.append(object)
            for child in (Self.ax(object, "accessibilityChildren") as [Any]?) ?? [] { if let child = child as? NSObject { walk(child, depth + 1) } }
        }
        walk(host, 0)
        return out
    }
    static func role(_ object: NSObject) -> String { ax(object, "accessibilityRole") ?? "" }
    static func text(_ object: NSObject) -> [String] {
        [ax(object, "accessibilityLabel") as String?, ax(object, "accessibilityTitle") as String?, ax(object, "accessibilityValue") as String?, ax(object, "accessibilityHelp") as String?].compactMap { $0 }.filter { !$0.isEmpty }
    }
    func labels() -> [String] { elements().map { Self.role($0) + ":" + Self.text($0).joined(separator: "|") } }
    func find(_ label: String, roles: Set<String> = ["AXButton", "AXCheckBox", "AXMenuButton", "AXPopUpButton", "AXRadioButton", "AXLink", "AXSwitch", "AXToggle", "AXDisclosureTriangle"]) -> [NSObject] {
        elements().filter { roles.contains(Self.role($0)) && Self.text($0).contains(label) }
    }
    /// Presses the `index`th accessibility button whose label, title, value or help matches.
    @discardableResult func press(_ label: String, index: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let matches = find(label)
        guard matches.indices.contains(index) else { XCTFail("No button \"\(label)\" #\(index); have \(labels())", file: file, line: line); return false }
        let pressed = Self.axBool(matches[index], "accessibilityPerformPress")
        pump()
        return pressed
    }
    /// Opens the pop-up (or menu button / context menu via `action`) matching `label` and picks `item`
    /// from the menu while it tracks, then dismisses it.
    @discardableResult func choose(_ item: String, in label: String, index: Int = 0, action: String = "accessibilityPerformPress", roles: Set<String> = ["AXPopUpButton", "AXMenuButton"], file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let matches = find(label, roles: roles)
        guard matches.indices.contains(index) else { XCTFail("No pop-up \"\(label)\"; have \(labels())", file: file, line: line); return false }
        return pick(item, file: file, line: line) { _ = Self.axBool(matches[index], action) }
    }
    /// Runs `open`, and when a menu starts tracking performs `item` in it (searching submenus) and closes it.
    @discardableResult func pick(_ item: String, file: StaticString = #filePath, line: UInt = #line, open: () -> Void) -> Bool {
        var picked = false, seen: [String] = []
        let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated {
                menu.update()
                seen = menu.allTitles
                RunLoop.main.perform(inModes: [.eventTracking, .default, .modalPanel]) {
                    MainActor.assumeIsolated {
                        menu.update(); seen = menu.allTitles
                        if !picked { picked = menu.perform(item) }
                        menu.cancelTrackingWithoutAnimation()
                    }
                }
            }
        }
        open()
        pump(0.2)
        NotificationCenter.default.removeObserver(token)
        if !picked { XCTFail("Menu item \"\(item)\" not picked; saw \(seen)", file: file, line: line) }
        return picked
    }
    func axAction(_ label: String, _ action: String, roles: Set<String>, index: Int = 0) {
        let matches = find(label, roles: roles)
        guard matches.indices.contains(index) else { XCTFail("No element \(label)"); return }
        _ = Self.axBool(matches[index], action); pump()
    }
    /// Center of a matching element in the hosting view's (flipped) coordinates.
    func center(of label: String, roles: Set<String>? = nil, index: Int = 0) -> CGPoint? {
        let matches = roles.map { find(label, roles: $0) } ?? elements().filter { Self.text($0).contains(label) }
        guard matches.indices.contains(index) else { return nil }
        let selector = NSSelectorFromString("accessibilityFrame"), object = matches[index]
        guard object.responds(to: selector) else { return nil }
        typealias Frame = @convention(c) (NSObject, Selector) -> NSRect
        let screen = unsafeBitCast(object.method(for: selector), to: Frame.self)(object, selector)
        let inWindow = window.convertFromScreen(screen)
        let local = host.convert(inWindow, from: nil)
        return CGPoint(x: local.midX, y: local.midY)
    }
    /// Delivers a file drop at `point` through the hosting view's dragging-destination methods.
    @discardableResult func drop(_ urls: [URL], at point: CGPoint) -> Bool {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WidgetsCoverage-" + UUID().uuidString))
        pasteboard.clearContents(); pasteboard.writeObjects(urls as [NSURL])
        let info = WidgetsDraggingInfo(window: window, location: host.convert(point, to: nil), pasteboard: pasteboard)
        var result = false
        let location = host.convert(point, to: nil)
        // SwiftUI's drop targets are private subviews registered for dragged types.
        let targets = views(NSView.self).filter { !$0.registeredDraggedTypes.isEmpty && $0.convert($0.bounds, to: nil).contains(location) }
        for candidate in targets where !result {
            do {
                let destination = candidate as NSDraggingDestination
                _ = destination.draggingEntered?(info); pump(0.05)
                _ = destination.draggingUpdated?(info); pump(0.05)
                if destination.prepareForDragOperation?(info) ?? true { result = destination.performDragOperation?(info) ?? false }
                destination.concludeDragOperation?(info)
                destination.draggingEnded?(info)
            }
        }
        pump(0.3)
        return result
    }
    /// First element text starting with `prefix` (e.g. a tile's "Title: caption" label).
    func label(prefix: String) -> String? { elements().lazy.flatMap(Self.text).first { $0.hasPrefix(prefix) } }
    func contains(_ fragment: String) -> Bool { elements().contains { Self.text($0).contains { $0.contains(fragment) } } }
    func has(_ label: String) -> Bool { elements().contains { Self.text($0).contains(label) } }
    func pressAll(_ label: String) { for index in find(label).indices.reversed() { press(label, index: index) } }

    // MARK: AppKit controls
    func views<T: NSView>(_ type: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ view: NSView) { if let match = view as? T { out.append(match) }; view.subviews.forEach(walk) }
        walk(host)
        return out
    }
    /// Types into the `index`th text field and submits it (Return), firing `onSubmit`.
    func submit(_ text: String, field index: Int = 0) {
        guard let field = editableField(index) else { return }
        edit(field, text)
        if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
        pump()
    }
    func type(_ text: String, field index: Int = 0) {
        guard let field = editableField(index) else { return }
        edit(field, text)
        pump()
    }
    private func editableField(_ index: Int) -> NSTextField? {
        let fields = views(NSTextField.self).filter { $0.isEditable }
        guard fields.indices.contains(index) else { XCTFail("No text field #\(index)"); return nil }
        return fields[index]
    }
    /// Reports an edit the way AppKit does to SwiftUI, without making the field first responder:
    /// focusing a field summons the AutoFill view service, whose remote view crashes on teardown.
    private func edit(_ field: NSTextField, _ text: String) {
        field.stringValue = text
        let editor = NSTextView(); editor.string = text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field, userInfo: ["NSFieldEditor": editor])
    }
    /// Chooses an item in the `index`th pop-up button (SwiftUI Picker).
    func choose(_ title: String, popup index: Int = 0, file: StaticString = #filePath, line: UInt = #line) {
        let popups = views(NSPopUpButton.self)
        guard popups.indices.contains(index) else { XCTFail("No pop-up #\(index)", file: file, line: line); return }
        let popup = popups[index]
        guard let item = popup.item(withTitle: title) else { XCTFail("No item \(title) in \(popup.itemTitles)", file: file, line: line); return }
        popup.select(item)
        if let action = popup.action { NSApp.sendAction(action, to: popup.target, from: popup) }
        pump()
    }
    /// Builds the context menu for the element labelled `label` (as a right-click would) and performs `item`.
    @discardableResult func contextPick(_ item: String, on label: String, roles: Set<String>? = ["AXButton"], file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let point = center(of: label, roles: roles) else { XCTFail("No element \(label); have \(labels())", file: file, line: line); return false }
        let location = host.convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return false }
        var view: NSView? = host.hitTest(location) ?? host
        while let candidate = view {
            if let menu = candidate.menu(for: event) {
                menu.update()
                let done = menu.perform(item)
                pump()
                if !done { XCTFail("No menu item \(item) in \(menu.allTitles)", file: file, line: line) }
                return done
            }
            view = candidate.superview
        }
        XCTFail("No context menu at \(label)", file: file, line: line); return false
    }
}

final class WidgetsDraggingInfo: NSObject, NSDraggingInfo {
    let window: NSWindow; let location: NSPoint; let pasteboard: NSPasteboard
    init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard) { self.window = window; self.location = location; self.pasteboard = pasteboard }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .generic, .link, .move] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 4242 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 1 } set {} }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
    // Private bookkeeping AppKit's SwiftUI drop target expects from a real dragging session.
    private var lastOperation: UInt = 0
    @objc func _lastDragDestinationOperation() -> UInt { lastOperation }
    @objc func _setLastDragDestinationOperation(_ value: UInt) { lastOperation = value }
}

extension NSMenu {
    /// Performs the item with `title`, searching submenus.
    @discardableResult func perform(_ title: String) -> Bool {
        for (index, item) in items.enumerated() {
            if item.title == title { performActionForItem(at: index); return true }
            if let submenu = item.submenu { submenu.update(); if submenu.perform(title) { return true } }
        }
        return false
    }
    var allTitles: [String] { items.flatMap { [$0.title] + ($0.submenu?.allTitles ?? []) } }
}

/// A fresh temporary directory with symlinks resolved the way FileManager listings report them.
func widgetsTempDir(_ prefix: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory.path
    let real = realpath(base, nil).map { p -> String in defer { free(p) }; return String(cString: p) } ?? base
    let url = URL(fileURLWithPath: real, isDirectory: true).appendingPathComponent(prefix + "-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func widgetDefaults() -> UserDefaults { UserDefaults(suiteName: "WidgetsCoverage-" + UUID().uuidString)! }

/// Replaces every system seam on the model, its toolkit, utilities and music players with fakes,
/// so no test can reach a live panel, the general pasteboard, the network, or launch an app.
@MainActor func widgetsIsolate(_ model: DockModel, file: StaticString = #filePath, line: UInt = #line) {
    model.openApplication = { XCTFail("live launch of \($0.path)", file: file, line: line) }
    model.chooseExportURL = { XCTFail("live save panel", file: file, line: line); return nil }
    model.chooseImportURL = { XCTFail("live open panel", file: file, line: line); return nil }
    model.fetchUsage = { _ in throw URLError(.notConnectedToInternet) }
    widgetsIsolate(model.toolkit, file: file, line: line)
}
@MainActor func widgetsIsolate(_ kit: Toolkit, file: StaticString = #filePath, line: UInt = #line) {
    kit.pasteboard = NSPasteboard(name: NSPasteboard.Name("WidgetsCoverage-" + UUID().uuidString))
    kit.chooseFiles = { XCTFail("live file panel", file: file, line: line); return [] }
    kit.weatherFetch = { _ in throw URLError(.notConnectedToInternet) }
    kit.applicationRoots = []
    widgetsIsolate(kit.utilities, file: file, line: line)
    for player in [kit.spotify, kit.appleMusic] { widgetsIsolate(player) }
}
@MainActor func widgetsIsolate(_ utilities: Utilities, file: StaticString = #filePath, line: UInt = #line) {
    utilities.chooseDirectory = { _ in XCTFail("live folder panel", file: file, line: line); return nil }
    utilities.sampleColor = { $0(nil) }
    utilities.capture = { nil }
    utilities.setLoginItem = { _ in }
    utilities.loginStatus = { .notRegistered }
    utilities.chime = {}
}
@MainActor func widgetsIsolate(_ player: MusicPlayer) {
    player.locate = { _ in nil }
    player.launch = { _ in }
    player.isRunning = { _ in false }
    player.runScript = { _, _ in throw URLError(.cancelled) }
    player.fetchArtwork = { _ in throw URLError(.notConnectedToInternet) }
}

/// URL protocol stub for URLSession seams; responses are keyed by URL path.
final class WidgetsStubProtocol: URLProtocol {
    struct Stub { var status = 200; var mime = "application/json"; var body = Data(); var redirect: URL? = nil; var length: Int? = nil; var fail = false }
    nonisolated(unsafe) static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) static var requests: [URL] = []
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetsStubProtocol.self]
        return configuration
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.append(url)
        let stub = Self.stubs[url.host.map { $0 + url.path } ?? url.path] ?? Stub(status: 404)
        if stub.fail { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        if let redirect = stub.redirect {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirect.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        var headers = ["Content-Type": stub.mime]
        headers["Content-Length"] = String(stub.length ?? stub.body.count)
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Waits on the main run loop until `condition` holds or the timeout passes.
@MainActor func widgetsWait(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}

/// A small valid PNG drawn in memory.
func widgetsPNG(color: NSColor = .systemRed, size: Int = 24) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// A short silent 16-bit mono WAV.
func widgetsWAV(frames: Int = 800) -> Data {
    var data = Data()
    func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = frames * 2
    data.append(contentsOf: Array("RIFF".utf8)); le(UInt32(36 + bytes)); data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1)); le(UInt32(8000)); le(UInt32(16000)); le(UInt16(2)); le(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); le(UInt32(bytes)); data.append(Data(count: bytes))
    return data
}

func widgetsGitHubSnapshot(run: Bool, warning: String?) throws -> GitHubSnapshot {
    let repo = try JSONDecoder().decode(RepositorySummary.self, from: Data(#"{"full_name":"o/r","html_url":"https://github.com/o/r","stargazers_count":5,"forks_count":2,"open_issues_count":3,"description":null}"#.utf8))
    let issues = try JSONDecoder().decode([RepositoryIssue].self, from: Data(#"[{"id":1,"number":7,"title":"Bug","html_url":"https://github.com/o/r/issues/7","pull_request":null},{"id":2,"number":8,"title":"Fix","html_url":"https://github.com/o/r/pull/8","pull_request":{"url":null}},{"id":3,"number":9,"title":"Evil","html_url":"https://evil.example/9","pull_request":null}]"#.utf8))
    let runs = try JSONDecoder().decode(RepositoryRuns.self, from: Data(#"{"workflow_runs":[{"id":1,"name":null,"status":"in_progress","conclusion":null,"html_url":"https://github.com/o/r/actions/runs/1"}]}"#.utf8))
    return GitHubSnapshot(repository: repo, issues: issues, run: run ? runs.workflow_runs.first : nil, activityWarning: warning)
}
