import XCTest
import SwiftUI
import AppKit
import EventKit
@testable import DockGrove

final class WidgetsUntitledReminder: EKReminder {
    override var title: String! { get { nil } set {} }
}

@MainActor final class WidgetsCoverageUtilityTests: XCTestCase {
    var defaults: UserDefaults!
    var utility: Utilities!
    var log: WidgetEffectLog!
    var folder: URL!

    override func setUp() async throws {
        defaults = widgetDefaults()
        utility = Utilities(store: defaults)
        widgetsIsolate(utility)
        log = WidgetEffectLog()
        folder = try widgetsTempDir("WidgetsUtility")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tool.app"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: folder.appendingPathComponent("note.txt"))
        utility.folder = folder
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    func view(_ kind: ToolKind, setup: Bool = true) -> WidgetHost {
        WidgetHost(UtilityView(kind: kind, utility: utility).environment(\.widgetEffects, log.handler).environment(\.connectionSetupAllowed, setup))
    }

    func testBookmarksAddValidateAndRemove() {
        let host = view(.bookmarks)
        host.press("Add bookmark")
        XCTAssertTrue(utility.bookmarks.isEmpty)
        host.type("Example", field: 0); host.type("ftp://nope", field: 1)
        host.press("Add bookmark")
        XCTAssertNotNil(utility.status)
        XCTAssertTrue(host.has(utility.status!))
        host.type("example.com", field: 1)
        host.press("Add bookmark")
        XCTAssertEqual(utility.bookmarks.map(\.title), ["Example"])
        utility.bookmarks.append(Bookmark(title: "Broken", address: "not a url"))
        host.pump()
        XCTAssertTrue(host.has("Example"))
        host.press("Remove", index: 1)
        host.press("Remove")
        XCTAssertTrue(utility.bookmarks.isEmpty)
    }

    func testFoldersNavigateOpenRevealAndChoose() throws {
        let host = view(.folders)
        XCTAssertEqual(Set(utility.folderItems.map(\.lastPathComponent)), ["Nested", "Tool.app", "note.txt"])
        host.press("note.txt")
        XCTAssertEqual(log.names.last, "open:" + folder.appendingPathComponent("note.txt").absoluteString)
        host.press("Tool.app")
        XCTAssertTrue(log.names.last?.hasSuffix("Tool.app/") == true)
        host.contextPick("Show in Finder", on: "note.txt")
        XCTAssertTrue(log.names.contains("reveal:" + folder.appendingPathComponent("note.txt").path))
        host.press("Nested")
        XCTAssertEqual(utility.folder.lastPathComponent, "Nested")
        host.press("Up")
        XCTAssertEqual(utility.folder.standardizedFileURL.path, folder.standardizedFileURL.path)
        host.press("Newest")
        XCTAssertEqual(utility.folderSort, "Newest")
        host.press("Choose…"); host.press("Downloads"); host.press("Refresh")
        XCTAssertTrue(log.names.contains("chooseFolder"))
        XCTAssertTrue(log.names.contains { $0.hasPrefix("browse:") && $0.hasSuffix("/Downloads") })
    }

    func testStopwatchStartLapPauseReset() {
        let host = view(.stopwatch)
        host.press("Start")
        XCTAssertNotNil(utility.stopwatchStart)
        host.press("Lap"); host.press("Lap")
        XCTAssertEqual(utility.laps.count, 2)
        XCTAssertTrue(host.has("Lap 2"))
        host.press("Pause")
        XCTAssertNil(utility.stopwatchStart)
        host.press("Reset")
        XCTAssertTrue(utility.laps.isEmpty)
    }

    func testWaterDrinkAndReminder() {
        utility.waterDue = true
        let host = view(.water)
        XCTAssertTrue(host.has("Time for a water break"))
        host.press("Drank a glass"); host.press("Drank a glass"); host.press("−1")
        XCTAssertEqual(utility.water, 1)
        XCTAssertFalse(utility.waterDue)
    }

    func testHabitsAddToggleRemove() {
        let host = view(.habits)
        host.press("Add")
        XCTAssertTrue(utility.habits.isEmpty)
        host.type("Stretch"); host.press("Add")
        XCTAssertEqual(utility.habits.map(\.title), ["Stretch"])
        host.press("Circle")
        XCTAssertEqual(utility.habits[0].completedDays.count, 1)
        XCTAssertTrue(host.has("1 recorded days"))
        host.press("Remove")
        XCTAssertTrue(utility.habits.isEmpty)
    }

    func testProgressClocksAndDefault() {
        let progress = view(.progress)
        XCTAssertTrue(progress.has("Day") && progress.has("Year"))
        let clocks = view(.clocks)
        XCTAssertTrue(clocks.has("America/New York"))
        clocks.press("Add clock")
        XCTAssertTrue(utility.zones.contains("America/Los_Angeles"))
        clocks.press("Remove")
        XCTAssertFalse(utility.zones.contains("America/New_York"))
        clocks.choose("Europe/Paris", in: "America/Los_Angeles")
        clocks.press("Add clock")
        XCTAssertTrue(utility.zones.contains("Europe/Paris"))
        utility.status = "Status line"
        let empty = view(.pet)
        XCTAssertTrue(empty.has("Status line"))
    }

    func testConverterCategorySwapAndInvalid() {
        let host = view(.converter)
        XCTAssertTrue(host.has("3.280839895 ft"))
        host.press("Left And Right Arrows")
        host.choose("Temperature", in: "Length")
        XCTAssertTrue(host.contains("°F"), "\(host.labels())")
        host.type("warm")
        XCTAssertTrue(host.has("Enter a valid number."))
    }

    func testCaptureColorsAndControls() {
        let capture = view(.capture)
        capture.press("Capture selection to clipboard")
        log.openResult = false
        capture.press("Open macOS Screenshot toolbar")
        XCTAssertEqual(utility.status, "This system app is unavailable on this Mac.")
        log.openResult = true
        utility.status = nil
        capture.press("Open macOS Screenshot toolbar")
        XCTAssertNil(utility.status)
        let colors = view(.colors)
        colors.press("Pick from screen"); colors.press("Copy hex")
        let controls = view(.controls)
        for title in ["Mission Control", "Emoji & Symbols", "Sound settings", "Display settings", "Wi-Fi settings", "Bluetooth settings", "Desktop & Dock settings", "Open Trash"] { controls.press(title) }
        XCTAssertTrue(log.names.contains("screenshot"))
        XCTAssertTrue(log.names.contains("pickColor"))
        XCTAssertTrue(log.names.contains("copy:#FFFFFF"))
        XCTAssertTrue(log.names.contains("palette"))
        XCTAssertTrue(log.names.contains("open:x-apple.systempreferences:com.apple.BluetoothSettings"))
        XCTAssertEqual(log.names.filter { $0.hasPrefix("open:") }.count, 9)
    }

    func testRemindersCompleteRefreshAndSettingsLink() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Call"
        let untitled = EKReminder(eventStore: EKEventStore())
        object_setClass(untitled, WidgetsUntitledReminder.self) // a reminder whose title reads nil
        utility.reminders = [reminder, untitled]
        let host = view(.reminders)
        XCTAssertTrue(host.has("Call"), "\(host.labels())")
        host.press("Mark complete in Apple Reminders")
        host.press("Allow / refresh Reminders access")
        XCTAssertEqual(log.names, ["completeReminder", "loadReminders"])
        let locked = view(.reminders, setup: false)
        XCTAssertFalse(locked.has("Allow / refresh Reminders access"))
    }

    func testLoginAndWorkspaceSettings() {
        let model = DockModel(defaults: defaults)
        widgetsIsolate(model)
        let kit = model.toolkit
        utility = kit.utilities
        kit.utilities.status = "Login note"
        kit.profiles = [DockProfile(name: "Desk", apps: [], widgets: ["focus"], accent: "White", size: 48)]
        let host = WidgetHost(WorkspaceSettings(model: model, kit: kit).environment(\.widgetEffects, log.handler), width: 600, height: 900)
        XCTAssertTrue(host.has("Login note"))
        host.press("Open DockGrove at login")
        XCTAssertTrue(log.names.contains { $0.hasPrefix("login:") })
        host.press("Export layouts…"); host.press("Import layouts…")
        XCTAssertTrue(log.names.contains("export") && log.names.contains("import"))
        host.type("Studio")
        host.press("Save layout")
        XCTAssertEqual(kit.profiles.map(\.name), ["Desk", "Studio"])
        host.press("Apply")
        XCTAssertEqual(kit.enabled, ["focus"])
        host.press("Remove")
        XCTAssertEqual(kit.profiles.map(\.name), ["Studio"])
        if let screen = NSScreen.screens.first {
            host.press("Display: " + screen.localizedName)
            host.press(screen.localizedName, index: 0)
            XCTAssertEqual(kit.screenIndex, 0)
            XCTAssertEqual(model.screenID, DockModel.displayID(screen))
        }
    }
}
