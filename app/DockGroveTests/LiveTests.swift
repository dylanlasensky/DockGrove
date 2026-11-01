import XCTest
@testable import DockGrove

/// Network and hardware checks. Opt in with `TEST_RUNNER_DOCKGROVE_LIVE_TESTS=1 xcodebuild test …`;
/// set `TEST_RUNNER_DOCKGROVE_WEATHER_CITY` to choose the Apple Weather city.
@MainActor final class LiveTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        try XCTSkipUnless(environment["DOCKGROVE_LIVE_TESTS"] == "1", "Live tests are opt-in.")
    }

    func testGitHubPublicRepository() async throws {
        let snapshot = try await GitHubClient.fetch("dylanlasensky/DockGrove", useCLI: false)
        XCTAssertEqual(snapshot.repository.full_name.lowercased(), "dylanlasensky/dockgrove")
    }

    func testCodexAllowance() async throws {
        do {
            let usage = try await Task.detached { try UsageClient.fetch(custom: "") }.value
            XCTAssertFalse(usage.buckets.isEmpty)
        } catch {
            throw XCTSkip("Codex is not signed in on this Mac: \(error.localizedDescription)")
        }
    }

    func testCurrencyReferenceRate() async throws {
        let currency = CurrencyWidget()
        currency.refresh()
        while currency.loading { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNotNil(currency.report, currency.status)
    }

    func testSystemSampling() async throws {
        let monitor = SystemMonitor()
        monitor.sample()
        // Match the widget cadence: cached host statistics may not advance in 250 ms.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        monitor.sample()
        XCTAssertTrue(monitor.available)
        XCTAssertTrue((0...100).contains(monitor.memory))
    }

    func testAudioOutputDiscovery() throws {
        let audio = AudioControl()
        audio.refresh()
        try XCTSkipIf(audio.outputs.isEmpty, "No audio outputs available")
    }

    func testAppleWeather() async throws {
        let weather = try await AppleWeatherClient.fetch(city: environment["DOCKGROVE_WEATHER_CITY"] ?? "Cupertino")
        XCTAssertFalse(weather.city.isEmpty)
    }
}
