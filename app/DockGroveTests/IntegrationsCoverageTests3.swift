import XCTest
import SwiftUI
import AppKit
import EventKit
import CoreLocation
import MapKit
import Contacts
import ServiceManagement
@testable import DockGrove

// MARK: - Utilities

@MainActor final class IntegrationsUtilitiesTests: XCTestCase {
    private func utilities() -> (Utilities, IntegrationsEventAccess) {
        let utility = Utilities(store: IntegrationsUI.defaults(self))
        let access = IntegrationsEventAccess()
        utility.reminderStore = access
        utility.chooseDirectory = { _ in XCTFail("Unexpected folder panel"); return nil }
        utility.sampleColor = { _ in XCTFail("Unexpected color sampler") }
        utility.capture = { XCTFail("Unexpected capture"); return nil }
        utility.setLoginItem = { _ in XCTFail("Unexpected login item change") }
        utility.chime = {}
        return (utility, access)
    }

    func testBookmarksPreferencesAndWaterReminder() {
        for odd in ["://example.com", "/://example.com", "?://example.com", "#://example.com"] { XCTAssertNil(Bookmark.url(odd)) }
        XCTAssertNil(Bookmark.url("ftp://example.com"))
        XCTAssertEqual(Bookmark.url("example.com")?.absoluteString, "https://example.com")
        let (utility, _) = utilities()
        utility.zones = ["UTC"]; XCTAssertEqual(utility.store.stringArray(forKey: "worldClockZones"), ["UTC"])
        utility.waterGoal = 6; XCTAssertEqual(utility.store.integer(forKey: "waterGoal"), 6)
        var chimes = 0
        utility.chime = { chimes += 1 }
        utility.timer?.fire(); IntegrationsUI.spin(0.05)
        XCTAssertFalse(utility.waterDue)
        utility.waterReminder = true
        XCTAssertTrue(utility.store.bool(forKey: "waterReminder"))
        utility.nextDrink = Date().addingTimeInterval(-1)
        utility.timer?.fire()
        XCTAssertTrue(IntegrationsUI.wait { utility.waterDue })
        XCTAssertEqual(chimes, 1)
        XCTAssertGreaterThan(utility.nextDrink, Date())
        Utilities.playChime()
        _ = LoginService.status()
    }

    func testNewestFolderSortToleratesMissingFiles() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        let old = folder.appendingPathComponent("old.txt"), new = folder.appendingPathComponent("new.txt")
        try Data().write(to: old); try Data().write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: old.path)
        let (utility, _) = utilities()
        utility.folderItems = [old, folder.appendingPathComponent("gone-a"), new, folder.appendingPathComponent("gone-b")]
        utility.folderSort = "Newest"
        XCTAssertEqual(utility.sortedFolderItems.prefix(2).map(\.lastPathComponent), ["new.txt", "old.txt"])
    }

    func testFolderColorScreenshotAndLoginActions() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        try Data().write(to: folder.appendingPathComponent("item.txt"))
        let (utility, _) = utilities()
        var panels: [NSOpenPanel] = []
        utility.chooseDirectory = { panels.append($0); return nil }
        utility.chooseFolder()
        XCTAssertTrue(panels[0].canChooseDirectories); XCTAssertFalse(panels[0].canChooseFiles)
        utility.chooseDirectory = { _ in folder }
        utility.chooseFolder()
        XCTAssertEqual(utility.folder, folder); XCTAssertEqual(utility.folderItems.map(\.lastPathComponent), ["item.txt"])

        utility.sampleColor = { handler in handler(nil); handler(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) }
        utility.pickColor()
        XCTAssertTrue(IntegrationsUI.wait { utility.colorHex == "#FF8000" })

        for (code, prefix) in [(Int32(0), "Capture finished"), (nil, "Capture cancelled")] {
            utility.capture = { code }
            utility.screenshot()
            XCTAssertTrue(utility.busy)
            utility.screenshot() // Ignored while a capture is running.
            XCTAssertTrue(IntegrationsUI.wait { !utility.busy })
            XCTAssertTrue(utility.status?.hasPrefix(prefix) == true)
        }

        var requests: [Bool] = []
        var status = SMAppService.Status.enabled
        utility.setLoginItem = { requests.append($0) }
        utility.loginStatus = { status }
        utility.setLogin(true); XCTAssertTrue(utility.loginEnabled); XCTAssertNil(utility.status)
        status = .requiresApproval
        utility.setLogin(false); XCTAssertFalse(utility.loginEnabled); XCTAssertTrue(utility.status?.hasPrefix("Approve DockGrove") == true)
        XCTAssertEqual(requests, [true, false])
        utility.setLoginItem = { _ in throw CocoaError(.featureUnsupported) }
        utility.setLogin(true); XCTAssertTrue(utility.status?.hasPrefix("Could not change login startup") == true)
    }

    func testRemindersLoadAndComplete() {
        let (utility, access) = utilities()
        access.allowReminders = .success(false)
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus == "Reminders permission was not granted." })
        access.allowReminders = .failure(CocoaError(.featureUnsupported))
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus.hasPrefix("Reminders are unavailable") })
        access.allowReminders = .success(true)
        access.reminders = nil
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus.hasPrefix("Incomplete reminders") })
        access.reminders = [access.reminder("Water plants"), access.reminder(nil), access.reminder("Call")]
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.reminders.count == 3 })
        XCTAssertEqual(utility.reminders.map { $0.title ?? "" }, ["", "Call", "Water plants"])

        let call = utility.reminders[1]
        utility.completeReminder(call)
        XCTAssertTrue(access.saved.first === call); XCTAssertTrue(call.isCompleted)
        XCTAssertFalse(utility.reminders.contains { $0 === call })
        access.saveError = CocoaError(.fileWriteNoPermission)
        let plants = utility.reminders.last!
        utility.completeReminder(plants)
        XCTAssertFalse(plants.isCompleted); XCTAssertEqual(utility.remindersStatus, "Could not save this reminder. Refresh and try again.")
    }
}

// MARK: - Companion

@MainActor final class IntegrationsCompanionTests: XCTestCase {
    func testMoodsActionsAndArtwork() {
        var state = CompanionState()
        XCTAssertEqual(state.mood, "Happy to be here")
        state.energy = 30; XCTAssertEqual(state.mood, "Ready for a nap")
        state.fullness = 30; XCTAssertEqual(state.mood, "A little snack?")
        state.resting = true; XCTAssertEqual(state.mood, "Dreaming softly")

        let store = IntegrationsUI.defaults(self)
        let pet = Companion(defaults: store)
        pet.play(); XCTAssertEqual(pet.playRequest, 1)
        pet.state.resting = true
        pet.play(); XCTAssertEqual(pet.playRequest, 1)
        pet.tick()
        pet.rename("   "); XCTAssertEqual(pet.state.name, "Miso")
        pet.rename("  Pixel  "); XCTAssertEqual(pet.state.name, "Pixel")
        XCTAssertEqual(CompanionArtwork.frames("Not an animal").count, CompanionArtwork.frames("Miso").count)
        XCTAssertEqual(CatPortrait(resting: false, accent: .blue).animal, "Miso")
        pet.state.reward(); XCTAssertEqual(pet.state.sessions, 1)
        pet.animal = "Fox"
        let restored = Companion(defaults: store)
        XCTAssertEqual(restored.animal, "Fox"); XCTAssertEqual(restored.state.sessions, 1)
    }

    func testCompanionViewStatesAndActions() {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        IntegrationsUI.render(CompanionView(pet: pet, accent: .orange))
        pet.state.resting = true
        IntegrationsUI.render(CompanionView(pet: pet, accent: .orange), dark: true)
        pet.state.resting = false
        let view = CompanionView(pet: pet, accent: .orange)
        let fullness = pet.state.fullness
        IntegrationsUI.press(IntegrationsUI.body(view), "Feed"); XCTAssertGreaterThan(pet.state.fullness, fullness)
        IntegrationsUI.press(IntegrationsUI.body(view), "Play"); XCTAssertEqual(pet.playRequest, 1)
        IntegrationsUI.press(IntegrationsUI.body(view), "Rest"); XCTAssertTrue(pet.state.resting)
        IntegrationsUI.press(IntegrationsUI.body(CompanionView(pet: pet, accent: .orange)), "Wake up"); XCTAssertFalse(pet.state.resting)
        IntegrationsUI.press(IntegrationsUI.body(view), "Rename"); XCTAssertEqual(pet.state.name, "Miso")
        IntegrationsUI.appear(IntegrationsUI.body(view))
    }

    func testDrawingFromAssetDirectoryAndContexts() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        defer { CompanionDrawing.assetDirectory = nil }
        func png(_ name: String) -> Data {
            let image = NSImage(named: "Companion-" + name + "-pixel")!
            return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        }
        try png("fox").write(to: folder.appendingPathComponent("fox-pixel.png"))
        let catalog = folder.appendingPathComponent("Companion-cow-pixel.imageset")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        try png("cow").write(to: catalog.appendingPathComponent("cow-pixel.png"))
        CompanionDrawing.assetDirectory = folder
        XCTAssertEqual(CompanionDrawing.rig("Fox")?.frames.count, 16)
        XCTAssertEqual(CompanionDrawing.rig("Cow")?.frames.count, 16)
        XCTAssertNil(CompanionDrawing.rig("Rabbit"))
        CompanionDrawing.assetDirectory = nil

        var motion = CompanionMotion()
        XCTAssertTrue((0..<16).contains(CompanionDrawing.frameIndex(animal: "Unknown", motion: motion)))
        motion.velocity = 0.01
        XCTAssertTrue((0..<8).contains(CompanionDrawing.frameIndex(animal: "Fox", motion: motion)))

        CompanionDrawing.draw(animal: "Fox", motion: motion, in: CGRect(x: 0, y: 0, width: 200, height: 120))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        for (animal, facing, reduced) in [("Rabbit", 1.0, false), ("Cow", -1.0, true), ("Fox", 1.0, false), ("Unknown", 1.0, false)] {
            motion.facing = facing
            CompanionDrawing.draw(animal: animal, motion: motion, in: CGRect(x: 0, y: 0, width: 200, height: 120), reducedMotion: reduced)
        }
    }

    func testSpriteSceneClock() {
        let scene = CompanionSpriteScene(size: CGSize(width: 250, height: 180))
        scene.update(10)
        scene.update(10.5)
        scene.resetClock()
        scene.update(11)
        XCTAssertTrue((0..<16).contains(scene.frameIndex))
    }

    func testSpriteStageVisibilityAndInput() {
        let stage = CompanionStage(frame: NSRect(x: 0, y: 0, width: 250, height: 180))
        stage.animal = "Fox"; stage.resting = true
        XCTAssertEqual(stage.animal, "Fox"); XCTAssertTrue(stage.resting)
        XCTAssertNil(stage.hitTest(NSPoint(x: 10, y: 10)))
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 250, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = stage
        window.orderFront(nil)
        stage.isHidden = true
        XCTAssertTrue(stage.isPaused)
        stage.isHidden = false
        for name in [NSWindow.didChangeOcclusionStateNotification, NSApplication.didUnhideNotification] { NotificationCenter.default.post(name: name, object: window) }
        // A briefly visible, transparent window exercises the unpaused path.
        window.alphaValue = 0.01
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.orderFrontRegardless()
        IntegrationsUI.wait(1) { window.occlusionState.contains(.visible) }
        stage.refreshScene()
        window.orderOut(nil)
        window.contentView = nil
    }
}

// MARK: - Codex usage

final class IntegrationsCodexUsageTests: XCTestCase {
    func testLimitPresentation() throws {
        XCTAssertEqual(LimitWindow(usedPercent: 1, windowDurationMins: 90, resetsAt: nil).title, "90 min")
        XCTAssertEqual(LimitWindow(usedPercent: 1, windowDurationMins: nil, resetsAt: nil).resetDescription, "Reset time unavailable")
        XCTAssertEqual(LimitWindow(usedPercent: 1, windowDurationMins: nil, resetsAt: 1).resetDescription, "Awaiting reset refresh")
        XCTAssertTrue(LimitWindow(usedPercent: 1, windowDurationMins: nil, resetsAt: Date().addingTimeInterval(7200).timeIntervalSince1970).resetDescription.hasPrefix("Resets "))
        XCTAssertEqual(LimitBucket(limitId: nil, limitName: "Named", primary: nil, secondary: nil, planType: nil).title, "Named")
        XCTAssertEqual(LimitBucket(limitId: "codex", limitName: nil, primary: nil, secondary: nil, planType: nil).title, "Codex")
        XCTAssertEqual(LimitBucket(limitId: "other", limitName: nil, primary: nil, secondary: nil, planType: nil).title, "other")
        XCTAssertEqual(LimitBucket(limitId: nil, limitName: nil, primary: nil, secondary: nil, planType: nil).title, "Plan usage")
        let sorted = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimitsByLimitId":{"b":{},"codex":{},"a":{},"c":{}}}"#.utf8))
        XCTAssertEqual(sorted.buckets.map(\.0), ["codex", "a", "b", "c"])
        let single = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimits":{}}"#.utf8))
        XCTAssertEqual(single.buckets.map(\.0), ["default"])
        XCTAssertTrue(try JSONDecoder().decode(UsageResponse.self, from: Data("{}".utf8)).buckets.isEmpty)
        for error in [UsageError.missingCLI, .timeout, .disconnected, .service, .noWindows] { XCTAssertFalse(error.errorDescription!.isEmpty) }
    }

    func testAppServerFailureModes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DockGroveIntegrations." + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func codex(_ mode: String) throws -> String {
            let path = folder.appendingPathComponent("codex-" + mode).path
            try FileManager.default.copyItem(atPath: try Fixtures.path("CodexFixture"), toPath: path)
            return path
        }
        let buckets = try UsageClient.fetch(custom: try codex("buckets"))
        XCTAssertEqual(buckets.buckets.map(\.0), ["codex", "alpha", "beta", "zeta"])
        for (mode, expected) in [("exit", UsageError.disconnected), ("error", .service), ("nowindows", .noWindows), ("flood", .service)] {
            XCTAssertThrowsError(try UsageClient.fetch(custom: try codex(mode))) { error in
                XCTAssertEqual((error as? UsageError).map { "\($0)" }, "\(expected)", mode)
            }
        }
        XCTAssertThrowsError(try UsageClient.fetch(custom: try codex("hang"), timeout: 0.3)) { XCTAssertEqual(($0 as? UsageError).map { "\($0)" }, "timeout") }
        Thread.sleep(forTimeInterval: 1.3) // Lets the delayed SIGKILL check run.
    }
}

// MARK: - Weather

@MainActor final class IntegrationsWeatherTests: XCTestCase {
    private let reading = WeatherReading(temperature: Measurement(value: 20, unit: .celsius), apparentTemperature: Measurement(value: 19, unit: .celsius),
                                         condition: "Clear", symbolName: "sun.max", date: Date(timeIntervalSince1970: 1_800_000_000),
                                         attributionURL: URL(string: "https://weatherkit.apple.com/legal")!, lightMarkURL: URL(string: "https://example.com/light.png")!, darkMarkURL: URL(string: "https://example.com/dark.png")!)

    private func place(_ address: [String: String]) -> CLPlacemark {
        let postal = CNMutablePostalAddress()
        postal.city = address["city"] ?? ""; postal.state = address["state"] ?? ""; postal.country = address["country"] ?? ""
        return MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3, longitude: -122.0), postalAddress: postal)
    }

    func testFetchNamesPlacesAndRejectsMissingCities() async throws {
        let reading = reading
        let snapshot = try await AppleWeatherClient.fetch(city: "cupertino", geocode: { _ in [self.place(["city": "Cupertino", "state": "CA", "country": "United States"])] }, current: { _ in reading })
        XCTAssertEqual(snapshot.city, "Cupertino, CA, United States")
        XCTAssertEqual(snapshot.condition, "Clear"); XCTAssertEqual(snapshot.darkMarkURL.lastPathComponent, "dark.png")
        let deduplicated = try await AppleWeatherClient.fetch(city: "x", geocode: { _ in [self.place(["city": "Singapore", "state": "Singapore", "country": "Singapore"])] }, current: { _ in reading })
        XCTAssertEqual(deduplicated.city, "Singapore")
        let unnamed = try await AppleWeatherClient.fetch(city: "typed city", geocode: { _ in [self.place([:])] }, current: { _ in reading })
        XCTAssertFalse(unnamed.city.isEmpty)
        do { _ = try await AppleWeatherClient.fetch(city: "nowhere", geocode: { _ in [] }, current: { _ in reading }); XCTFail("Missing city accepted") }
        catch { XCTAssertTrue(error is WeatherLookupError) }

        let geocode = AppleWeatherClient.geocode, current = AppleWeatherClient.current
        defer { AppleWeatherClient.geocode = geocode; AppleWeatherClient.current = current }
        AppleWeatherClient.geocode = { city in XCTAssertEqual(city, "Paris"); return [self.place(["city": "Paris", "country": "France"])] }
        AppleWeatherClient.current = { _ in reading }
        let paris = try await AppleWeatherClient.fetch(city: "Paris")
        XCTAssertEqual(paris.city, "Paris, France")
    }
}

