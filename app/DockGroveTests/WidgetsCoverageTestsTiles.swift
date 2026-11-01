import XCTest
import SwiftUI
import AppKit
import EventKit
@testable import DockGrove

/// Hosts `ToolTile.contents` the way the notch and settings do, re-rendering when the models change.
struct WidgetsContentsHost: View {
    let kind: ToolKind
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    var body: some View { ToolTile(kind: kind, model: model, kit: kit).contents }
}

@MainActor final class WidgetsCoverageTilesTests: XCTestCase {
    var defaults: UserDefaults!
    var model: DockModel!
    var kit: Toolkit { model.toolkit }
    var log: WidgetEffectLog!
    var directory: URL!
    let finder = "/System/Library/CoreServices/Finder.app"
    let calculator = "/System/Applications/Calculator.app"

    override func setUp() async throws {
        defaults = widgetDefaults()
        defaults.set([String](), forKey: "apps")
        model = DockModel(defaults: defaults)
        widgetsIsolate(model)
        log = WidgetEffectLog()
        directory = try widgetsTempDir("WidgetsTiles")
        model.toolkit.utilities.folder = directory
    }
    override func tearDown() async throws {
        kit.monitor.stop(); kit.claudeCodeUsage.stop(); kit.geminiUsage.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func weather() -> WeatherSnapshot {
        let t = Measurement(value: 21, unit: UnitTemperature.celsius)
        let mark = directory.appendingPathComponent("mark.png")
        try? widgetsPNG().write(to: mark)
        return WeatherSnapshot(city: "Lisbon", temperature: t, apparentTemperature: t, condition: "Sunny", symbolName: "sun.max.fill", date: Date(), attributionURL: URL(string: "https://weatherkit.apple.com/legal")!, lightMarkURL: mark, darkMarkURL: mark)
    }
    func populate() {
        kit.tasks = [TaskItem(title: "Write tests"), TaskItem(title: "Ship", done: true)]
        kit.utilities.habits = [Habit(title: "Walk", completedDays: [Habit.day(Date())])]
        kit.note = "Remember the milk"
        kit.clipboardEnabled = true; kit.clipboard = ["copied text"]
    }
    func tile(_ kind: ToolKind) -> WidgetHost {
        WidgetHost(ToolTile(kind: kind, model: model, kit: kit).environment(\.widgetEffects, log.handler), width: 300, height: 200)
    }
    func contents(_ kind: ToolKind, height: CGFloat = 760) -> WidgetHost {
        WidgetHost(WidgetsContentsHost(kind: kind, model: model, kit: kit).environment(\.widgetEffects, log.handler), width: 380, height: height)
    }

    // MARK: Tile faces, captions, popover and context menu
    func testPlainTilesShowCaptionsForEveryKind() {
        populate()
        kit.richWidgets = false
        for kind in ToolKind.allCases {
            let host = tile(kind)
            XCTAssertFalse(host.find(kind.title).isEmpty, "\(kind): \(host.labels())")
        }
        kit.utilities.waterDue = true; kit.focusFinished = true
        kit.weatherSnapshot = weather(); kit.weatherText = "21°"
        for kind in [ToolKind.water, .focus, .weather] { _ = tile(kind) }
        let search = tile(.search)
        search.press(ToolKind.search.title)
        search.pump(0.3)
        search.press(ToolKind.search.title)
        let weatherTile = tile(.weather)
        weatherTile.press(ToolKind.weather.title)
        weatherTile.pump(0.3)
        weatherTile.press(ToolKind.weather.title)
    }

    func testShapedAndRichTilesOpenAndMenu() {
        populate()
        kit.richWidgets = true
        kit.enabled = ["focus", "tasks", "notes"]
        let rich = tile(.tasks)
        let open = rich.elements().filter { WidgetHost.role($0) == "AXButton" }
        XCTAssertFalse(open.isEmpty)
        if let first = open.first { _ = WidgetHost.axBool(first, "accessibilityPerformPress"); rich.pump(0.3); _ = WidgetHost.axBool(first, "accessibilityPerformPress"); rich.pump() }
        let richSearch = tile(.search)
        if let first = richSearch.elements().first(where: { WidgetHost.role($0) == "AXButton" }) { _ = WidgetHost.axBool(first, "accessibilityPerformPress"); richSearch.pump(0.2) }

        kit.edge = "Top"
        for (kind, shape) in [(ToolKind.tasks, "circle"), (.search, "pill"), (.weather, "square"), (.github, "square"), (.water, "circle")] {
            kit.widgetShapes[kind.rawValue] = shape
            kit.weatherSnapshot = kind == .weather ? weather() : nil
            let host = tile(kind)
            let label = host.label(prefix: kind.title + ": ")
            XCTAssertNotNil(label, "\(kind): \(host.labels())")
            guard let label else { continue }
            host.press(label); host.pump(0.2); host.press(label)
        }
        kit.widgetShapes["tasks"] = "circle"
        let host = tile(.tasks)
        let label = ToolKind.tasks.title + ": " + "1 to do"
        host.contextPick("Move later", on: label)
        XCTAssertEqual(kit.enabled, ["focus", "notes", "tasks"])
        host.contextPick("Move earlier", on: label)
        XCTAssertEqual(kit.enabled, ["focus", "tasks", "notes"])
        host.contextPick("Square", on: label)
        XCTAssertEqual(kit.widgetShapes["tasks"], "square")
        host.contextPick("Remove widget", on: label)
        XCTAssertFalse(kit.enabled.contains("tasks"))
    }

    // MARK: Popover contents per kind
    func testContentsRenderEveryKind() {
        populate()
        kit.weatherSnapshot = weather()
        for kind in ToolKind.allCases where ![.system, .windows, .audio, .spacer, .separator].contains(kind) {
            let host = contents(kind)
            XCTAssertGreaterThan(host.elements().count, 1, "\(kind)")
        }
        // Views with live system readers render once, without interaction.
        for kind in [ToolKind.system, .audio, .windows, .spacer, .separator] { _ = contents(kind) }
    }

    func testSearchContents() {
        kit.applications = [DockApp(url: URL(fileURLWithPath: finder)), DockApp(url: URL(fileURLWithPath: calculator))]
        model.apps = [DockApp(url: URL(fileURLWithPath: finder))]
        let host = contents(.search)
        let calc = kit.applications[1].name
        host.press(calc)
        XCTAssertEqual(log.names, ["launch:" + calculator])
        host.press("Pin app", index: 1)
        kit.query = "Calc"; host.pump()
        XCTAssertTrue(host.has(calc))
    }

    func testTasksFocusNotesContents() {
        populate()
        let tasks = contents(.tasks)
        tasks.submit("Plan")
        kit.draftTask = "Review"; tasks.pump()
        tasks.press("Add")
        XCTAssertEqual(kit.tasks.map(\.title), ["Write tests", "Ship", "Plan", "Review"])
        tasks.press("Mark done")
        XCTAssertTrue(kit.tasks[0].done)
        tasks.press("Remove task")
        tasks.press("Clear completed")
        XCTAssertTrue(kit.tasks.allSatisfy { !$0.done })
        kit.tasks = []; tasks.pump()
        XCTAssertTrue(tasks.has("A little space for what comes next."))

        kit.focusFinished = true
        let focus = contents(.focus)
        XCTAssertTrue(focus.has("Session complete"))
        for minutes in [5, 15, 25, 50] { focus.press("\(minutes)m") }
        XCTAssertEqual(kit.seconds, 50 * 60)
        focus.press("Start"); XCTAssertNotNil(kit.focusEnd)
        XCTAssertTrue(focus.has("Pause"), "\(focus.labels())")
        focus.press("Pause"); XCTAssertNil(kit.focusEnd)
        focus.press("Reset"); XCTAssertEqual(kit.seconds, 25 * 60)
        _ = contents(.notes)
        let reminders = contents(.reminders)
        reminders.press("Connection settings")
        XCTAssertEqual(model.connectionSettingsKind, .reminders)
    }

    func testFilesContents() throws {
        let file = directory.appendingPathComponent("report.txt"); try Data("x".utf8).write(to: file)
        let dropped = directory.appendingPathComponent("dropped.txt"); try Data("y".utf8).write(to: dropped)
        kit.files = [file.path]
        let host = contents(.files)
        host.press("report.txt")
        host.press("Reveal in Finder")
        host.press("Add files…"); host.press("Downloads")
        if let point = host.center(of: "Drop files here to keep shortcuts handy.") { host.drop([dropped], at: point) }
        XCTAssertTrue(widgetsWait { kit.files.contains(dropped.path) })
        host.press("Remove shortcut")
        XCTAssertFalse(kit.files.contains(file.path))
        XCTAssertEqual(Array(log.names.prefix(4)), ["open:" + file.absoluteString, "reveal:" + file.path, "addFiles", "open:" + FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").absoluteString])
    }

    func testClipboardAndWeatherContents() {
        populate()
        let clip = contents(.clipboard)
        clip.press("copied text")
        clip.press("Clear history")
        XCTAssertTrue(kit.clipboard.isEmpty)
        XCTAssertEqual(log.names, ["copy:copied text"])
        let weather = contents(.weather)
        weather.submit("Porto")
        weather.press("Get weather")
        XCTAssertEqual(Array(log.names.suffix(2)), ["fetchWeather", "fetchWeather"])
        kit.weatherLoading = true; weather.pump()
        XCTAssertTrue(weather.has("Loading…"))
    }

    // MARK: Rich cards
    func card(_ kind: ToolKind, scheme: ColorScheme = .light) -> WidgetHost {
        WidgetHost(RichWidgetCard(kind: kind, model: model, kit: kit, open: {}).environment(\.widgetEffects, log.handler), width: 236, height: 80, scheme: scheme)
    }
    func event(_ title: String, allDay: Bool) -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = title; event.startDate = Date().addingTimeInterval(3600); event.endDate = Date().addingTimeInterval(7200); event.isAllDay = allDay
        return event
    }
    func testRichCardsEveryKindEmpty() {
        kit.clipboardEnabled = false
        for kind in ToolKind.allCases { _ = card(kind) }
        for kind in ToolKind.allCases { _ = card(kind, scheme: .dark) }
    }
    func testRichCardsPopulatedAndControls() throws {
        populate()
        kit.focusFinished = true
        kit.utilities.waterDue = true
        kit.weatherSnapshot = weather(); kit.weatherText = "21°"
        kit.monitor.available = true; kit.monitor.cpu = 42; kit.monitor.history = [1, 5, 3]
        let calendarEvents = [event("Standup", allDay: false)]
        kit.calendar.events = calendarEvents; kit.calendar.connected = true
        kit.googleCalendar.events = [event("Holiday", allDay: true)]
        kit.groups.groups = [AppGroup(name: "Work", paths: [finder])]
        let snapshot = try widgetsGitHubSnapshot(run: true, warning: nil)
        kit.github.snapshot = snapshot
        kit.claudeCodeUsage.report = LocalAIReport(provider: "claude", observed: Date(), windows: [LocalAIWindow(name: "5h", used: 25, resets: Date().addingTimeInterval(600))], models: [], sessionCost: nil)
        kit.geminiUsage.report = LocalAIReport(provider: "gemini", observed: Date().addingTimeInterval(-4000), windows: [], models: [LocalAIModel(name: "g", total: 1200, input: 1000, output: 200, cached: 0, requests: 2)], sessionCost: nil)
        kit.openaiUsage.snapshot = AIUsageSnapshot(totals: [12345], start: Date(), end: Date())
        kit.currency.report = ExchangeRate(date: "2026-10-30", base: "USD", quote: "EUR", rate: 0.9)
        kit.voiceMemo.recording = true; kit.voiceMemo.elapsed = 75
        kit.spotify.track = TrackSnapshot(title: "Song", artist: "", playing: true)
        kit.spotify.connected = true
        kit.spotify.artwork = NSImage(data: widgetsPNG())
        kit.appleMusic.track = TrackSnapshot(title: "Tune", artist: "", playing: false)
        kit.appleMusic.connected = true
        for kind in ToolKind.allCases { _ = card(kind) }
        // Claude report without an active window, and fresh Gemini report.
        kit.claudeCodeUsage.report = LocalAIReport(provider: "claude", observed: Date().addingTimeInterval(-4000), windows: [], models: [], sessionCost: nil)
        kit.geminiUsage.report = LocalAIReport(provider: "gemini", observed: Date(), windows: [], models: [], sessionCost: nil)
        _ = card(.claudeCodeUsage); _ = card(.geminiUsage)
        kit.calendar.events = []; _ = card(.calendar)
        kit.calendar.connected = false; _ = card(.calendar)
        kit.weatherSnapshot = nil; kit.weatherCity = "Oslo"; _ = card(.weather)
        kit.weatherCity = ""; _ = card(.weather)
        kit.appleMusic.track = TrackSnapshot(title: "Tune", artist: "Band", playing: true); _ = card(.appleMusic)
        kit.spotify.track = TrackSnapshot(title: "Song", artist: "", playing: false); _ = card(.music)
        model.albumColors = false; _ = card(.spotify)
        kit.groups.groups = []; model.apps = [DockApp(url: URL(fileURLWithPath: finder))]; _ = card(.appGroups)

        kit.spotify.connected = true; kit.appleMusic.connected = true
        kit.appleMusic.track = TrackSnapshot(title: "Tune", artist: "Band", playing: true)
        let music = card(.spotify)
        music.press("Play music")
        let apple = card(.appleMusic)
        apple.press("Pause music")
        XCTAssertEqual(log.names, ["music:playpause", "music:playpause"])
        kit.focusEnd = nil
        let focus = card(.focus)
        focus.press("Start focus"); XCTAssertNotNil(kit.focusEnd)
        focus.press("Pause focus"); XCTAssertNil(kit.focusEnd)
        let stopwatch = card(.stopwatch)
        stopwatch.press("Start or pause stopwatch"); XCTAssertNotNil(kit.utilities.stopwatchStart)
        stopwatch.press("Start or pause stopwatch"); XCTAssertNil(kit.utilities.stopwatchStart)
        let water = card(.water)
        water.press("Log a glass of water"); XCTAssertEqual(kit.utilities.water, 1)
    }
}
