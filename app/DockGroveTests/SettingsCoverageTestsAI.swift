import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

/// AI connection forms. Every side effect goes to a fake: sign-in CLIs resolve to the sign-in
/// fixture or to nothing, Keychain calls stay in memory, reports and Claude settings live in a
/// temporary folder, file panels are never shown and the pasteboard is private.
@MainActor final class SettingsCoverageTestsAI: XCTestCase {
    private var folder: URL!
    private var keychain: [String: Data] = [:]
    private var fetches = 0
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("SettingsCoverage." + UUID().uuidString))

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsCoverageAI." + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saved = (UsageKeychain.service, UsageKeychain.update, UsageKeychain.add, UsageKeychain.copy, UsageKeychain.delete)
        let folder = folder!
        addTeardownBlock {
            (UsageKeychain.service, UsageKeychain.update, UsageKeychain.add, UsageKeychain.copy, UsageKeychain.delete) = saved
            try? FileManager.default.removeItem(at: folder)
        }
        UsageKeychain.service = "SettingsCoverage." + UUID().uuidString
        UsageKeychain.update = { [unowned self] query, attributes in
            let account = (query as NSDictionary)[kSecAttrAccount as String] as! String
            guard self.keychain[account] != nil else { return errSecItemNotFound }
            self.keychain[account] = (attributes as NSDictionary)[kSecValueData as String] as? Data; return errSecSuccess
        }
        UsageKeychain.add = { [unowned self] item in
            let item = item as NSDictionary
            self.keychain[item[kSecAttrAccount as String] as! String] = item[kSecValueData as String] as? Data; return errSecSuccess
        }
        UsageKeychain.copy = { [unowned self] query, result in
            guard let data = self.keychain[(query as NSDictionary)[kSecAttrAccount as String] as! String] else { return errSecItemNotFound }
            result.pointee = data as CFData; return errSecSuccess
        }
        UsageKeychain.delete = { [unowned self] query in
            self.keychain[(query as NSDictionary)[kSecAttrAccount as String] as! String] = nil; return errSecSuccess
        }
    }

    private func model() -> DockModel {
        let model = makeSettingsModel(self)
        model.fetchUsage = { [unowned self] _ in self.fetches += 1; throw UsageError.service }
        model.codexSignIn.resolve = { _, _ in nil }
        for widget in [model.toolkit.claudeCodeUsage, model.toolkit.geminiUsage] {
            widget.directory = folder.appendingPathComponent("reports")
            widget.settingsURL = folder.appendingPathComponent("claude/settings.json")
            widget.command = "/tmp/dockgrove --claude-statusline"
            widget.chooseFile = { _ in nil }
            widget.pasteboard = pasteboard
            widget.signIn.resolve = { _, _ in nil }
        }
        for widget in [model.toolkit.openaiUsage, model.toolkit.anthropicUsage, model.toolkit.cursorUsage] {
            widget.makeTransport = { ({ _ in throw AIUsageFailure.denied }, {}) }
        }
        addTeardownBlock { [model] in model.toolkit.claudeCodeUsage.stop(); model.toolkit.geminiUsage.stop() }
        return model
    }
    private func host(_ model: DockModel, _ provider: StudioAIProvider, _ method: AIConnectionMethod, expanded: Bool = true, height: CGFloat = 1000) -> SettingsHarness {
        SettingsHarness(AIConnectionSettings(model: model, provider: provider, initialMethod: method, optionsExpanded: expanded).padding(), width: 760, height: height)
    }
    private func isDisclosure(_ rect: CGRect) -> Bool { rect.width < 14 && rect.height < 14 }
    /// Clicks every control after the three connection-method buttons. Options start expanded;
    /// synthesized clicks cannot operate disclosure triangles.
    private func clickForm(_ harness: SettingsHarness) {
        harness.clickAll(from: 3) { !self.isDisclosure($0) }
    }
    private func wait(until condition: () -> Bool) {
        for _ in 0..<200 where !condition() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Copies the sign-in fixture under the name that selects its behavior.
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        var source = bundle.url(forResource: "SignInFixture", withExtension: nil)?.path
        if source == nil {
            let products = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            source = products.appendingPathComponent("SignInFixture").path
        }
        guard let source, FileManager.default.isExecutableFile(atPath: source) else { throw XCTSkip("SignInFixture was not built") }
        let path = folder.appendingPathComponent(name).path
        try FileManager.default.copyItem(atPath: source, toPath: path)
        return path
    }

    func testProviderAndMethodMetadata() {
        XCTAssertEqual(StudioAIProvider.allCases.map(\.title), ["OpenAI", "Claude", "Gemini", "Cursor"])
        XCTAssertEqual(StudioAIProvider.allCases.map(\.id), ["openai", "claude", "gemini", "cursor"])
        XCTAssertEqual(StudioAIProvider.allCases.map(\.icon), [.openAI, .claude, .google, .code])
        XCTAssertEqual(StudioAIProvider.allCases.map(\.kind), [nil, .claudeCodeUsage, .geminiUsage, .cursorUsage])
        XCTAssertEqual(StudioAIProvider(kind: .openaiUsage), .openai)
        XCTAssertEqual(StudioAIProvider(kind: .anthropicUsage), .claude)
        XCTAssertEqual(StudioAIProvider(kind: .claudeCodeUsage), .claude)
        XCTAssertEqual(StudioAIProvider(kind: .geminiUsage), .gemini)
        XCTAssertEqual(StudioAIProvider(kind: .cursorUsage), .cursor)
        XCTAssertNil(StudioAIProvider(kind: .focus))
        XCTAssertFalse(StudioAIProvider.gemini.supports(.token))
        XCTAssertFalse(StudioAIProvider.cursor.supports(.cli))
        XCTAssertTrue(StudioAIProvider.openai.supports(.cli))
        XCTAssertEqual(AIConnectionMethod.allCases.map(\.id), ["Sign in", "API token", "Use CLI"])
        XCTAssertEqual(AIConnectionMethod.allCases.map(\.icon), [.account, .key, .code])
    }

    func testOpenAISignInWithUsageAndOptions() throws {
        let model = model()
        let now = Date().timeIntervalSince1970
        let window = LimitWindow(usedPercent: 40, windowDurationMins: 300, resetsAt: now + 3600)
        model.usage = UsageResponse(rateLimits: nil, rateLimitsByLimitId: [
            "codex": LimitBucket(limitId: "codex", limitName: nil, primary: window, secondary: window, planType: nil),
            "other": LimitBucket(limitId: "other", limitName: "Other", primary: nil, secondary: nil, planType: nil)])
        model.refreshed = Date(); model.usageError = "Usage is a little stale."
        model.codexSignIn.resolve = { [path = try fixture("success")] _, _ in path }
        let harness = host(model, .openai, .signIn, height: 1200)
        defer { harness.close() }
        clickForm(harness)
        wait { !model.codexSignIn.busy && model.codexSignIn.authenticated }
        XCTAssertTrue(model.codexSignIn.authenticated, "Sign-in ran the fixture CLI")
        wait { fetches >= 2 }
        XCTAssertGreaterThanOrEqual(fetches, 2, "Refresh usage and the successful sign-in each fetch usage")
        harness.type("/no/such/codex", into: harness.textFields()[0])
        XCTAssertEqual(model.customCLI, "/no/such/codex")
        harness.settle(0.1)
    }

    func testOpenAIUseCLIWithSingleBucketAndMethodSwitching() {
        let model = model()
        model.usage = UsageResponse(rateLimits: LimitBucket(limitId: nil, limitName: nil, primary: nil, secondary: nil, planType: nil), rateLimitsByLimitId: nil)
        let harness = host(model, .openai, .cli, expanded: false)
        defer { harness.close() }
        clickForm(harness)
        XCTAssertEqual(model.codexSignIn.status, "Install ChatGPT / Codex to continue.")
        let methods = Array(harness.controls().prefix(3))
        harness.click(methods[0]) // Sign in
        harness.click(methods[1]) // API token
        XCTAssertFalse(harness.views(NSSecureTextField.self).isEmpty, "API token shows a secure field")
    }

    func testCodexSignInBusyCancels() throws {
        let model = model()
        model.codexSignIn.resolve = { [path = try fixture("waiting")] _, _ in path }
        model.codexSignIn.start(.codex)
        XCTAssertTrue(model.codexSignIn.busy)
        let harness = host(model, .openai, .signIn, expanded: false)
        defer { harness.close() }
        clickForm(harness) // Cancel
        XCTAssertFalse(model.codexSignIn.busy)
        XCTAssertNotEqual(model.codexSignIn.status, AISignIn.initialStatus)
    }

    func testAPITokenStatesSaveAndOptions() {
        for provider in [StudioAIProvider.openai, .claude, .cursor] {
            let model = model()
            let widget = provider == .openai ? model.toolkit.openaiUsage : provider == .claude ? model.toolkit.anthropicUsage : model.toolkit.cursorUsage
            widget.snapshot = AIUsageSnapshot(totals: Array(repeating: 1200, count: widget.provider.labels.count), start: Date(), end: Date())
            widget.status = "Updated just now"
            let harness = host(model, provider, .token, height: 1000)
            let field = harness.views(NSSecureTextField.self)[0]
            harness.type("  sk-test  ", into: field, submit: true)
            XCTAssertEqual(keychain[widget.provider.rawValue], Data("sk-test".utf8), "Saving trims and stores the token")
            wait { !widget.busy }
            harness.type("sk-again", into: harness.views(NSSecureTextField.self)[0])
            let save = harness.controls().first { $0.minX > field.convert(field.bounds, to: nil).maxX && abs($0.midY - field.convert(field.bounds, to: nil).midY) < 6 }
            harness.click(save!)
            XCTAssertEqual(keychain[widget.provider.rawValue], Data("sk-again".utf8))
            wait { !widget.busy }
            clickForm(harness) // Auto-refresh, refresh, account link, remove
            XCTAssertNil(keychain[widget.provider.rawValue], "Remove saved token clears it")
            widget.busy = true; widget.status = ""; widget.snapshot = nil
            harness.settle()
            harness.type("ignored", into: harness.views(NSSecureTextField.self)[0], submit: true)
            XCTAssertNil(keychain[widget.provider.rawValue], "Nothing is saved while busy")
            widget.busy = false
            harness.close()
        }
    }

    func testClaudeSetupStatesAndOptions() throws {
        let model = model()
        let widget = model.toolkit.claudeCodeUsage
        widget.signIn.resolve = { [path = try fixture("success")] _, _ in path }
        let harness = host(model, .claude, .signIn, height: 1100)
        defer { harness.close() }
        XCTAssertNotNil(widget.timer, "The form starts the usage reader")
        clickForm(harness)
        wait { widget.signIn.authenticated }
        harness.settle(0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: widget.settingsURL.path), "Capture writes only the temporary Claude settings")
        widget.status = "Could not read the report."
        harness.settle()
        widget.status = ""
        harness.settle()
        let now = Date()
        widget.report = LocalAIReport(provider: "claude", observed: now.addingTimeInterval(-4000), windows: [LocalAIWindow(name: "5 hour", used: 30, resets: now.addingTimeInterval(3600)), LocalAIWindow(name: "Weekly", used: 10, resets: now.addingTimeInterval(-60))], models: [], sessionCost: nil)
        harness.settle()
        widget.report = LocalAIReport(provider: "claude", observed: now, windows: [], models: [], sessionCost: nil)
        harness.settle()
    }

    func testClaudeUseCLI() {
        let model = model()
        let harness = host(model, .claude, .cli, expanded: false)
        defer { harness.close() }
        clickForm(harness)
        XCTAssertEqual(model.toolkit.claudeCodeUsage.signIn.status, "Install Claude Code to continue.")
    }

    func testGeminiImportCopyAndReports() {
        let model = model()
        let widget = model.toolkit.geminiUsage
        let harness = host(model, .gemini, .cli, height: 1000)
        defer { harness.close() }
        widget.status = "This is not a supported usage report."
        harness.settle()
        clickForm(harness)
        XCTAssertTrue(pasteboard.string(forType: .string)?.hasPrefix("gemini --output-format json") == true)
        XCTAssertEqual(widget.status, "Local usage snapshot cleared.")
        widget.status = "No local report yet."
        harness.settle()
        widget.report = LocalAIReport(provider: "gemini", observed: Date(), windows: [], models: [LocalAIModel(name: "gemini-pro", total: 1500, input: 1000, output: 500, cached: 0, requests: 2)], sessionCost: nil)
        harness.settle()
    }

    func testGeminiReportShowsTokenTotal() throws {
        let model = model()
        let widget = model.toolkit.geminiUsage
        // Showing the widget reloads its saved report, so save one.
        try FileManager.default.createDirectory(at: widget.directory, withIntermediateDirectories: true)
        try LocalAIStore.save(LocalAIReport(provider: "gemini", observed: Date(), windows: [], models: [LocalAIModel(name: "gemini-pro", total: 1500, input: 1000, output: 500, cached: 0, requests: 2)], sessionCost: nil), provider: .gemini, directory: widget.directory)
        widget.refresh()
        XCTAssertEqual(widget.report?.totalTokens, 1500)
        let fresh = host(model, .gemini, .cli, expanded: false)
        fresh.close()
        try LocalAIStore.save(LocalAIReport(provider: "gemini", observed: Date().addingTimeInterval(-4000), windows: [], models: [LocalAIModel(name: "gemini-pro", total: 1500, input: 1000, output: 500, cached: 0, requests: 2)], sessionCost: nil), provider: .gemini, directory: widget.directory)
        widget.refresh()
        let harness = host(model, .gemini, .cli, expanded: false)
        defer { harness.close() }
        // Appearing reloads the saved file; wait for that state rather than a fixed delay.
        wait { widget.report?.observed ?? .distantFuture < Date().addingTimeInterval(-3000) }
        XCTAssertEqual(widget.report?.totalTokens, 1500)
        XCTAssertTrue(widget.status.hasPrefix("Last received"), widget.status)
    }

    func testGeminiSignInRendersWithoutLaunchingTerminal() {
        let model = model()
        let harness = host(model, .gemini, .signIn, expanded: false)
        defer { harness.close() }
        // Gemini's own sign-in controls are covered by their owner; only render them here.
        XCTAssertNotNil(model.toolkit.geminiUsage.timer)
    }

    func testCursorSignIn() {
        let model = model()
        let harness = host(model, .cursor, .signIn)
        defer { harness.close() }
        clickForm(harness)
    }

    private func connections(_ model: DockModel, _ access: StudioAccess) -> SettingsHarness {
        SettingsHarness(StudioConnections(model: model).environment(\.studioAccess, access).padding(), width: 760, height: 1400)
    }

    func testConnectionsWithNothingToConnect() {
        let model = model()
        let none = StudioAccess(canUseFeatures: { _ in true }, canAccess: { _, _ in false }, canAccessAI: { _ in false })
        model.codexConnectionSelected = true
        let harness = connections(model, none)
        defer { harness.close() }
        XCTAssertTrue(harness.controls().isEmpty)
    }

    func testConnectionsAIProviderButtons() {
        let model = model()
        let ai = StudioAccess(canUseFeatures: { _ in true }, canAccess: { _, _ in false }, canAccessAI: { _ in true })
        model.codexConnectionSelected = true
        let harness = connections(model, ai)
        defer { harness.close() }
        for index in (0..<StudioAIProvider.allCases.count).reversed() { harness.click(harness.controls()[index]) }
        XCTAssertTrue(model.codexConnectionSelected)
        harness.click(harness.controls()[2])
        XCTAssertEqual(model.connectionSettingsKind, .geminiUsage)
        XCTAssertFalse(model.codexConnectionSelected)
        model.connectionSettingsKind = .openaiUsage
        harness.settle()
    }

    func testConnectionsServiceButtons() {
        let model = model()
        let services = StudioAccess(canUseFeatures: { _ in true }, canAccess: { _, kind in kind == .appleMusic || kind == .calendar }, canAccessAI: { _ in false })
        model.codexConnectionSelected = true
        let harness = connections(model, services)
        defer { harness.close() }
        harness.click(harness.controls()[1])
        XCTAssertEqual(model.connectionSettingsKind, .calendar)
        XCTAssertFalse(model.codexConnectionSelected)
    }

    func testConnectionSettingsButton() {
        var opened = 0
        let custom = SettingsHarness(ConnectionSettingsButton().environment(\.connectionSettingsAction, { opened += 1 }).padding(), width: 300, height: 100)
        custom.click(custom.controls()[0])
        custom.close()
        XCTAssertEqual(opened, 1)
        let standard = SettingsHarness(ConnectionSettingsButton().padding(), width: 300, height: 100)
        standard.click(standard.controls()[0])
        standard.close()
    }
}
