import XCTest

/// Launches the real app with `--native-test`: renders every widget, checks replacement-Dock geometry
/// and window states with isolated preferences, writes PNGs, then quits. Never changes Apple's Dock.
final class NativeRenderingTests: XCTestCase {
    func testNativeRenderingAndWindowStates() throws {
        let output = URL(fileURLWithPath: "/private/tmp/DockGroveNative-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let app = XCUIApplication()
        app.launchArguments = ["--native-test", output.path]
        app.launch()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 180), "Native tests did not finish")
        let result = try String(contentsOf: output.appendingPathComponent("native-result.txt"), encoding: .utf8)
        XCTAssertEqual(result, "PASS")
        let renders = try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasSuffix(".png") }
        XCTAssertFalse(renders.isEmpty)
        for name in renders {
            let attachment = XCTAttachment(contentsOfFile: output.appendingPathComponent(name))
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
