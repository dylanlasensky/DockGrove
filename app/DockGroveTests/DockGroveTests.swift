import XCTest
@testable import DockGrove

/// Locates the Swift fixture tools built alongside the test bundle.
enum Fixtures {
    static func path(_ name: String) throws -> String {
        let bundle = Bundle(for: DockGroveTests.self)
        if let url = bundle.url(forResource: name, withExtension: nil) { return url.path }
        // Products directory: <products>/DockGrove.app/Contents/PlugIns/DockGroveTests.xctest
        let products = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = products.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("Fixture \(name) was not built") }
        return url.path
    }
}

/// Runs DockGrove's regression suites inside the app. Failures stop at the failing precondition.
@MainActor final class DockGroveTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DockGroveTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testLayoutBehaviorStudioLicensingAndUsage() throws {
        runSelfTests(codexFixture: try Fixtures.path("CodexFixture"))
    }

    func testWeatherLocalAIWorkspaceAndCompanions() async throws {
        try await runIntegrationTests()
    }

    func testAISignInLifecycle() async throws {
        try await runAISignInTests(fixture: try Fixtures.path("SignInFixture"))
    }

    func testAssetCatalog() throws {
        try runAssetCatalogTests(output: try temporaryDirectory())
    }

    func testDockStudioRenders() throws {
        let output = try temporaryDirectory()
        try renderDockStudio(to: output)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
}
