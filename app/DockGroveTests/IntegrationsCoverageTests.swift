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
        for failure in [AIUsageFailure.invalid, .denied, .limited, .service, .keychain, .adminKeyRequired(.anthropic), .adminKeyRequired(.openai), .adminKeyRequired(.cursor), .rejected(400, nil), .rejected(404, "x")] { XCTAssertFalse(failure.errorDescription!.isEmpty) }
        XCTAssertEqual(AIUsageFailure.adminKeyRequired(.cursor).errorDescription, AIUsageFailure.denied.errorDescription)
    }

    func testClaudeReportIncludesTodayBucket() throws {
        // 2026-11-03T15:30:00Z. Claude returns only buckets that end before `ending_at`, so sending
        // `ending_at=now` dropped today; a non-midnight `starting_at` dropped the first day as well.
        let now = Date(timeIntervalSince1970: 1_793_719_800)
        let start = AIProvider.anthropic.windowStart(now: now)
        XCTAssertEqual(ISO8601DateFormatter().string(from: start), "2026-10-28T00:00:00Z")
        let request = try AIProvider.anthropic.request(key: "fixture", start: start, end: now, page: nil)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(request.url?.path, "/v1/organizations/usage_report/messages")
        XCTAssertEqual(items.first { $0.name == "starting_at" }?.value, "2026-10-28T00:00:00Z")
        XCTAssertNil(items.first { $0.name == "ending_at" })
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "7")
        XCTAssertEqual(items.first { $0.name == "bucket_width" }?.value, "1d")
        XCTAssertEqual(AIProvider.openai.windowStart(now: now), now.addingTimeInterval(-7 * 86400))
        // The documented response shape, including extra fields and a null cursor, decodes.
        let documented = Data(#"{"data":[{"starting_at":"2026-11-03T00:00:00Z","ending_at":"2026-11-04T00:00:00Z","results":[{"account_id":null,"api_key_id":null,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":3},"cache_read_input_tokens":200,"context_window":null,"inference_geo":null,"model":null,"output_tokens":500,"server_tool_use":{"web_search_requests":0},"service_account_id":null,"service_tier":null,"speed":null,"uncached_input_tokens":1500,"workspace_id":null}]},{"starting_at":"2026-11-02T00:00:00Z","ending_at":"2026-11-03T00:00:00Z","results":[]}],"has_more":false,"next_page":null}"#.utf8)
        XCTAssertEqual(try AIProvider.anthropic.decode(documented).totals, [1703, 500])
    }

    func testRejectedKeysExplainWhichKeyIsNeeded() async throws {
        func failure(_ provider: AIProvider, key: String, status: Int, body: String = "") async -> AIUsageFailure? {
            do { _ = try await AIUsageClient.fetch(provider, key: key) { _ in (Data(body.utf8), status) }; return nil }
            catch { return error as? AIUsageFailure }
        }
        let claudeBody = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let standard = await failure(.anthropic, key: "sk-ant-api03-fixture", status: 401, body: claudeBody)
        XCTAssertEqual(standard, .adminKeyRequired(.anthropic))
        XCTAssertTrue(standard!.errorDescription!.contains("sk-ant-admin"))
        let anthropicAdmin = await failure(.anthropic, key: "sk-ant-admin01-fixture", status: 403)
        XCTAssertEqual(anthropicAdmin, .denied)
        let project = await failure(.openai, key: "sk-proj-fixture", status: 401)
        XCTAssertEqual(project, .adminKeyRequired(.openai))
        let openAIAdmin = await failure(.openai, key: "sk-admin-fixture", status: 401)
        XCTAssertEqual(openAIAdmin, .denied)
        let cursor = await failure(.cursor, key: "key_fixture", status: 401)
        XCTAssertEqual(cursor, .denied)
        let limited = await failure(.anthropic, key: "sk-ant-admin01-fixture", status: 429)
        XCTAssertEqual(limited, .limited)
        let server = await failure(.anthropic, key: "sk-ant-admin01-fixture", status: 529)
        XCTAssertEqual(server, .service)

        let bad = await failure(.anthropic, key: "sk-ant-admin01-fixture", status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"limit: must be at most 31\nfor 1d"}}"#)
        XCTAssertEqual(bad, .rejected(400, "limit: must be at most 31 for 1d"))
        XCTAssertEqual(bad?.errorDescription, "The service refused the usage request (HTTP 400): limit: must be at most 31 for 1d")
        XCTAssertEqual(AIUsageClient.message(Data(#"{"error":"Team not found"}"#.utf8), key: "k"), "Team not found")
        XCTAssertEqual(AIUsageClient.message(Data(#"{"message":"Bad date range"}"#.utf8), key: "k"), "Bad date range")
        XCTAssertNil(AIUsageClient.message(Data(#"{"error":{"message":"bad key sk-secret"}}"#.utf8), key: "sk-secret"), "The key is never echoed")
        XCTAssertNil(AIUsageClient.message(Data("<html>".utf8), key: "k"))
        XCTAssertEqual(AIUsageClient.message(Data(("{\"message\":\"" + String(repeating: "a", count: 300) + "\"}").utf8), key: "k")?.count, 201)
        let notFound = await failure(.cursor, key: "key_fixture", status: 404, body: "not json")
        XCTAssertEqual(notFound, .rejected(404, nil))
    }

    func testStartLoadsASavedKeyOncePerLaunch() async throws {
        let keychain = MemoryKeychain(); keychain.install()
        let saved = AIUsageWidget.loadsSavedKey
        defer { AIUsageWidget.loadsSavedKey = saved }
        XCTAssertFalse(saved, "Test hosts never auto-read a saved key")
        var requests = 0
        let report = openAIReport
        let widget = AIUsageWidget(.openai)
        widget.makeTransport = { ({ _ in requests += 1; return (report, 200) }, {}) }
        widget.start(); XCTAssertEqual(requests, 0)

        AIUsageWidget.loadsSavedKey = true
        widget.start() // No saved key: stays quiet, no request.
        XCTAssertEqual(requests, 0); XCTAssertEqual(widget.status, "")

        keychain.items["openai"] = Data("sk-admin-fixture".utf8)
        let relaunched = AIUsageWidget(.openai)
        relaunched.makeTransport = { ({ _ in requests += 1; return (report, 200) }, {}) }
        relaunched.start()
        await IntegrationsUI.settle { !relaunched.busy }
        XCTAssertEqual(relaunched.snapshot?.totals, [100, 20]); XCTAssertEqual(requests, 1)
        relaunched.start()
        XCTAssertEqual(requests, 1, "Appearing again does not refetch")
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
        XCTAssertNil(widget.snapshot); XCTAssertEqual(widget.status, AIUsageFailure.adminKeyRequired(.openai).localizedDescription)
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
        for error in [LocalAIError.invalid, .tooLarge, .existingStatusLine, .changedSettings, .missing, .cliMissing, .signedOut, .noLimits, .cliFailed] { XCTAssertFalse(error.errorDescription!.isEmpty) }
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

    func testChainedCaptureRunsTheOriginalStatusLine() throws {
        let root = try IntegrationsUI.temporaryDirectory(self)
        func chain(_ data: Data, _ original: String, shell: String = "/bin/sh") throws -> (Int32, String) {
            let input = root.appendingPathComponent(UUID().uuidString), output = root.appendingPathComponent(UUID().uuidString)
            try data.write(to: input); try Data().write(to: output)
            let reader = try FileHandle(forReadingFrom: input), writer = try FileHandle(forWritingTo: output)
            defer { try? reader.close() }
            let status = LocalAIStore.capture(.claude, input: reader, directory: root, then: original, output: writer, shell: URL(fileURLWithPath: shell))
            try writer.close()
            return (status, try String(contentsOf: output, encoding: .utf8))
        }
        // The original gets the same bytes on stdin; its output and exit status are forwarded.
        let (status, output) = try chain(claudeReport, "printf 'mine:'; /bin/cat; exit 3")
        XCTAssertEqual(status, 3); XCTAssertEqual(output, "mine:" + String(data: claudeReport, encoding: .utf8)!)
        XCTAssertEqual(try LocalAIStore.load(.claude, directory: root).windows.first?.used, 24)
        // A report DockGrove cannot read never breaks the user's status line.
        try FileManager.default.removeItem(at: LocalAIStore.url(.claude, directory: root))
        XCTAssertEqual(try chain(Data("not json".utf8), "/bin/cat").1, "not json")
        XCTAssertThrowsError(try LocalAIStore.load(.claude, directory: root))
        // An original that ignores a large input still exits normally (no SIGPIPE).
        XCTAssertEqual(try chain(Data(repeating: 0x41, count: 300_000), "printf ok").0, 0)
        XCTAssertEqual(try chain(claudeReport, "/bin/cat", shell: root.appendingPathComponent("missing-shell").path).0, 127)
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
        let custom: NSDictionary = ["type": "command", "command": "~/.claude/statusline-command.sh", "padding": 1]
        try JSONSerialization.data(withJSONObject: ["statusLine": custom]).write(to: widget.settingsURL)
        func statusLine() throws -> NSDictionary? { (try JSONSerialization.jsonObject(with: Data(contentsOf: widget.settingsURL)) as? NSDictionary)?["statusLine"] as? NSDictionary }
        widget.connectClaude(); XCTAssertTrue(widget.status.contains("custom status line keeps working"))
        XCTAssertEqual(try statusLine()?["command"] as? String, widget.command + " --then '~/.claude/statusline-command.sh'")
        XCTAssertEqual(try statusLine()?["padding"] as? Int, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ClaudeStatusLineSetup.originalURL(widget.directory).path))
        widget.connectClaude(); XCTAssertEqual(try statusLine()?["command"] as? String, widget.command + " --then '~/.claude/statusline-command.sh'")
        widget.disconnectClaude(); XCTAssertTrue(widget.status.hasSuffix("Your original status line was restored."))
        XCTAssertEqual(try statusLine(), custom)
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "static"]]).write(to: widget.settingsURL)
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
        var prompts: [String] = []
        widget.chooseFile = { prompts.append($0); return nil }
        widget.importReport(); XCTAssertEqual(prompts.count, 1); XCTAssertTrue(prompts[0].contains("Gemini CLI"))
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

    // MARK: Claude Code /usage

    /// Real `claude -p /usage` text (America/New_York account, Nov 3 2026).
    static let usageText = """
    You are currently using your subscription to power your Claude Code usage

    Current week (all models): 28% used · resets Nov 6 at 7:59pm (America/New_York)
    Current week (Fable): 14% used · resets Nov 6 at 7:59pm (America/New_York)

    What's contributing to your usage?
    Approximate · sessions on this machine only · shares overlap

    Last 24h · 1625 requests · 4 sessions
      89%  Give "general-purpose" subagents a cheaper model
      56%  Start fresh when you switch tasks · run /clear
      10%  Turn off MCP servers you don't use · 26k tokens per request
      Top subagents: general-purpose 63%
      Top MCP servers: playwright 1%

    Last 7d · 15268 requests · 10 sessions
      96%  Stop sessions you no longer need · some ran 8 hours or more
    """
    static func usageJSON(_ result: String, error: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": "result", "subtype": "success", "is_error": error, "local_command": "usage", "total_cost_usd": 0, "num_turns": 0, "result": result])
    }
    private static let newYork = TimeZone(identifier: "America/New_York")!
    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ zone: TimeZone = newYork) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testUsageParserReadsTheRealUsageScreen() throws {
        let now = Self.date(2026, 11, 3, 12, 0)
        let report = try ClaudeUsageParser.report(Self.usageJSON(Self.usageText), now: now)
        XCTAssertEqual(report.windows.map(\.name), ["Weekly · all models", "Weekly · Fable"])
        XCTAssertEqual(report.windows.map(\.used), [28, 14])
        XCTAssertEqual(report.windows[0].resets, Self.date(2026, 11, 6, 19, 59))
        XCTAssertEqual(report.windows[1].resetText, "Nov 6 at 7:59pm (America/New_York)")
        XCTAssertEqual(report.source, "usage"); XCTAssertEqual(report.observed, now); XCTAssertNil(report.sessionCost)
        XCTAssertEqual(report.summary, "Last 24h · 1625 requests · 4 sessions")
        XCTAssertEqual(report.drivers?.map(\.percent), [89, 56, 10])
        XCTAssertEqual(report.drivers?.first?.text, "Give \"general-purpose\" subagents a cheaper model")
        XCTAssertEqual(report.mostConstrained(at: now)?.name, "Weekly · all models")

        // A 5-hour session, the reset rounding Claude Code uses ("8pm"), clamping and a cap of eight windows.
        let session = ClaudeUsageParser.parse("Current session: 41.5% used · resets 7:59pm (America/New_York)\nCurrent week (all models): 120% used · resets Nov 6 at 8pm (America/New_York)\nCurrent day: 3% used\nCurrent week: 2% used · resets in 3 hours", now: now)
        XCTAssertEqual(session.windows.map(\.name), ["5-hour window", "Weekly · all models", "Day", "Weekly · all models"])
        XCTAssertEqual(session.windows.map(\.used), [41.5, 100, 3, 2])
        XCTAssertEqual(session.windows[0].resets, Self.date(2026, 11, 3, 19, 59))
        XCTAssertEqual(session.windows[1].resets, Self.date(2026, 11, 6, 20, 0))
        XCTAssertNil(session.windows[2].resets); XCTAssertNil(session.windows[2].resetText); XCTAssertNil(session.windows[2].resetLabel)
        XCTAssertNil(session.windows[3].resets); XCTAssertEqual(session.windows[3].resetLabel, "Resets in 3 hours")
        XCTAssertTrue(session.windows[0].resetLabel!.hasPrefix("Resets "))
        XCTAssertNil(session.summary); XCTAssertTrue(session.drivers.isEmpty)
        XCTAssertEqual(ClaudeUsageParser.parse(Array(repeating: "Current session: 1% used", count: 12).joined(separator: "\n"), now: now).windows.count, 8)
        XCTAssertTrue(ClaudeUsageParser.parse("garbage \u{0}\n%%% used\nCurrent : % used\n\u{1F643}", now: now).windows.isEmpty)
    }

    func testUsageResetTimes() {
        let now = Self.date(2026, 11, 3, 12, 0)
        let utc = TimeZone(identifier: "UTC")!
        func reset(_ text: String) -> Date? { ClaudeUsageParser.resetDate(text, now: now) }
        XCTAssertEqual(reset("7:59pm (America/New_York)"), Self.date(2026, 11, 3, 19, 59))
        XCTAssertEqual(reset("6am (America/New_York)"), Self.date(2026, 11, 4, 6, 0), "A passed time is tomorrow's")
        XCTAssertEqual(reset("12am (America/New_York)"), Self.date(2026, 11, 4, 0, 0))
        XCTAssertEqual(reset("Jan 2 at 9:05am (UTC)"), Self.date(2027, 1, 2, 9, 5, utc), "A passed date is next year's")
        XCTAssertEqual(reset("November 3, 2026 at 13:30 (GMT)"), Self.date(2026, 11, 3, 13, 30, utc))
        XCTAssertEqual(reset("Nov. 2 at 8pm (America/New_York)"), Self.date(2026, 11, 2, 20, 0), "Within a day is still this year's")
        XCTAssertNotNil(reset("Nov 6 at 8pm"), "Without a zone, the Mac's zone")
        XCTAssertNotNil(reset("8pm (PDT)"), "A zone abbreviation")
        for bad in ["Foo 6 at 8pm (UTC)", "Nov 31 at 8pm (UTC)", "8 (UTC)", "13pm (UTC)", "0am (UTC)", "25:00 (UTC)", "8:61pm (UTC)", "8pm (Not/AZone)", "in 3h", "Nov 6 at 1pm at 2pm", "", "(UTC)"] {
            XCTAssertNil(reset(bad), bad)
        }
        XCTAssertEqual(ClaudeUsageParser.title("week (Opus)"), "Weekly · Opus")
        XCTAssertEqual(ClaudeUsageParser.title("Session"), "5-hour window")
    }

    func testUsageResultErrorsAndSignInStates() {
        let now = Date()
        func failure(_ data: Data) -> LocalAIError? {
            do { _ = try ClaudeUsageParser.report(data, now: now); return nil } catch { return error as? LocalAIError }
        }
        XCTAssertEqual(failure(Self.usageJSON("Not logged in · Please run /login", error: true)), .signedOut)
        XCTAssertEqual(failure(Self.usageJSON("Something went wrong", error: true)), .cliFailed)
        XCTAssertEqual(failure(Self.usageJSON("Invalid API key · Please run /login")), .signedOut)
        XCTAssertEqual(failure(Self.usageJSON("You are currently using API usage billing")), .noLimits)
        XCTAssertEqual(failure(Self.usageJSON("")), .noLimits)
        XCTAssertEqual(failure(Data("not json".utf8)), .cliFailed)
        XCTAssertEqual(failure(Data("[1]".utf8)), .cliFailed)
        XCTAssertEqual(failure(try! JSONSerialization.data(withJSONObject: ["is_error": false])), .noLimits)
    }

    func testUsageCommandRunsTheCLIWithItsOwnPath() async throws {
        let root = try IntegrationsUI.temporaryDirectory(self)
        func script(_ name: String, _ body: String) throws -> String {
            let url = root.appendingPathComponent(name)
            try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url.path
        }
        let output = root.appendingPathComponent("path.txt").path
        let ok = try script("claude", "[ \"$*\" = '-p /usage --output-format json --no-session-persistence' ] || exit 9\nprintf '%s' \"$PATH\" > '\(output)'\nprintf '%s' '{\"is_error\":false,\"result\":\"Current session: 5% used\"}'")
        let data = try await ClaudeUsageCommand.live(ok)
        XCTAssertEqual(try ClaudeUsageParser.report(data, now: Date()).windows.first?.used, 5)
        XCTAssertTrue(try String(contentsOfFile: output, encoding: .utf8).hasPrefix(root.path + ":"), "The CLI's own folder comes first on PATH")
        XCTAssertEqual(ClaudeUsageCommand.arguments.last, "--no-session-persistence")

        // A non-zero exit still returns its JSON (Claude Code reports sign-in errors that way).
        let failing = try script("failing", "printf '%s' '{\"is_error\":true}'; exit 1")
        let failed = try await ClaudeUsageCommand.run(failing)
        XCTAssertEqual(failed, Data(#"{"is_error":true}"#.utf8))
        // Oversized output, a hung CLI, a crash and a missing executable all fail without data.
        let chatty = try script("chatty", "yes DockGrove | head -c 200000")
        let hung = try script("hung", "exec /bin/sleep 5")
        let crashed = try script("crashed", "kill -9 $$")
        for (path, timeout, limit) in [(chatty, 30.0, 1000), (hung, 0.3, 1000), (crashed, 30.0, 1000), (root.appendingPathComponent("missing").path, 30.0, 1000)] {
            do { _ = try await ClaudeUsageCommand.run(path, timeout: timeout, maxBytes: limit); XCTFail("\(path) succeeded") }
            catch { XCTAssertEqual(error as? LocalAIError, .cliFailed) }
        }
        try await Task.sleep(nanoseconds: 1_300_000_000) // lets the hung CLI's SIGKILL check run
    }

    func testUsageStorageMergeAndValidation() throws {
        let root = try IntegrationsUI.temporaryDirectory(self)
        let now = Date()
        // A report saved before /usage support (no optional fields) still loads.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = #"{"provider":"claude","observed":\#(now.timeIntervalSinceReferenceDate - 60),"windows":[{"name":"Weekly window","used":12,"resets":\#(now.timeIntervalSinceReferenceDate + 600)}],"models":[],"sessionCost":0.5}"#
        try Data(old.utf8).write(to: LocalAIStore.url(.claude, directory: root))
        let line = try LocalAIStore.load(.claude, directory: root)
        XCTAssertEqual(line.windows.first?.used, 12); XCTAssertNil(line.source); XCTAssertNil(line.drivers)
        XCTAssertTrue(LocalAIStore.url(.claude, directory: root, usage: true).lastPathComponent == "claude-usage.json")

        let usage = try ClaudeUsageParser.report(Self.usageJSON(Self.usageText + "\nCurrent session: 3% used · resets soon"), now: now)
        try LocalAIStore.save(usage, provider: .claude, directory: root, usage: true)
        let loaded = try LocalAIStore.load(.claude, directory: root, usage: true)
        XCTAssertEqual(loaded.windows.count, 3); XCTAssertEqual(loaded.windows[2].resetText, "soon"); XCTAssertNil(loaded.windows[2].resets)
        XCTAssertEqual(loaded.activeWindows(at: now).count, 3, "A window without a readable reset stays active")

        // Fresh /usage wins and keeps the status line's cost; a stale one yields to a newer status line.
        let merged = try XCTUnwrap(LocalAIReport.merged(statusLine: line, usage: loaded, now: now))
        XCTAssertEqual(merged.windows.count, 3); XCTAssertEqual(merged.sessionCost, 0.5); XCTAssertEqual(merged.source, "usage")
        let newerLine = LocalAIReport(provider: "claude", observed: now.addingTimeInterval(10), windows: line.windows, models: [], sessionCost: nil)
        XCTAssertNil(LocalAIReport.merged(statusLine: newerLine, usage: loaded, now: now.addingTimeInterval(1900))?.source)
        XCTAssertEqual(LocalAIReport.merged(statusLine: line, usage: loaded, now: now.addingTimeInterval(1900))?.source, "usage", "An older status line never replaces /usage")
        let staleUsage = LocalAIReport(provider: "claude", observed: now.addingTimeInterval(-4000), windows: loaded.windows, models: [], sessionCost: nil, source: "usage")
        XCTAssertEqual(LocalAIReport.merged(statusLine: nil, usage: staleUsage, now: now)?.source, "usage")
        XCTAssertNil(LocalAIReport.merged(statusLine: nil, usage: nil, now: now))
        XCTAssertNil(LocalAIReport(provider: "claude", observed: now, windows: [], models: [], sessionCost: nil).mostConstrained(at: now))

        for invalid in [
            LocalAIReport(provider: "claude", observed: now, windows: Array(repeating: LocalAIWindow(name: "w", used: 1, resets: nil), count: 9), models: [], sessionCost: nil),
            LocalAIReport(provider: "claude", observed: now, windows: [], models: [], sessionCost: nil, drivers: [LocalAIDriver(percent: 101, text: "x")]),
            LocalAIReport(provider: "claude", observed: now, windows: [], models: [], sessionCost: nil, summary: String(repeating: "x", count: 201)),
            LocalAIReport(provider: "claude", observed: now, windows: [LocalAIWindow(name: "w", used: 1, resets: nil, resetText: String(repeating: "x", count: 201))], models: [], sessionCost: nil),
        ] {
            try LocalAIStore.save(invalid, provider: .claude, directory: root, usage: true)
            XCTAssertThrowsError(try LocalAIStore.load(.claude, directory: root, usage: true))
        }
    }

    func testWidgetRunsUsageOnStartTimerAndRefresh() async throws {
        let (widget, _) = try widget(.claude)
        XCTAssertNil(widget.runUsage, "Test hosts never run the real Claude Code")
        XCTAssertFalse(LocalAIWidget.runsUsageCommand)
        widget.refreshUsage(); XCTAssertEqual(widget.usageStatus, "")

        var runs: [String] = []
        var reply: () throws -> Data = { Self.usageJSON(Self.usageText) }
        widget.runUsage = { path in runs.append(path); try await Task.sleep(nanoseconds: 20_000_000); return try reply() }
        widget.refreshUsage()
        XCTAssertEqual(widget.usageStatus, LocalAIError.cliMissing.localizedDescription); XCTAssertTrue(runs.isEmpty)

        widget.signIn.resolve = { _, _ in "/fake/claude" }
        widget.start() // not due: the missing-CLI check just ran
        XCTAssertNotNil(widget.usageTimer); XCTAssertFalse(widget.usageBusy)
        widget.refreshUsage(); XCTAssertTrue(widget.usageBusy)
        widget.refreshUsage() // ignored while running
        let loaded = await IntegrationsUI.settle { !widget.usageBusy }
        XCTAssertTrue(loaded); XCTAssertEqual(runs, ["/fake/claude"])
        XCTAssertEqual(widget.report?.source, "usage"); XCTAssertEqual(widget.report?.windows.count, 2)
        XCTAssertTrue(widget.status.hasPrefix("Updated from /usage")); XCTAssertEqual(widget.usageStatus, "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: LocalAIStore.url(.claude, directory: widget.directory, usage: true).path))

        // Not due again for five minutes; the timer and Refresh button respect / override that.
        widget.refreshUsageIfDue(); widget.usageTimer?.fire()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runs.count, 1)
        reply = { Self.usageJSON("Not logged in · Please run /login", error: true) }
        widget.refreshUsage()
        _ = await IntegrationsUI.settle { !widget.usageBusy }
        XCTAssertEqual(widget.usageStatus, LocalAIError.signedOut.localizedDescription)
        XCTAssertEqual(widget.report?.source, "usage", "The last good /usage report stays")
        reply = { throw CancellationError() }
        widget.refreshUsage()
        _ = await IntegrationsUI.settle { !widget.usageBusy }
        XCTAssertEqual(widget.usageStatus, LocalAIError.cliFailed.localizedDescription)

        widget.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalAIStore.url(.claude, directory: widget.directory, usage: true).path))
        widget.stop(); XCTAssertNil(widget.usageTimer)

        let (gemini, _) = try self.widget(.gemini)
        gemini.runUsage = { _ in XCTFail("Gemini never runs /usage"); return Data() }
        gemini.start(); gemini.refreshUsage(); XCTAssertNil(gemini.usageTimer)
    }

    func testUsageViewShowsEveryWindowAndDrivers() throws {
        let (widget, _) = try widget(.claude)
        let now = Date()
        widget.report = LocalAIReport.merged(statusLine: nil, usage: try ClaudeUsageParser.report(Self.usageJSON(Self.usageText + "\nCurrent session: 91% used · resets soon"), now: now), now: now)
        widget.usageStatus = LocalAIError.signedOut.localizedDescription
        for dark in [false, true] { IntegrationsUI.render(LocalAIUsageView(widget: widget, automaticallyRefresh: false), dark: dark) }
        let strings = IntegrationsUI.strings(in: IntegrationsUI.body(LocalAIUsageView(widget: widget, setupAllowedOverride: false, automaticallyRefresh: false)))
        XCTAssertFalse(strings.isEmpty)
        var calls = 0
        widget.signIn.resolve = { _, _ in calls += 1; return nil }
        widget.runUsage = { _ in Data() }
        IntegrationsUI.press(IntegrationsUI.body(LocalAIUsageView(widget: widget, setupAllowedOverride: false, automaticallyRefresh: false)), "Refresh")
        XCTAssertEqual(calls, 1); XCTAssertEqual(widget.usageStatus, LocalAIError.cliMissing.localizedDescription)
    }
}

// MARK: - CLI sign-in

@MainActor final class IntegrationsSignInTests: XCTestCase {
    private func settle(_ signIn: AISignIn) { XCTAssertTrue(IntegrationsUI.wait(10) { !signIn.busy }) }

    func testCLILookupCoversInstallersAGUIAppPATHMisses() throws {
        // Finder-launched apps get a minimal PATH, so npm/nvm and Claude's local installs must be searched directly.
        let home = try IntegrationsUI.temporaryDirectory(self).path
        let name = "dockgrove-fixture-cli-" + UUID().uuidString.prefix(8)
        func install(_ folder: String) throws -> String {
            try FileManager.default.createDirectory(atPath: home + folder, withIntermediateDirectories: true)
            let path = home + folder + "/" + name
            try "#!/bin/sh\nexit 0\n".write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            return path
        }
        XCTAssertNil(AICommand.executable(name, home: home))
        _ = try install("/.nvm/versions/node/v9.11.0/bin")
        let newest = try install("/.nvm/versions/node/v22.3.0/bin")
        XCTAssertEqual(AICommand.executable(name, home: home), newest, "Newest nvm node wins")
        let local = try install("/.claude/local")
        XCTAssertEqual(AICommand.executable(name, home: home), local)
        let npm = try install("/.npm-global/bin")
        XCTAssertEqual(AICommand.executable(name, home: home), local, "Earlier folders keep priority")
        XCTAssertEqual(AICommand.executable(name, custom: npm, home: home), npm, "A chosen executable wins")
        let preferred = try install("/.local/bin")
        XCTAssertEqual(AICommand.executable(name, home: home), preferred)
        XCTAssertEqual(UsageClient.executable(custom: newest, home: home), newest)
        for folder in ["/.bun/bin", "/.volta/bin", "/Library/pnpm"] { XCTAssertTrue(AICommand.searchDirectories(home: home).contains(home + folder)) }

        // Node-script CLIs need their own folder (where nvm keeps `node`) on the child's PATH.
        let path = AICommand.searchPath(for: newest, home: home).split(separator: ":").map(String.init)
        XCTAssertEqual(path.first, home + "/.nvm/versions/node/v22.3.0/bin")
        XCTAssertTrue(path.contains("/usr/bin"))
        let homebrew = AICommand.searchPath(for: "/opt/homebrew/bin/codex", home: home).split(separator: ":").map(String.init)
        XCTAssertEqual(homebrew.first, "/opt/homebrew/bin"); XCTAssertEqual(homebrew.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertEqual(AICommand.environment(for: newest)["PATH"]?.hasPrefix(home + "/.nvm/versions/node/v22.3.0/bin:"), true)
        XCTAssertNil(AICommand.environment(for: newest)["ANTHROPIC_API_KEY"])
        XCTAssertTrue(AICommand.geminiScript(executable: newest, directory: home).contains("export PATH='" + home + "/.nvm/versions/node/v22.3.0/bin'\":$HOME/.local/bin"))
    }

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
