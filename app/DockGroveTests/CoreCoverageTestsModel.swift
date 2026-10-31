import XCTest
import AppKit
import WeatherKit
import SwiftUI
@testable import DockGrove

private struct ModelTestError: Error {}

/// Grants StoreKit tiers to `PurchaseManager.shared` through its injectable store.
@MainActor private func grant(_ productIDs: Set<String>) async {
    let manager = PurchaseManager.shared
    manager.store = StoreKitClient(
        updates: { AsyncStream { $0.finish() } },
        latest: { id in productIDs.contains(id) ? PurchaseTransaction(productID: id, nonConsumable: true, revoked: false, upgraded: false, finish: {}) : nil },
        products: { _ in [] },
        sync: {})
    await manager.refreshEntitlements()
}

@MainActor private func resetPurchases() async {
    await grant([])
    PurchaseManager.shared.store = .live
}

@MainActor private func settle(_ seconds: Double = 0.15) async {
    try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
}

@MainActor private func waitUntil(_ condition: () -> Bool, timeout: Double = 5) async {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
}

private let fullAccess: Set<String> = [AccessTier.full.productID!]
private let plusAccess: Set<String> = [AccessTier.plus.productID!]

private func usageResponse() throws -> UsageResponse {
    let json = #"{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":10}},"other":{"limitId":"other"}}}"#
    return try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
}

@MainActor final class CoreCoverageTestsModel: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoreModel." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        await resetPurchases()
        try? FileManager.default.removeItem(at: directory)
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "CoreModel." + UUID().uuidString)! }

    private func makeApp(_ name: String, in folder: URL? = nil) throws -> DockApp {
        let url = (folder ?? directory).appendingPathComponent(name + ".app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DockApp(url: url)
    }

    private func model(_ store: UserDefaults? = nil, purchases: Bool = true) -> DockModel {
        let model = DockModel(defaults: store ?? defaults(), purchasesEnabled: purchases)
        model.fetchUsage = { _ in throw ModelTestError() }
        model.openApplication = { _ in XCTFail("Unexpected app launch") }
        model.chooseExportURL = { nil }
        model.chooseImportURL = { nil }
        return model
    }

    // MARK: DockModel

    func testPersistedSettingsAndConnectionActions() {
        let store = defaults()
        let model = model(store, purchases: false)
        XCTAssertTrue(model.canAccessAI, "Without StoreKit every feature is available")
        XCTAssertTrue(model.toolkit.canAccess(.clipboard))
        model.usageEnabled = true; model.customCLI = "/bin/codex"; model.selectedBucket = "other"
        model.visible = false; model.dockName = String(repeating: "n", count: 50)
        model.snappingEnabled = true; model.snapRequiresOption = false; model.screenID = "screen"
        XCTAssertTrue(store.bool(forKey: "usageEnabled"))
        XCTAssertEqual(store.string(forKey: "customCLI"), "/bin/codex")
        XCTAssertEqual(store.string(forKey: "selectedBucket"), "other")
        XCTAssertEqual(store.object(forKey: "dockVisible") as? Bool, false)
        XCTAssertEqual(store.string(forKey: "dockName")?.count, 40)
        XCTAssertTrue(store.bool(forKey: "snappingEnabled"))
        XCTAssertEqual(store.object(forKey: "snapRequiresOption") as? Bool, false)
        XCTAssertEqual(model.screenID, "screen")
        var opened = 0
        model.settingsAction = { opened += 1 }
        model.openCodexConnection()
        XCTAssertTrue(model.codexConnectionSelected)
        model.openConnectionSettings(.search)
        XCTAssertFalse(model.codexConnectionSelected)
        XCTAssertEqual(model.connectionSettingsKind, .search)
        XCTAssertEqual(opened, 2)
        XCTAssertGreaterThan(model.toolbarWidth(screenWidth: 1000, widths: []), 0)
        XCTAssertNil(model.activeBucket)
    }

    func testInitFallbacksStoredAppsAndObservers() async throws {
        let app = try makeApp("Stored")
        let store = defaults()
        store.set(Data(), forKey: "accent")
        store.set(true, forKey: "usageEnabled")
        store.set([app.id, directory.appendingPathComponent("Missing.app").path], forKey: "apps")
        let model = model(store)
        XCTAssertEqual(model.accent, "White")
        XCTAssertEqual(model.apps, [app])
        XCTAssertNil(model.usage)

        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        LicenseManager.shared.objectWillChange.send()
        await settle()
        XCTAssertGreaterThan(changes, 0)
        observation.cancel()

        // The 300 s timer refreshes only when usage is enabled.
        model.usageEnabled = false
        model.timer?.fire(); await settle(0.05)
        XCTAssertFalse(model.fetching)
    }

    func testPurchaseChangesRefreshAndClearUsage() async throws {
        let model = model()
        model.usageEnabled = true
        let response = try usageResponse()
        model.fetchUsage = { _ in response }
        await grant(fullAccess)
        await waitUntil { model.usage != nil }
        XCTAssertNotNil(model.usage)
        XCTAssertEqual(model.activeBucket?.limitId, "codex")
        model.selectedBucket = "missing"
        XCTAssertNotNil(model.activeBucket)

        // The periodic timer refreshes enabled usage.
        model.refreshed = nil
        model.timer?.fire()
        await waitUntil { model.refreshed != nil }
        XCTAssertNotNil(model.refreshed)

        await grant([])
        await waitUntil { model.usage == nil }
        XCTAssertNil(model.usage)
    }

    func testRefreshUsageOutcomes() async throws {
        let model = model()
        model.refreshUsage()
        XCTAssertFalse(model.fetching, "Locked tiers never fetch")
        await grant(fullAccess)

        model.fetchUsage = { _ in throw UsageError.missingCLI }
        model.refreshUsage()
        model.refreshUsage() // Ignored while fetching.
        await waitUntil { !model.fetching }
        XCTAssertEqual(model.usageError, UsageError.missingCLI.localizedDescription)

        model.fetchUsage = { _ in throw ModelTestError() }
        model.refreshUsage()
        await waitUntil { !model.fetching }
        XCTAssertEqual(model.usageError, "Could not read usage. Check your Codex connection in Settings.")

        // A superseded request is discarded.
        let gate = DispatchSemaphore(value: 0)
        let response = try usageResponse()
        model.fetchUsage = { _ in gate.wait(); return response }
        model.refreshUsage()
        model.fetchUsage = { _ in response }
        model.reloadSignedInUsage()
        await waitUntil { model.usage != nil }
        gate.signal()
        await settle()
        XCTAssertNotNil(model.usage)
        XCTAssertNil(model.usageError)

        // Losing access while a fetch is in flight drops the result.
        model.usage = nil
        model.fetchUsage = { _ in gate.wait(); return response }
        model.refreshUsage()
        await grant([])
        gate.signal()
        await waitUntil { !model.fetching }
        XCTAssertNil(model.usage)
    }

    func testAppEditingOpeningAndPicker() async throws {
        let model = model()
        let a = try makeApp("Alpha"), b = try makeApp("Beta"), c = try makeApp("Gamma")
        model.apps = [a, b]
        var launched: [URL] = []
        model.openApplication = { launched.append($0) }
        model.open(a)
        XCTAssertEqual(launched, [a.url])

        model.move(a, by: 1)
        XCTAssertEqual(model.apps, [b, a])
        model.move(a, by: 5)
        XCTAssertEqual(model.apps, [b, a])

        model.pin(c)
        XCTAssertEqual(model.apps, [b, a, c])
        model.dropApp(c.id, onto: b)
        XCTAssertEqual(model.apps, [c, b, a])
        model.dropApp(c.id, onto: c)
        XCTAssertEqual(model.apps, [c, b, a])

        model.addApps()
        XCTAssertNotNil(model.appPickerWindow)
        model.appPickerWindow?.close(); model.appPickerWindow = nil
    }

    func testProfilesSaveApplyExportImport() throws {
        let model = model()
        let a = try makeApp("Alpha"), b = try makeApp("Beta")
        model.apps = [a, b]
        model.toolkit.profileName = "  Work  "
        model.saveProfile()
        XCTAssertEqual(model.toolkit.profiles.last?.apps, [a.id, b.id])

        var profile = DockProfile(name: "P", apps: [b.id, b.id, a.id, directory.appendingPathComponent("Gone.app").path, "/bin/ls"], widgets: ["search", "search", "bogus"], accent: "Blue", size: 99)
        profile.edge = "Top"
        model.applyProfile(profile)
        XCTAssertEqual(model.apps, [b, a])
        XCTAssertEqual(model.toolkit.enabled, ["search"])
        XCTAssertEqual(model.iconSize, 64)

        // Export: success, then a destination that cannot be written.
        let export = directory.appendingPathComponent("layouts.json")
        model.exportProfiles() // Cancelled chooser.
        model.chooseExportURL = { export }
        model.exportProfiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        model.chooseExportURL = { self.directory.appendingPathComponent("missing/layouts.json") }
        model.exportProfiles()
        XCTAssertEqual(model.systemError, "Could not export layouts.")

        // Import: valid export, then a file that is not a layout list.
        model.systemError = nil
        let before = model.toolkit.profiles.count
        model.importProfiles() // Cancelled chooser.
        model.chooseImportURL = { export }
        model.importProfiles()
        XCTAssertEqual(model.toolkit.profiles.count, before * 2)
        let invalid = directory.appendingPathComponent("invalid.json")
        try Data("{}".utf8).write(to: invalid)
        model.chooseImportURL = { invalid }
        model.importProfiles()
        XCTAssertEqual(model.systemError, "This file is not a valid DockGrove layout export.")
    }

    // MARK: Toolkit

    func testToolkitSettingsLockingAndWidgets() async throws {
        let store = defaults()
        let kit = Toolkit(store: store, purchasesEnabled: true)
        kit.autoHide = true; kit.hideOnOverlap = true; kit.screenIndex = 2; kit.clipboardEnabled = true
        XCTAssertTrue(store.bool(forKey: "autoHide"))
        XCTAssertTrue(store.bool(forKey: "hideOnOverlap"))
        XCTAssertEqual(store.integer(forKey: "screenIndex"), 2)

        var changes = 0
        let observation = kit.objectWillChange.sink { changes += 1 }
        kit.pet.objectWillChange.send()
        await settle(0.05)
        XCTAssertGreaterThan(changes, 0)
        observation.cancel()

        XCTAssertFalse(kit.canAccess(.clipboard))
        kit.clipboard = ["x"]
        kit.stopLockedWidgets()
        XCTAssertTrue(kit.clipboard.isEmpty)

        kit.toggle(.search, false)
        XCTAssertFalse(kit.enabled.contains("search"))

        var chosen = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/a"), URL(string: "https://example.com")!]
        kit.chooseFiles = { chosen }
        kit.addFiles()
        XCTAssertEqual(kit.files, ["/tmp/a"])
        chosen = []
        kit.addFiles()
        XCTAssertEqual(kit.files, ["/tmp/a"])
    }

    func testToolkitTickTimerAndClipboard() async throws {
        let kit = Toolkit(store: defaults(), purchasesEnabled: true)
        kit.focusEnd = Date().addingTimeInterval(-1)
        kit.tickNow()
        XCTAssertTrue(kit.focusFinished)
        XCTAssertNil(kit.focusEnd)
        for _ in 0..<15 { kit.tickNow() }
        kit.tick?.fire(); await settle(0.05)

        await grant(plusAccess)
        let board = NSPasteboard(name: NSPasteboard.Name("CoreModel." + UUID().uuidString))
        defer { board.releaseGlobally() }
        kit.pasteboard = board
        kit.clipboardEnabled = true
        board.clearContents(); board.setString("first", forType: .string)
        kit.tickNow()
        board.clearContents(); board.setString("second", forType: .string)
        kit.tickNow()
        board.clearContents(); board.setString("first", forType: .string)
        kit.tickNow()
        XCTAssertEqual(kit.clipboard, ["first", "second"])
        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString("secret", forType: .string)
        kit.tickNow()
        XCTAssertEqual(kit.clipboard, ["first", "second"])
    }

    func testToolkitApplicationScanAndWeather() async throws {
        let kit = Toolkit(store: defaults(), purchasesEnabled: true)
        let other = directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try makeApp("beta"); _ = try makeApp("Alpha"); _ = try makeApp("Beta", in: other)
        kit.applicationRoots = [directory.path, directory.appendingPathComponent("absent").path]
        kit.scanApplications()
        kit.scanApplications(force: true) // Ignored while scanning.
        await waitUntil { !kit.scanningApps }
        XCTAssertEqual(kit.applications.map(\.url.lastPathComponent).prefix(4), ["Alpha.app", "Beta.app", "beta.app", "Finder.app"])
        kit.scanApplications() // Already loaded and not forced.
        XCTAssertFalse(kit.scanningApps)
        kit.scanApplications(force: true)
        await waitUntil { !kit.scanningApps }
        XCTAssertEqual(kit.applications.count, 4)

        let snapshot = WeatherSnapshot(city: "Paris", temperature: .init(value: 20, unit: .celsius), apparentTemperature: .init(value: 19, unit: .celsius), condition: "Clear", symbolName: "sun.max", date: Date(), attributionURL: URL(string: "https://example.com")!, lightMarkURL: URL(string: "https://example.com/l")!, darkMarkURL: URL(string: "https://example.com/d")!)
        kit.weatherFetch = { _ in snapshot }
        kit.weatherCity = "Paris"
        kit.fetchWeather()
        await waitUntil { kit.weatherSnapshot != nil }
        XCTAssertEqual(kit.weatherText, "68°F")
        kit.weatherSnapshot = nil
        await kit.loadWeather()
        XCTAssertNotNil(kit.weatherSnapshot)
    }

    // MARK: Remaining model and toolkit surface

    func testModelAppearanceGeometryAndOrdering() throws {
        let store = defaults()
        let model = model(store)
        model.showClock = false; model.theme = "Pearl"; model.widthFraction = 0.5; model.notchEnabled = true
        model.notchWidth = -10; model.alignment = 0.2; model.elevation = 0.3; model.albumColors = false; model.showUsageCard = false
        XCTAssertEqual(store.object(forKey: "notchWidth") as? Double, model.notchWidth)
        XCTAssertEqual(store.string(forKey: "theme"), "Pearl")
        _ = model.color
        model.accent = "Blue"; _ = model.color
        model.theme = "Glass"; _ = model.color
        XCTAssertEqual(model.scheme, .dark)
        XCTAssertGreaterThan(model.dockHeight, model.barHeight)
        XCTAssertGreaterThan(model.barHeight, model.tileHeight)
        XCTAssertGreaterThan(model.toolbarWidth(screenWidth: 1200, widths: [100, 200]), 0)
        model.fitToolbarToContent = false
        XCTAssertGreaterThan(model.toolbarWidth(screenWidth: 1200, widths: [100]), 0)
        XCTAssertEqual(model.screenID, "")
        if let screen = NSScreen.screens.first {
            XCTAssertFalse(DockModel.displayID(screen).isEmpty)
            model.screenID = DockModel.displayID(screen)
            XCTAssertEqual(model.selectedScreen, screen)
        }
        model.screenID = "unknown"
        XCTAssertEqual(model.selectedScreen == nil, NSScreen.screens.isEmpty)

        let a = try makeApp("Alpha"), b = try makeApp("Beta"), c = try makeApp("Gamma")
        model.apps = [a, b, c]
        XCTAssertEqual(a.name, "Alpha")
        XCTAssertGreaterThan(a.icon.size.width, 0)
        XCTAssertFalse(a.isRunning)
        model.toolkit.enabled = ["search", "bogus"]
        model.entryOrder = ["removed-entry"]
        model.moveEntry("app:" + c.id, onto: "app:" + a.id)
        XCTAssertEqual(model.entryOrder.last, "removed-entry")
        XCTAssertEqual(model.orderedEntries.first?.id, "app:" + c.id)
        model.reorder(c.id, before: b)
        XCTAssertEqual(model.apps, [a, c, b])
        model.reorder(c.id, before: c)
        model.reorder(b.id, before: a)
        XCTAssertEqual(model.apps, [b, a, c])
        model.remove(a)
        XCTAssertEqual(model.apps, [b, c])
        model.undoAppChange()
        XCTAssertEqual(model.apps.count, 3)
    }

    func testLiveLaunchOfMissingApplicationFailsHarmlessly() async {
        // A path that does not exist exercises the production launcher without starting anything.
        DockModel.launch(directory.appendingPathComponent("Missing.app"))
        await settle(0.5)
    }

    func testLivePanelsReturnNothingWhenCancelled() {
        func cancelNextModal() {
            RunLoop.main.perform(inModes: [.modalPanel]) { NSApp.abortModal() }
        }
        cancelNextModal(); XCTAssertNil(DockModel.runSavePanel())
        cancelNextModal(); XCTAssertNil(DockModel.runOpenPanel())
        cancelNextModal(); XCTAssertEqual(Toolkit.runFilePanel(), [])
    }

    func testToolkitTimerTasksAndWidgetOrder() async {
        let store = defaults()
        store.set(Data("not json".utf8), forKey: "tasks")
        let kit = Toolkit(store: store, purchasesEnabled: true)
        XCTAssertTrue(kit.tasks.isEmpty)
        kit.note = "n"; kit.richWidgets = false; kit.showRunning = false
        kit.draftTask = "  Write  "; kit.addTask(); kit.addTask()
        XCTAssertEqual(kit.tasks.map(\.title), ["Write"])
        XCTAssertFalse(kit.tasks[0].done)
        XCTAssertEqual(kit.timerText, "25:00")
        kit.toggleTimer(); XCTAssertNotNil(kit.focusEnd)
        kit.toggleTimer(); XCTAssertNil(kit.focusEnd)
        kit.resetTimer(0); kit.toggleTimer(); XCTAssertEqual(kit.seconds, 1500)
        kit.resetTimer(5); XCTAssertEqual(kit.seconds, 300)

        kit.enabled = ["search", "focus"]
        kit.toggle(.clipboard, true) // Locked on the free tier.
        XCTAssertFalse(kit.enabled.contains("clipboard"))
        kit.toggle(.tasks, true); kit.toggle(.tasks, true)
        XCTAssertEqual(kit.enabled, ["search", "focus", "tasks"])
        kit.moveWidget(.search, by: 1)
        XCTAssertEqual(kit.enabled, ["focus", "search", "tasks"])
        kit.moveWidget(.search, by: 9)
        XCTAssertEqual(kit.enabled, ["focus", "search", "tasks"])

        // An empty clipboard change is ignored.
        await grant(plusAccess)
        let board = NSPasteboard(name: NSPasteboard.Name("CoreModel." + UUID().uuidString))
        defer { board.releaseGlobally() }
        kit.pasteboard = board
        kit.clipboardEnabled = true
        board.clearContents()
        kit.tickNow()
        board.clearContents(); board.setString("", forType: .string)
        kit.tickNow()
        XCTAssertTrue(kit.clipboard.isEmpty)
    }

    func testWeatherFailuresAndSupersededRequests() async {
        let kit = Toolkit(store: defaults())
        kit.weatherCity = "Nowhere"
        await kit.loadWeather { _ in throw WeatherLookupError.cityNotFound }
        XCTAssertEqual(kit.weatherDetail, "City not found. Try adding a state or country.")
        await kit.loadWeather { _ in throw WeatherError.permissionDenied }
        XCTAssertEqual(kit.weatherDetail, "Apple Weather isn’t available in this build.")
        await kit.loadWeather { _ in throw ModelTestError() }
        XCTAssertEqual(kit.weatherText, "Unavailable")
        XCTAssertTrue(kit.weatherDetail.hasPrefix("Could not load Apple Weather"))

        let snapshot = WeatherSnapshot(city: "Paris", temperature: .init(value: 20, unit: .celsius), apparentTemperature: .init(value: 19, unit: .celsius), condition: "Clear", symbolName: "sun.max", date: Date(), attributionURL: URL(string: "https://example.com")!, lightMarkURL: URL(string: "https://example.com/l")!, darkMarkURL: URL(string: "https://example.com/d")!)
        await kit.loadWeather { _ in kit.weatherCity = "Rome"; return snapshot }
        XCTAssertNil(kit.weatherSnapshot)
        await kit.loadWeather { _ in kit.weatherCity = "Oslo"; throw ModelTestError() }
        XCTAssertEqual(kit.weatherText, "Choose a city")
    }
}
