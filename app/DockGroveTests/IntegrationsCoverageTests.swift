import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

/// Hosting and reflection helpers for the Integrations coverage tests. SwiftUI buttons on macOS
/// are not AppKit controls, so actions are found by reflecting over a view's `body` and invoked
/// directly; bodies are covered by hosting the views in an offscreen window.
@MainActor enum IntegrationsUI {
    struct FoundButton { let title: String; let action: @MainActor () -> Void }

    /// Evaluates `body` generically so tests never link against SwiftUI's private opaque result types.
    @_optimize(none) @inline(never) static func body(_ view: any View) -> Any { view.body }

    static func spin(_ seconds: TimeInterval = 0.02) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Spins the main run loop until `condition` holds or `timeout` passes.
    @discardableResult static func wait(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { spin() }
        return condition()
    }

    /// Awaits `condition` from an async test, yielding the main actor between checks.
    @discardableResult static func settle(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        return condition()
    }

    static func render<V: View>(_ view: V, setup: Bool = true, width: CGFloat = 420, height: CGFloat = 1000, dark: Bool = false) {
        let host = NSHostingView(rootView: view.environment(\.connectionSetupAllowed, setup).frame(width: width, height: height))
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        spin(0.05)
        window.orderOut(nil)
        window.contentView = nil
    }

    private static func isClass(_ value: Any) -> Bool { Mirror(reflecting: value).displayStyle == .class }

    static func strings(in value: Any, depth: Int = 0) -> [String] {
        guard depth < 12 else { return [] }
        if let text = value as? String { return [text] }
        return Mirror(reflecting: value).children.flatMap { strings(in: $0.value, depth: depth + 1) }
    }

    static func buttons(in value: Any) -> [FoundButton] {
        var result: [FoundButton] = []
        func walk(_ value: Any, _ depth: Int) {
            guard depth < 80, !isClass(value) else { return }
            let mirror = Mirror(reflecting: value)
            if String(describing: type(of: value)).hasPrefix("Button<"),
               let box = mirror.children.first(where: { $0.label == "action" })?.value,
               let closure = Mirror(reflecting: box).children.first(where: { $0.label == "closure" })?.value as? @MainActor () -> Void {
                let label = mirror.children.first(where: { $0.label == "label" })?.value ?? ""
                result.append(FoundButton(title: strings(in: label).joined(separator: " "), action: closure))
            }
            for child in mirror.children { walk(child.value, depth + 1) }
        }
        walk(value, 0)
        return result
    }

    /// Presses every button whose label contains `title`; fails if none is found.
    static func press(_ value: Any, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = buttons(in: value).filter { $0.title.contains(title) }
        XCTAssertFalse(matches.isEmpty, "No button labelled \(title) in \(buttons(in: value).map(\.title))", file: file, line: line)
        matches.forEach { $0.action() }
    }

    static func values<T>(_ type: T.Type, in value: Any) -> [T] {
        var result: [T] = []
        func walk(_ value: Any, _ depth: Int) {
            guard depth < 80 else { return }
            if let match = value as? T { result.append(match); return }
            guard !isClass(value) else { return }
            for child in Mirror(reflecting: value).children { walk(child.value, depth + 1) }
        }
        walk(value, 0)
        return result
    }

    /// Plain closures stored under `label`, such as `appear` for onAppear or a view's callback.
    static func closures(_ label: String, in value: Any) -> [() -> Void] {
        var result: [() -> Void] = []
        func walk(_ value: Any, _ depth: Int) {
            guard depth < 80, !isClass(value) else { return }
            for child in Mirror(reflecting: value).children {
                if child.label == label {
                    if let closure = child.value as? () -> Void { result.append(closure); continue }
                    if let closure = child.value as? @MainActor () -> Void { result.append({ MainActor.assumeIsolated { closure() } }); continue }
                }
                walk(child.value, depth + 1)
            }
        }
        walk(value, 0)
        return result
    }

    /// A Toggle's binding. SwiftUI stores it as `Binding<ToggleState>`, an internal one-byte enum,
    /// so it is read and written through the byte values of a constant on and off toggle.
    @MainActor struct ToggleHandle {
        let binding: IntegrationsAnyBinding
        private static func byte(_ on: Bool) -> UInt8 { values(IntegrationsAnyBinding.self, in: Toggle("", isOn: .constant(on))).first!.byte }
        var isOn: Bool {
            get { binding.byte == Self.byte(true) }
            nonmutating set { binding.setByte(Self.byte(newValue)) }
        }
    }
    static func toggles(in value: Any) -> [ToggleHandle] {
        values(IntegrationsAnyBinding.self, in: value).filter { $0.valueTypeName == "ToggleState" }.map(ToggleHandle.init)
    }

    static func appear(_ value: Any) { closures("appear", in: value).forEach { $0() } }

    static func temporaryDirectory(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DockGroveIntegrations." + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path); try? FileManager.default.removeItem(at: url) }
        return url
    }

    static func defaults(_ test: XCTestCase) -> UserDefaults {
        let suite = "DockGroveIntegrations." + UUID().uuidString
        test.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// Copies a fixture tool under `name`; fixtures choose their behavior from the name they run as.
    static func fixture(_ tool: String, named name: String, in folder: URL) throws -> String {
        let path = folder.appendingPathComponent(name).path
        try FileManager.default.copyItem(atPath: try Fixtures.path(tool), toPath: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }
}

/// Type-erased access to any `Binding`, including bindings to SwiftUI's internal types.
protocol IntegrationsAnyBinding {
    var valueTypeName: String { get }
    var byte: UInt8 { get }
    func setByte(_ byte: UInt8)
}
extension Binding: IntegrationsAnyBinding {
    var valueTypeName: String { String(describing: Value.self) }
    var byte: UInt8 { withUnsafeBytes(of: wrappedValue) { $0[0] } }
    func setByte(_ byte: UInt8) {
        precondition(MemoryLayout<Value>.size == 1)
        var raw = byte
        wrappedValue = withUnsafeBytes(of: &raw) { $0.load(as: Value.self) }
    }
}

// MARK: - Organization API usage

@MainActor final class IntegrationsAIUsageTests: XCTestCase {
    private var originals: (String, (CFDictionary, CFDictionary) -> OSStatus, (CFDictionary) -> OSStatus, (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus, (CFDictionary) -> OSStatus)!

    override func setUp() {
        super.setUp()
        originals = (UsageKeychain.service, UsageKeychain.update, UsageKeychain.add, UsageKeychain.copy, UsageKeychain.delete)
        UsageKeychain.service = "app.wavedock.ai-usage.tests." + UUID().uuidString
    }

    override func tearDown() {
        UsageKeychain.update = originals.1; UsageKeychain.add = originals.2; UsageKeychain.copy = originals.3; UsageKeychain.delete = originals.4
        for provider in AIProvider.allCases { try? UsageKeychain.remove(provider) }
        UsageKeychain.service = originals.0
        super.tearDown()
    }

    /// In-memory keychain so widget tests never depend on the login keychain state.
    private final class MemoryKeychain {
        var items: [String: Data] = [:]
        var failUpdate = false, failDelete = false
        func install() {
            UsageKeychain.update = { query, attributes in
                if self.failUpdate { return errSecAuthFailed }
                let account = (query as NSDictionary)[kSecAttrAccount as String] as! String
                guard self.items[account] != nil else { return errSecItemNotFound }
                self.items[account] = (attributes as NSDictionary)[kSecValueData as String] as? Data; return errSecSuccess
            }
            UsageKeychain.add = { item in
                let dictionary = item as NSDictionary
                self.items[dictionary[kSecAttrAccount as String] as! String] = dictionary[kSecValueData as String] as? Data; return errSecSuccess
            }
            UsageKeychain.copy = { query, result in
                guard let data = self.items[(query as NSDictionary)[kSecAttrAccount as String] as! String] else { return errSecItemNotFound }
                result.pointee = data as CFData; return errSecSuccess
            }
            UsageKeychain.delete = { query in
                if self.failDelete { return errSecAuthFailed }
                self.items[(query as NSDictionary)[kSecAttrAccount as String] as! String] = nil; return errSecSuccess
            }
        }
    }

    private let openAIReport = Data(#"{"data":[{"results":[{"input_tokens":100,"output_tokens":20}]}],"has_more":false,"next_page":null}"#.utf8)

    func testProviderMetadataAndFailureText() throws {
        XCTAssertEqual(AIProvider.allCases.map(\.title), ["OpenAI API", "Claude API", "Cursor team"])
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.documentation.scheme, "https")
            XCTAssertEqual(provider.accountURL.scheme, "https")
        }
        for failure in [AIUsageFailure.invalid, .denied, .limited, .service, .keychain] { XCTAssertFalse(failure.errorDescription!.isEmpty) }
    }

    func testDecodeRejectsPartialCursorPagesAndOverflow() throws {
        let partial = Data(#"{"data":[{"agentRequests":1,"chatRequests":1,"composerRequests":1,"totalTabsAccepted":1}],"pagination":{"hasNextPage":true}}"#.utf8)
        XCTAssertThrowsError(try AIProvider.cursor.decode(partial))
        let complete = Data(#"{"data":[{"agentRequests":1,"chatRequests":1,"composerRequests":1,"totalTabsAccepted":1}],"pagination":{"hasNextPage":false}}"#.utf8)
        XCTAssertEqual(try AIProvider.cursor.decode(complete).totals, [1, 1, 1, 1])
        let overflow = Data(#"{"data":[{"results":[{"input_tokens":9000000000000000000,"output_tokens":1},{"input_tokens":9000000000000000000,"output_tokens":1}]}],"has_more":false}"#.utf8)
        XCTAssertThrowsError(try AIProvider.openai.decode(overflow))
        XCTAssertThrowsError(try AIProvider.anthropic.decode(Data(#"{"data":[{"results":[{"uncached_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":1}]}],"has_more":false}"#.utf8)))
        XCTAssertThrowsError(try AIProvider.openai.decode(Data(#"{"data":[{"noresults":1}],"has_more":false}"#.utf8)))
        XCTAssertThrowsError(try AIProvider.openai.decode(Data(#"{"data":[]}"#.utf8)))
    }

    func testFetchStopsRunawayPaginationOversizedReportsAndOverflow() async throws {
        var calls = 0
        do {
            _ = try await AIUsageClient.fetch(.openai, key: "fixture") { _ in
                calls += 1
                return (Data(#"{"data":[],"has_more":true,"next_page":"p\#(calls)"}"#.utf8), 200)
            }
            XCTFail("Runaway pagination accepted")
        } catch { XCTAssertEqual(error as? AIUsageFailure, .invalid) }
        XCTAssertEqual(calls, 100)
        do { _ = try await AIUsageClient.fetch(.openai, key: "fixture") { _ in (Data(count: 20_000_001), 200) }; XCTFail("Oversized report accepted") }
        catch { XCTAssertEqual(error as? AIUsageFailure, .invalid) }
        var page = 0
        do {
            _ = try await AIUsageClient.fetch(.openai, key: "fixture") { _ in
                page += 1
                return (Data(#"{"data":[{"results":[{"input_tokens":9000000000000000000,"output_tokens":0}]}],"has_more":true,"next_page":"p\#(page)"}"#.utf8), 200)
            }
            XCTFail("Overflowing totals accepted")
        } catch { XCTAssertEqual(error as? AIUsageFailure, .invalid) }
    }

    func testRedirectsAreRefused() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://example.invalid/usage")!
        let task = session.dataTask(with: url)
        var followed: URLRequest? = URLRequest(url: url)
        NoUsageRedirects().urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: url)) { followed = $0 }
        XCTAssertNil(followed)
    }

    func testKeychainRoundTripInIsolatedService() throws {
        try UsageKeychain.save("first-key", provider: .openai)
        try UsageKeychain.save("second-key", provider: .openai)
        XCTAssertEqual(try UsageKeychain.load(.openai), "second-key")
        try UsageKeychain.remove(.openai)
        try UsageKeychain.remove(.openai)
        XCTAssertThrowsError(try UsageKeychain.load(.openai))
        XCTAssertEqual(UsageKeychain.query(.cursor)[kSecAttrAccount as String] as? String, "cursor")
    }

    func testKeychainFailuresSurfaceAsKeychainErrors() throws {
        UsageKeychain.update = { _, _ in errSecAuthFailed }
        XCTAssertThrowsError(try UsageKeychain.save("key", provider: .anthropic)) { XCTAssertEqual($0 as? AIUsageFailure, .keychain) }
        UsageKeychain.update = { _, _ in errSecItemNotFound }
        UsageKeychain.add = { _ in errSecDuplicateItem }
        XCTAssertThrowsError(try UsageKeychain.save("key", provider: .anthropic))
        UsageKeychain.copy = { _, result in result.pointee = Data([0xFF, 0xFE]) as CFData; return errSecSuccess }
        XCTAssertThrowsError(try UsageKeychain.load(.anthropic))
        UsageKeychain.copy = { _, result in result.pointee = "not data" as CFString; return errSecSuccess }
        XCTAssertThrowsError(try UsageKeychain.load(.anthropic))
        UsageKeychain.delete = { _ in errSecAuthFailed }
        XCTAssertThrowsError(try UsageKeychain.remove(.anthropic))
    }

    func testSessionTransportReportsNonHTTPStatusAsZero() async throws {
        let (transport, finish) = AIUsageWidget.sessionTransport()
        defer { finish() }
        let (data, status) = try await transport(URLRequest(url: URL(string: "data:application/json,%7B%7D")!))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
        XCTAssertEqual(status, 0)
    }

    func testWidgetConnectRefreshForgetAndFailures() async throws {
        let keychain = MemoryKeychain(); keychain.install()
        let widget = AIUsageWidget(.openai)
        var finished = 0
        let report = openAIReport
        var respond: (URLRequest) async throws -> (Data, Int) = { _ in (report, 200) }
        widget.makeTransport = { ({ try await respond($0) }, { finished += 1 }) }

        widget.connect("   "); XCTAssertEqual(widget.status, "Enter a valid admin key.")
        widget.connect("line\nbreak"); XCTAssertEqual(widget.status, "Enter a valid admin key.")
        widget.connect(" fixture-key ")
        XCTAssertTrue(widget.busy)
        widget.refresh() // Ignored while a refresh is in flight.
        await IntegrationsUI.settle { !widget.busy }
        XCTAssertEqual(widget.snapshot?.totals, [100, 20])
        XCTAssertTrue(widget.status.hasPrefix("Updated"))
        XCTAssertEqual(keychain.items["openai"], Data("fixture-key".utf8))
        XCTAssertEqual(finished, 1)

        respond = { _ in (Data(), 401) }
        widget.refresh(); await IntegrationsUI.settle { !widget.busy }
        XCTAssertNil(widget.snapshot); XCTAssertEqual(widget.status, AIUsageFailure.denied.localizedDescription)
        respond = { _ in throw URLError(.notConnectedToInternet) }
        widget.refresh(); await IntegrationsUI.settle { !widget.busy }
        XCTAssertEqual(widget.status, AIUsageFailure.service.localizedDescription)

        // A refresh that finishes after Disconnect must not restore stale data or state.
        respond = { _ in try await Task.sleep(nanoseconds: 200_000_000); return (report, 200) }
        widget.refresh(); widget.forget()
        XCTAssertEqual(widget.status, "Disconnected. Saved key removed.")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(widget.snapshot); XCTAssertEqual(widget.status, "Disconnected. Saved key removed.")
        keychain.items["openai"] = Data("fixture-key".utf8)
        respond = { _ in try await Task.sleep(nanoseconds: 200_000_000); throw URLError(.timedOut) }
        widget.refresh(); widget.forget()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(widget.status, "Disconnected. Saved key removed.")

        widget.refresh(); XCTAssertEqual(widget.status, "Enter a key, or unlock Keychain if one is already saved.")
        keychain.failUpdate = true
        widget.connect("another-key"); XCTAssertEqual(widget.status, AIUsageFailure.keychain.localizedDescription)
        keychain.failDelete = true
        widget.forget(); XCTAssertEqual(widget.status, AIUsageFailure.keychain.localizedDescription)
    }

    func testHourlyTimerRefreshesOnlyWhenEnabled() async throws {
        let keychain = MemoryKeychain(); keychain.install()
        keychain.items["cursor"] = Data("fixture-key".utf8)
        let widget = AIUsageWidget(.cursor)
        var requests = 0
        widget.makeTransport = { ({ _ in requests += 1; return (Data(#"{"data":[]}"#.utf8), 200) }, {}) }
        widget.timer?.fire(); try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(requests, 0)
        widget.autoRefresh = true
        widget.timer?.fire()
        let refreshed = await IntegrationsUI.settle { requests == 1 && !widget.busy }
        XCTAssertTrue(refreshed)
    }

    func testUsageViewStatesAndActions() throws {
        let keychain = MemoryKeychain(); keychain.install()
        for provider in AIProvider.allCases {
            let widget = AIUsageWidget(provider)
            widget.makeTransport = { ({ _ in (Data(), 500) }, {}) }
            for setup in [true, false] { IntegrationsUI.render(AIUsageView(widget: widget), setup: setup) }
            widget.snapshot = AIUsageSnapshot(totals: provider.labels.map { _ in 42 }, start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_600_000))
            widget.busy = true
            IntegrationsUI.render(AIUsageView(widget: widget), dark: true)
            widget.busy = false
            let setupView = AIUsageView(widget: widget, setupAllowedOverride: true)
            IntegrationsUI.press(IntegrationsUI.body(setupView), "Save key")
            XCTAssertEqual(widget.status, "Enter a valid admin key.")
            IntegrationsUI.press(IntegrationsUI.body(setupView), "Refresh saved key")
            IntegrationsUI.press(IntegrationsUI.body(setupView), "Disconnect")
            XCTAssertEqual(widget.status, "Disconnected. Saved key removed.")
            IntegrationsUI.press(IntegrationsUI.body(AIUsageView(widget: widget, setupAllowedOverride: false)), "Refresh")
            XCTAssertEqual(widget.status, "Enter a key, or unlock Keychain if one is already saved.")
        }
    }
}

// MARK: - Local CLI usage

@MainActor final class IntegrationsLocalAIUsageTests: XCTestCase {
    private let claudeReport = Data(#"{"model":{},"context_window":{},"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":4102444800}},"cost":{"total_cost_usd":0.5}}"#.utf8)
    private let geminiReport = Data(#"{"stats":{"models":{"gemini-pro":{"tokens":{"total":130,"prompt":100,"candidates":30,"cached":40},"api":{"totalRequests":2}}}}}"#.utf8)

    private func widget(_ provider: LocalAIProvider) throws -> (LocalAIWidget, URL) {
        let root = try IntegrationsUI.temporaryDirectory(self)
        let widget = LocalAIWidget(provider)
        widget.directory = root.appendingPathComponent("AI Usage")
        widget.settingsURL = root.appendingPathComponent(".claude/settings.json")
        widget.command = "'/Applications/DockGrove.app/Contents/MacOS/DockGrove' --claude-statusline"
        widget.pasteboard = NSPasteboard(name: NSPasteboard.Name("DockGroveIntegrations." + UUID().uuidString))
        widget.chooseFile = { _ in XCTFail("Unexpected file panel"); return nil }
        widget.signIn.resolve = { _, _ in nil }
        addTeardownBlock { widget.stop(); widget.pasteboard.releaseGlobally() }
        return (widget, root)
    }

    func testMetadataErrorsAndDefaultLocations() {
        XCTAssertEqual(LocalAIProvider.claude.title, "Claude Code")
        XCTAssertEqual(LocalAIProvider.gemini.title, "Gemini CLI")
        XCTAssertEqual(LocalAIProvider.claude.documentation.host, "code.claude.com")
        XCTAssertEqual(LocalAIProvider.gemini.documentation.host, "geminicli.com")
        XCTAssertEqual(LocalAIModel(name: "m", total: 1, input: 1, output: 0, cached: 0, requests: 1).id, "m")
        for error in [LocalAIError.invalid, .tooLarge, .existingStatusLine, .changedSettings, .missing] { XCTAssertFalse(error.errorDescription!.isEmpty) }
        XCTAssertEqual(LocalAIStore.folder.lastPathComponent, "AI Usage")
        XCTAssertTrue(ClaudeStatusLineSetup.command.hasSuffix(" --claude-statusline"))
        XCTAssertTrue(ClaudeStatusLineSetup.settingsURL.path.hasSuffix(".claude/settings.json"))
    }

    func testStoredReportsWithWindowsAndCostReload() throws {
        let root = try IntegrationsUI.temporaryDirectory(self)
        let report = LocalAIReport(provider: "claude", observed: Date(), windows: [LocalAIWindow(name: "5-hour window", used: 30, resets: Date().addingTimeInterval(600))], models: [], sessionCost: 1.25)
        try LocalAIStore.save(report, provider: .claude, directory: root)
        let loaded = try LocalAIStore.load(.claude, directory: root)
        XCTAssertEqual(loaded.windows.count, 1); XCTAssertEqual(loaded.sessionCost, 1.25)
        let invalid = LocalAIReport(provider: "claude", observed: Date(), windows: [LocalAIWindow(name: "w", used: 130, resets: Date())], models: [], sessionCost: nil)
        try LocalAIStore.save(invalid, provider: .claude, directory: root)
        XCTAssertThrowsError(try LocalAIStore.load(.claude, directory: root))
    }

    func testCaptureFromInput() throws {
        let root = try IntegrationsUI.temporaryDirectory(self)
        func capture(_ data: Data, _ provider: LocalAIProvider) throws -> Int32 {
            let input = root.appendingPathComponent(UUID().uuidString)
            try data.write(to: input)
            let handle = try FileHandle(forReadingFrom: input)
            defer { try? handle.close() }
            return LocalAIStore.capture(provider, input: handle, directory: root)
        }
        XCTAssertEqual(try capture(claudeReport, .claude), 0)
        XCTAssertEqual(try LocalAIStore.load(.claude, directory: root).windows.first?.used, 24)
        XCTAssertEqual(try capture(Data(#"{"model":{},"context_window":{}}"#.utf8), .claude), 0)
        XCTAssertEqual(try capture(geminiReport, .gemini), 0)
        XCTAssertEqual(try LocalAIStore.load(.gemini, directory: root).totalTokens, 130)
        XCTAssertEqual(try capture(Data("not json".utf8), .gemini), 1)
    }

    func testWidgetRefreshStatusLineImportClearAndCopy() throws {
        let (widget, root) = try widget(.claude)
        widget.refresh(); XCTAssertNil(widget.report); XCTAssertEqual(widget.status, LocalAIError.missing.localizedDescription)
        try LocalAIStore.save(try LocalAIStore.decode(claudeReport, provider: .claude), provider: .claude, directory: widget.directory)
        widget.refresh(); XCTAssertNotNil(widget.report); XCTAssertTrue(widget.status.hasPrefix("Last received"))
        try Data("not json".utf8).write(to: LocalAIStore.url(.claude, directory: widget.directory))
        widget.refresh(); XCTAssertEqual(widget.status, LocalAIError.invalid.localizedDescription)

        widget.connectClaude(); XCTAssertTrue(widget.status.hasPrefix("Connected."))
        widget.disconnectClaude(); XCTAssertTrue(widget.status.hasPrefix("DockGrove status line removed"))
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": "custom"]]).write(to: widget.settingsURL)
        widget.connectClaude(); XCTAssertEqual(widget.status, LocalAIError.existingStatusLine.localizedDescription)
        widget.disconnectClaude(); XCTAssertEqual(widget.status, LocalAIError.changedSettings.localizedDescription)
        try Data("not json".utf8).write(to: widget.settingsURL)
        widget.disconnectClaude(); XCTAssertEqual(widget.status, LocalAIError.invalid.localizedDescription)
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        widget.settingsURL = blocked.appendingPathComponent("settings.json")
        widget.connectClaude(); XCTAssertEqual(widget.status, LocalAIError.invalid.localizedDescription)

        let report = root.appendingPathComponent("gemini.json")
        try geminiReport.write(to: report)
        var panels: [NSOpenPanel] = []
        widget.chooseFile = { panels.append($0); return nil }
        widget.importReport(); XCTAssertEqual(panels.count, 1); XCTAssertFalse(panels[0].allowsMultipleSelection)
        widget.chooseFile = { _ in report }
        widget.importReport()
        XCTAssertEqual(try LocalAIStore.load(.gemini, directory: widget.directory).totalTokens, 130)
        try Data("{}".utf8).write(to: report)
        widget.importReport(); XCTAssertEqual(widget.status, LocalAIError.invalid.localizedDescription)
        widget.chooseFile = { _ in root.appendingPathComponent("missing.json") }
        widget.importReport(); XCTAssertEqual(widget.status, LocalAIError.invalid.localizedDescription)

        widget.copyCaptureCommand()
        XCTAssertTrue(widget.pasteboard.string(forType: .string)?.hasSuffix(" --gemini-report") == true)

        try LocalAIStore.save(try LocalAIStore.decode(claudeReport, provider: .claude), provider: .claude, directory: widget.directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: widget.directory.path)
        widget.clear(); XCTAssertEqual(widget.status, "Could not clear the local snapshot.")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: widget.directory.path)
        widget.clear(); XCTAssertEqual(widget.status, "Local usage snapshot cleared.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalAIStore.url(.claude, directory: widget.directory).path))
        widget.clear(); XCTAssertNil(widget.report)
    }

    func testPollingTimer() async throws {
        let (widget, _) = try widget(.gemini)
        widget.start()
        let timer = widget.timer
        XCTAssertNotNil(timer)
        widget.start(); XCTAssertTrue(widget.timer === timer)
        try LocalAIStore.save(try LocalAIStore.decode(geminiReport, provider: .gemini), provider: .gemini, directory: widget.directory)
        widget.timer?.fire()
        let loaded = await IntegrationsUI.settle { widget.report != nil }
        XCTAssertTrue(loaded)
        widget.stop(); XCTAssertNil(widget.timer)
    }

    func testUsageViewStatesAndActions() throws {
        for provider in [LocalAIProvider.claude, .gemini] {
            let (widget, _) = try widget(provider)
            for setup in [true, false] { IntegrationsUI.render(LocalAIUsageView(widget: widget, automaticallyRefresh: false), setup: setup) }
            let now = Date()
            widget.report = LocalAIReport(provider: provider.rawValue, observed: now.addingTimeInterval(-4000), windows: [], models: [], sessionCost: nil)
            IntegrationsUI.render(LocalAIUsageView(widget: widget, automaticallyRefresh: false))
            widget.report = LocalAIReport(provider: provider.rawValue, observed: now,
                                          windows: [LocalAIWindow(name: "5-hour window", used: 40, resets: now.addingTimeInterval(3600)), LocalAIWindow(name: "Weekly window", used: 10, resets: now.addingTimeInterval(86400))],
                                          models: [LocalAIModel(name: "gemini-pro", total: 130, input: 60, output: 30, cached: 40, requests: 2)], sessionCost: 0.25)
            IntegrationsUI.render(LocalAIUsageView(widget: widget, automaticallyRefresh: false), dark: true)

            let setupView = LocalAIUsageView(widget: widget, setupAllowedOverride: true, automaticallyRefresh: false)
            if provider == .claude {
                IntegrationsUI.press(IntegrationsUI.body(setupView), "Set up Claude Code status line")
                XCTAssertTrue(widget.status.hasPrefix("Connected."))
                IntegrationsUI.press(IntegrationsUI.body(setupView), "Remove DockGrove status line")
                XCTAssertTrue(widget.status.hasPrefix("DockGrove status line removed"))
                let callbacks = IntegrationsUI.closures("onSuccess", in: IntegrationsUI.body(setupView))
                XCTAssertEqual(callbacks.count, 1)
                callbacks.forEach { $0() }
                XCTAssertTrue(widget.status.hasPrefix("Connected."))
            } else {
                var opened = 0
                widget.chooseFile = { _ in opened += 1; return nil }
                IntegrationsUI.press(IntegrationsUI.body(setupView), "Import Gemini session JSON")
                XCTAssertEqual(opened, 1)
                IntegrationsUI.press(IntegrationsUI.body(setupView), "Copy CLI capture command")
                XCTAssertNotNil(widget.pasteboard.string(forType: .string))
            }
            let plainView = LocalAIUsageView(widget: widget, setupAllowedOverride: false, automaticallyRefresh: false)
            IntegrationsUI.press(IntegrationsUI.body(plainView), "Refresh")
            IntegrationsUI.press(IntegrationsUI.body(plainView), "Clear local snapshot")
            XCTAssertNil(widget.report)
            IntegrationsUI.appear(IntegrationsUI.body(plainView))
            XCTAssertNil(widget.timer)
            IntegrationsUI.appear(IntegrationsUI.body(LocalAIUsageView(widget: widget, setupAllowedOverride: false)))
            XCTAssertNotNil(widget.timer)
        }
    }
}

// MARK: - CLI sign-in

@MainActor final class IntegrationsSignInTests: XCTestCase {
    private func settle(_ signIn: AISignIn) { XCTAssertTrue(IntegrationsUI.wait(10) { !signIn.busy }) }

    func testSetupLinksMissingCLIAndDefaultCallback() throws {
        XCTAssertEqual(AISignInProvider.codex.setupURL.host, "developers.openai.com")
        XCTAssertEqual(AISignInProvider.claude.setupURL.host, "code.claude.com")
        let signIn = AISignIn()
        signIn.resolve = { _, _ in nil }
        signIn.start(.claude)
        XCTAssertEqual(signIn.status, "Install Claude Code to continue.")
        XCTAssertFalse(signIn.busy)
        let folder = try IntegrationsUI.temporaryDirectory(self)
        let success = try IntegrationsUI.fixture("SignInFixture", named: "success", in: folder)
        signIn.resolve = { _, _ in success }
        signIn.start(.codex, checkOnly: true)
        settle(signIn)
        XCTAssertTrue(signIn.authenticated)
        XCTAssertNotNil(AISignIn().resolve(.codex, "/nonexistent/codex") ?? "fallback")
    }

    func testSignInControlsStatesAndActions() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        let success = try IntegrationsUI.fixture("SignInFixture", named: "success", in: folder)
        let waiting = try IntegrationsUI.fixture("SignInFixture", named: "waiting", in: folder)
        let signIn = AISignIn()
        var path = success, successes = 0
        signIn.resolve = { _, _ in path }
        for provider in [AISignInProvider.codex, .claude] {
            let controls = AISignInControls(signIn: signIn, provider: provider, custom: "") { successes += 1 }
            IntegrationsUI.render(controls)
            IntegrationsUI.press(IntegrationsUI.body(controls), "Sign in with")
            settle(signIn)
            IntegrationsUI.press(IntegrationsUI.body(controls), "Use existing sign-in")
            settle(signIn)
        }
        XCTAssertEqual(successes, 4)
        IntegrationsUI.render(AISignInControls(signIn: signIn, provider: .codex), dark: true)
        path = waiting
        let defaults = AISignInControls(signIn: signIn, provider: .claude)
        IntegrationsUI.press(IntegrationsUI.body(defaults), "Sign in with")
        XCTAssertTrue(signIn.busy)
        IntegrationsUI.render(defaults)
        IntegrationsUI.press(IntegrationsUI.body(defaults), "Cancel sign-in")
        XCTAssertFalse(signIn.busy)
        path = success
        IntegrationsUI.press(IntegrationsUI.body(defaults), "Use existing sign-in")
        settle(signIn)
        XCTAssertTrue(signIn.authenticated)
    }

    func testCodexConnectionView() throws {
        let model = DockModel(defaults: IntegrationsUI.defaults(self))
        model.codexSignIn.resolve = { _, _ in nil }
        var fetches = 0
        model.fetchUsage = { _ in fetches += 1; throw UsageError.noWindows }
        let view = CodexConnectionView(model: model)
        IntegrationsUI.render(view)
        let callbacks = IntegrationsUI.closures("onSuccess", in: IntegrationsUI.body(view))
        XCTAssertEqual(callbacks.count, 1)
        callbacks.forEach { $0() }
        XCTAssertNil(model.usage)
    }

    func testGeminiControls() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        for compact in [false, true] {
            for (opened, status) in [(false, GeminiSignInControls.initialStatus), (false, "Install Gemini CLI first."), (true, "Continue in Terminal.")] {
                IntegrationsUI.render(GeminiSignInControls(compact: compact, opened: opened, status: status))
            }
        }
        var imports = 0
        IntegrationsUI.press(IntegrationsUI.body(GeminiSignInControls(compact: true, onImport: { imports += 1 }, opened: true)), "Import usage")
        XCTAssertEqual(imports, 1)
        IntegrationsUI.press(IntegrationsUI.body(GeminiSignInControls(compact: true, opened: true)), "Import usage")

        var controls = GeminiSignInControls()
        controls.executable = { nil }
        IntegrationsUI.press(IntegrationsUI.body(controls), "Sign in with Google")

        var launched: [(URL, URL)] = []
        controls.executable = { "/opt/fixture/gemini" }
        controls.folder = folder.appendingPathComponent("Gemini Sign In")
        controls.openScript = { script, app, completion in launched.append((script, app)); completion(nil); completion(CocoaError(.fileNoSuchFile)) }
        IntegrationsUI.press(IntegrationsUI.body(controls), "Sign in with Google")
        var compactControls = GeminiSignInControls(compact: true)
        compactControls.executable = { nil }
        IntegrationsUI.press(IntegrationsUI.body(compactControls), "Sign in")
        IntegrationsUI.spin(0.1)
        XCTAssertEqual(launched.count, 1)
        let script = try String(contentsOf: launched[0].0, encoding: .utf8)
        XCTAssertTrue(script.contains("exec '/opt/fixture/gemini'"))
        XCTAssertEqual(launched[0].1.lastPathComponent, "Terminal.app")

        // The real launcher reports a missing application without showing anything.
        controls.openScript = GeminiSignInControls.open
        controls.terminal = folder.appendingPathComponent("Missing Terminal.app")
        IntegrationsUI.press(IntegrationsUI.body(controls), "Sign in with Google")
        var reported: Error?
        GeminiSignInControls.open(launched[0].0, with: controls.terminal) { reported = $0 }
        XCTAssertTrue(IntegrationsUI.wait { reported != nil })

        let blocker = folder.appendingPathComponent("file")
        try Data().write(to: blocker)
        controls.folder = blocker.appendingPathComponent("Gemini Sign In")
        IntegrationsUI.press(IntegrationsUI.body(controls), "Sign in with Google")
        IntegrationsUI.spin(0.2)
    }
}
