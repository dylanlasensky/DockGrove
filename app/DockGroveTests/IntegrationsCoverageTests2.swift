import XCTest
import SwiftUI
import AppKit
import EventKit
import CoreAudio
import CoreLocation
import MapKit
import Contacts
@testable import DockGrove

// MARK: - EventKit fakes

/// Unsaved calendar whose account source is a fixture; EventKit leaves `source` nil until saved.
final class IntegrationsFixtureCalendar: EKCalendar {
    override var source: EKSource! { get { IntegrationsFixtureSource() } set {} }
}
final class IntegrationsFixtureSource: EKSource {
    override var title: String { "Fixture account" }
}
/// EventKit returns "" for a cleared title; these report nil like an item synced without one.
final class IntegrationsUntitledEvent: EKEvent {
    override var title: String! { get { nil } set {} }
}
final class IntegrationsUntitledReminder: EKReminder {
    override var title: String! { get { nil } set {} }
}

/// Event and reminder access backed by unsaved fixture objects; no real store is read or written.
final class IntegrationsEventAccess: EventStoreAccess {
    let store = EKEventStore()
    var allowEvents: Result<Bool, Error> = .success(true)
    var allowReminders: Result<Bool, Error> = .success(true)
    var delay: UInt64 = 0
    var authorized = true
    var calendars: [EKCalendar] = []
    var events: [EKEvent] = []
    var reminders: [EKReminder]?
    var saveError: Error?
    var saved: [EKReminder] = []
    var queriedCalendars: [[EKCalendar]] = []

    func calendar(_ title: String) -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: store)
        object_setClass(calendar, IntegrationsFixtureCalendar.self)
        calendar.title = title
        return calendar
    }
    func event(_ title: String?, start: Date, allDay: Bool = false, url: URL? = nil, calendar: EKCalendar) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title; event.startDate = start; event.endDate = start.addingTimeInterval(3600); event.isAllDay = allDay; event.url = url; event.calendar = calendar
        if title == nil { object_setClass(event, IntegrationsUntitledEvent.self) }
        return event
    }
    func reminder(_ title: String?) -> EKReminder {
        let reminder = EKReminder(eventStore: store); reminder.title = title
        if title == nil { object_setClass(reminder, IntegrationsUntitledReminder.self) }
        return reminder
    }

    func requestEventAccess() async throws -> Bool { if delay > 0 { try? await Task.sleep(nanoseconds: delay) }; return try allowEvents.get() }
    func requestReminderAccess() async throws -> Bool { try allowReminders.get() }
    func eventsAuthorized() -> Bool { authorized }
    func eventCalendars() -> [EKCalendar] { calendars }
    func events(from start: Date, to end: Date, in calendars: [EKCalendar]) -> [EKEvent] { queriedCalendars.append(calendars); return events }
    func incompleteReminders(_ completion: @escaping ([EKReminder]?) -> Void) { let items = reminders; DispatchQueue.global().async { completion(items) } }
    func saveReminder(_ reminder: EKReminder) throws { if let saveError { throw saveError }; saved.append(reminder) }
}

// MARK: - Calendar

@MainActor final class IntegrationsCalendarTests: XCTestCase {
    private func widget(google: Bool = false) -> (CalendarWidget, IntegrationsEventAccess, () -> [URL]) {
        let access = IntegrationsEventAccess()
        let widget = CalendarWidget(store: IntegrationsUI.defaults(self), google: google, access: access)
        var opened: [URL] = []
        widget.open = { opened.append($0) }
        return (widget, access, { opened })
    }

    func testConnectOutcomes() {
        let (widget, access, _) = widget()
        access.allowEvents = .success(false)
        widget.connect(); XCTAssertTrue(widget.loading)
        widget.connect() // Ignored while a request is pending.
        XCTAssertTrue(IntegrationsUI.wait { !widget.loading })
        XCTAssertFalse(widget.connected); XCTAssertTrue(widget.status.hasPrefix("Calendar access was denied"))
        access.allowEvents = .failure(CocoaError(.featureUnsupported))
        widget.connect(); XCTAssertTrue(IntegrationsUI.wait { !widget.loading })
        XCTAssertEqual(widget.status, "Calendar access failed. Check macOS permissions and retry.")
        access.allowEvents = .success(true)
        widget.connect(); XCTAssertTrue(IntegrationsUI.wait { !widget.loading })
        XCTAssertTrue(widget.connected)
        XCTAssertEqual(widget.status, "No calendars configured. Add an account in macOS Internet Accounts.")

        // Responses that arrive after Disconnect are ignored, whether granted or failed.
        for outcome in [Result<Bool, Error>.success(true), .failure(CocoaError(.featureUnsupported))] {
            access.allowEvents = outcome; access.delay = 150_000_000
            widget.connect(); widget.disconnect()
            IntegrationsUI.spin(0.3)
            XCTAssertFalse(widget.connected); XCTAssertEqual(widget.status, "Disconnected.")
        }
    }

    func testRefreshSelectionAndEvents() {
        let (widget, access, _) = widget()
        widget.refreshIfAuthorized(); XCTAssertTrue(widget.calendars.isEmpty)
        let work = access.calendar("work"), home = access.calendar("Home")
        access.calendars = [work, home]
        widget.connected = true
        access.authorized = false
        widget.refreshIfAuthorized()
        XCTAssertFalse(widget.connected); XCTAssertEqual(widget.status, "Calendar permission was removed. Connect again when ready.")
        access.authorized = true; widget.connected = true
        widget.refreshIfAuthorized()
        XCTAssertEqual(widget.calendars.map(\.title), ["Home", "work"])
        XCTAssertEqual(widget.status, "No events in the next seven days.")
        let now = Date()
        access.events = [access.event("Later", start: now.addingTimeInterval(7200), calendar: work), access.event(nil, start: now.addingTimeInterval(60), calendar: home)]
        widget.refreshIfAuthorized()
        XCTAssertEqual(widget.events.map { $0.title ?? "" }, ["", "Later"])
        XCTAssertEqual(widget.status, "Next seven days · Syncs through macOS Calendar")
        widget.select(work, enabled: true)
        XCTAssertEqual(access.queriedCalendars.last?.map(\.title), ["work"])
        widget.select(work, enabled: false)
        widget.selected = ["missing"]
        XCTAssertTrue(widget.events.isEmpty); XCTAssertEqual(widget.status, "Selected calendars are unavailable. Select another calendar.")

        let (google, googleAccess, _) = self.widget(google: true)
        googleAccess.calendars = [googleAccess.calendar("Personal")]
        google.connected = true
        google.refreshIfAuthorized()
        XCTAssertTrue(google.status.hasPrefix("Select the calendars from your Google account"))
    }

    func testStoreChangesAndTimerRefreshOnlyWhileConnected() {
        let (widget, access, _) = widget()
        access.calendars = [access.calendar("Home")]
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: widget.eventStore)
        widget.timer?.fire()
        IntegrationsUI.spin(0.05)
        XCTAssertTrue(widget.calendars.isEmpty)
        widget.connected = true
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: widget.eventStore)
        XCTAssertTrue(IntegrationsUI.wait { widget.calendars.count == 1 })
        widget.calendars = []
        widget.timer?.fire()
        XCTAssertTrue(IntegrationsUI.wait { widget.calendars.count == 1 })
    }

    func testSystemEventStoreAdapterReadsNothingReal() {
        let store = EKEventStore()
        _ = store.eventsAuthorized()
        let calendar = EKCalendar(for: .event, eventStore: store)
        XCTAssertTrue(store.events(from: Date(), to: Date().addingTimeInterval(60), in: [calendar]).isEmpty)
        // The default opener reports a missing file without showing anything.
        CalendarWidget(store: IntegrationsUI.defaults(self), access: IntegrationsEventAccess()).open(URL(fileURLWithPath: "/nonexistent-dockgrove-\(UUID().uuidString)"))
    }

    func testAgendaViewStatesAndActions() {
        for google in [false, true] {
            let (widget, access, opened) = widget(google: google)
            for setup in [true, false] { IntegrationsUI.render(CalendarAgendaView(calendar: widget), setup: setup) }
            let work = access.calendar("Work")
            access.calendars = [work]
            let now = Date()
            access.events = [access.event("Standup", start: now.addingTimeInterval(60), url: URL(string: "https://example.com/meet"), calendar: work),
                             access.event(nil, start: now.addingTimeInterval(120), allDay: true, url: URL(string: "ftp://example.com"), calendar: work),
                             access.event("No link", start: now.addingTimeInterval(180), calendar: work),
                             access.event("Relative link", start: now.addingTimeInterval(240), url: URL(string: "meeting-notes"), calendar: work)]
            widget.connected = true
            widget.selected = [work.calendarIdentifier]
            widget.refreshIfAuthorized()
            for setup in [true, false] { IntegrationsUI.render(CalendarAgendaView(calendar: widget), setup: setup, dark: setup) }

            let view = CalendarAgendaView(calendar: widget, setupAllowedOverride: true)
            IntegrationsUI.press(IntegrationsUI.body(view), "Open Internet Accounts")
            IntegrationsUI.press(IntegrationsUI.body(view), "Open Calendar")
            XCTAssertEqual(opened().count, 2)
            XCTAssertEqual(opened().first?.scheme, "x-apple.systempreferences")
            XCTAssertEqual(opened().last?.lastPathComponent, "Calendar.app")
            for toggle in IntegrationsUI.values(ForEach<[EKCalendar], String, Toggle<Text>>.self, in: IntegrationsUI.body(view)) {
                for item in toggle.data {
                    for binding in IntegrationsUI.toggles(in: toggle.content(item)) {
                        XCTAssertTrue(binding.isOn)
                        binding.isOn = false
                        XCTAssertFalse(widget.selected.contains(item.calendarIdentifier))
                        binding.isOn = true
                    }
                }
            }
            XCTAssertEqual(widget.selected, [work.calendarIdentifier])
            let access2 = IntegrationsUI.toggles(in: IntegrationsUI.body(view))
            XCTAssertEqual(access2.count, 1)
            guard let allow = access2.first else { return }
            allow.isOn = false
            XCTAssertFalse(widget.connected)
            allow.isOn = true
            XCTAssertTrue(IntegrationsUI.wait { widget.connected && !widget.loading })
            IntegrationsUI.press(IntegrationsUI.body(view), "Refresh")
            XCTAssertTrue(IntegrationsUI.wait { !widget.loading })
        }
    }
}

// MARK: - System monitor and audio

/// Records requested audio changes; nothing reaches Core Audio.
final class IntegrationsAudio: AudioHardware {
    var ids: [AudioDeviceID]? = [1, 2, 3]
    var names: [AudioDeviceID: String] = [1: "Speakers", 3: "Headphones"]
    var outputs: Set<AudioDeviceID> = [1, 2]
    var current: AudioDeviceID? = 1
    var reading: (value: Float, settable: Bool) = (0.4, true)
    var accept = true
    var volumes: [Float] = [], selections: [AudioDeviceID] = []
    func devices() -> [AudioDeviceID]? { ids }
    func hasOutput(_ device: AudioDeviceID) -> Bool { outputs.contains(device) }
    func name(_ device: AudioDeviceID) -> String? { names[device] }
    func defaultOutput() -> AudioDeviceID? { current }
    func volume(_ device: AudioDeviceID) -> (value: Float, settable: Bool) { reading }
    func setVolume(_ value: Float, device: AudioDeviceID) -> Bool { volumes.append(value); return accept }
    func setDefaultOutput(_ device: AudioDeviceID) -> Bool { selections.append(device); if accept { current = device }; return accept }
}

@MainActor final class IntegrationsSystemTests: XCTestCase {
    func testSamplingAndTimer() {
        let monitor = SystemMonitor()
        monitor.sample()
        Thread.sleep(forTimeInterval: 0.06)
        monitor.sample()
        XCTAssertTrue((0...100).contains(monitor.memory))
        monitor.start()
        let timer = monitor.timer
        XCTAssertNotNil(timer)
        monitor.start(); XCTAssertTrue(monitor.timer === timer)
        Thread.sleep(forTimeInterval: 0.03)
        monitor.timer?.fire()
        IntegrationsUI.spin(0.05)
        monitor.stop(); XCTAssertNil(monitor.timer)
        XCTAssertEqual(SystemMonitor.speed(2048), "2 KB/s")
        XCTAssertEqual(SystemMonitor.speed(-5), "Zero KB/s")
    }

    func testAudioControlWithFakeHardware() {
        let hardware = IntegrationsAudio()
        let audio = AudioControl(hardware: hardware)
        audio.refresh()
        XCTAssertEqual(audio.outputs.map(\.name), ["Speakers"])
        XCTAssertEqual(audio.selected, 1); XCTAssertEqual(audio.volume, 0.4); XCTAssertEqual(audio.status, "System output volume")
        audio.setVolume(1.5); XCTAssertEqual(hardware.volumes, [1]); XCTAssertEqual(audio.volume, 1)
        hardware.accept = false
        audio.setVolume(0.2); XCTAssertEqual(audio.status, "The output refused the volume change.")
        audio.select(9); XCTAssertTrue(hardware.selections.isEmpty)
        audio.select(1); XCTAssertEqual(audio.status, "Could not change the audio output.")
        hardware.accept = true; hardware.reading = (0.1, false)
        audio.select(1); XCTAssertEqual(audio.status, "This output uses its own volume controls.")
        audio.setVolume(0.9); XCTAssertEqual(hardware.volumes.count, 2)
        hardware.current = nil
        audio.status = ""; audio.refresh(); XCTAssertEqual(audio.status, "")
        hardware.ids = nil
        audio.refresh(); XCTAssertEqual(audio.status, "Audio outputs unavailable.")
    }

    func testCoreAudioAdapterReadsAndRejectsUnknownObjects() {
        let hardware = CoreAudioHardware()
        for id in hardware.devices() ?? [] { _ = hardware.hasOutput(id); _ = hardware.name(id) }
        if let output = hardware.defaultOutput() { _ = hardware.volume(output) }
        let unknown = AudioDeviceID(kAudioObjectUnknown)
        XCTAssertFalse(hardware.hasOutput(unknown))
        XCTAssertNil(hardware.name(unknown))
        XCTAssertFalse(hardware.volume(unknown).settable)
        // Writes only target the unknown object, which Core Audio refuses.
        XCTAssertFalse(hardware.setVolume(0.5, device: unknown))
        let detached = CoreAudioHardware(system: unknown)
        XCTAssertNil(detached.devices())
        XCTAssertNil(detached.defaultOutput())
        XCTAssertFalse(detached.setDefaultOutput(unknown))
    }

    func testViews() {
        let monitor = SystemMonitor()
        let kit = Toolkit(store: IntegrationsUI.defaults(self))
        IntegrationsUI.render(SystemDetailView(monitor: monitor, kit: kit))
        monitor.available = true; monitor.history = [10, 50, 30]
        IntegrationsUI.render(SystemDetailView(monitor: monitor, kit: kit), dark: true)
        monitor.stop()
        let detail = SystemDetailView(monitor: monitor, kit: kit)
        IntegrationsUI.appear(IntegrationsUI.body(detail))
        XCTAssertNotNil(monitor.timer)
        monitor.stop()

        let hardware = IntegrationsAudio()
        hardware.names[2] = "Display"
        let audio = AudioControl(hardware: hardware)
        let view = AudioControlView(audio: audio)
        IntegrationsUI.render(view)
        XCTAssertEqual(audio.outputs.count, 2)
        let picker = IntegrationsUI.values(Binding<AudioDeviceID>.self, in: IntegrationsUI.body(view))
        XCTAssertEqual(picker.first?.wrappedValue, 1)
        picker.first?.wrappedValue = 2
        XCTAssertEqual(hardware.selections, [2])
        let slider = IntegrationsUI.values(Binding<Double>.self, in: IntegrationsUI.body(view))
        XCTAssertEqual(slider.first?.wrappedValue ?? 0, 0.4, accuracy: 0.001)
        slider.first?.wrappedValue = 0.75
        XCTAssertEqual(hardware.volumes, [0.75])
        audio.outputs = []
        IntegrationsUI.press(IntegrationsUI.body(view), "Refresh outputs")
        XCTAssertEqual(audio.outputs.count, 2)
        audio.outputs = []
        IntegrationsUI.appear(IntegrationsUI.body(view))
        XCTAssertEqual(audio.outputs.count, 2)
    }
}

// MARK: - Music players

@MainActor final class IntegrationsMusicTests: XCTestCase {
    private final class Script: @unchecked Sendable {
        var replies: [Result<Data, Error>] = []
        var sources: [String] = []
        func run(_ source: String, _ timeout: TimeInterval) throws -> Data {
            sources.append(source)
            return try replies.isEmpty ? Data("stopped\u{1e}Nothing playing\u{1e} ".utf8) : replies.removeFirst().get()
        }
    }

    private func player(_ bundleID: String, script: Script) -> MusicPlayer {
        let player = MusicPlayer(name: "Fixture", bundleID: bundleID)
        player.isRunning = { _ in true }
        player.locate = { _ in nil }
        player.launch = { _ in XCTFail("Unexpected launch") }
        player.runScript = { try script.run($0, $1) }
        player.fetchArtwork = { _ in throw URLError(.notConnectedToInternet) }
        addTeardownBlock { player.disconnect() }
        return player
    }

    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4)); image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    func testOpenPlayerLocatesAndLaunches() {
        let player = MusicPlayer(name: "Fixture", bundleID: "invalid.dockgrove.fixture")
        player.locate = { _ in nil }
        player.openPlayer(); XCTAssertEqual(player.status, "Fixture is not installed on this Mac.")
        var launched: [URL] = []
        player.locate = { URL(fileURLWithPath: "/Applications/\($0).app") }
        player.launch = { launched.append($0) }
        player.openPlayer(); XCTAssertEqual(launched.map(\.lastPathComponent), ["invalid.dockgrove.fixture.app"])
        // The real lookups and launcher fail quietly for apps that do not exist.
        let real = MusicPlayer(name: "Fixture", bundleID: "invalid.dockgrove.fixture")
        XCTAssertNil(real.locate("invalid.dockgrove.fixture"))
        XCTAssertFalse(real.isRunning("invalid.dockgrove.fixture"))
        real.launch(URL(fileURLWithPath: "/nonexistent-dockgrove.app"))
        IntegrationsUI.spin(0.3)
        XCTAssertEqual(String(decoding: try! MusicPlayer.osascript("return \"ok\"", timeout: 5), as: UTF8.self), "ok\n")
    }

    func testRefreshOutcomesAndArtwork() {
        let script = Script()
        let spotify = player("com.spotify.client", script: script)
        var artworkRequests: [URL] = []
        let image = png()
        spotify.fetchArtwork = { artworkRequests.append($0); return image }
        script.replies = [.success(Data("playing\u{1e}Song\u{1e}Artist\u{1e}https://i.scdn.co/image/abc".utf8))]
        spotify.refresh(command: .toggle)
        XCTAssertTrue(spotify.busy)
        spotify.refresh() // Ignored while busy.
        XCTAssertTrue(IntegrationsUI.wait { spotify.artwork != nil })
        XCTAssertTrue(script.sources[0].contains("playpause") && script.sources[0].contains("artwork url"))
        XCTAssertEqual(artworkRequests.map(\.host), ["i.scdn.co"])
        XCTAssertTrue(spotify.connected); XCTAssertEqual(spotify.status, "Connected to Fixture")
        script.replies = [.success(Data("playing\u{1e}Song\u{1e}Artist\u{1e}https://i.scdn.co/image/abc".utf8))]
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy })
        XCTAssertEqual(artworkRequests.count, 1, "Unchanged artwork is not fetched again")
        script.replies = [.success(Data("playing\u{1e}Other\u{1e}Artist\u{1e}https://[::1".utf8))]
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy }); IntegrationsUI.spin(0.05)
        XCTAssertNil(spotify.artwork)
        script.replies = [.success(Data("paused\u{1e}Song\u{1e}Artist\u{1e}https://i.scdn.co/image/def".utf8))]
        spotify.fetchArtwork = { _ in throw URLError(.timedOut) }
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy }); IntegrationsUI.spin(0.05)
        XCTAssertNil(spotify.artwork)
        script.replies = [.success(Data("paused\u{1e}Song\u{1e}Artist".utf8))]
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy })
        XCTAssertNil(spotify.artwork); XCTAssertEqual(spotify.track?.playing, false)

        script.replies = [.success(Data("error\u{1e}-1743\u{1e} ".utf8))]
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy })
        XCTAssertFalse(spotify.connected); XCTAssertTrue(spotify.status.contains("Automation"))
        script.replies = [.success(Data("garbage".utf8))]
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy })
        XCTAssertTrue(spotify.status.hasPrefix("No readable track"))
        script.replies = [.failure(UsageError.timeout)]
        spotify.refresh(); XCTAssertTrue(IntegrationsUI.wait { !spotify.busy })
        XCTAssertTrue(spotify.status.hasPrefix("Could not read Fixture"))

        // A reply that arrives after Disconnect is discarded.
        script.replies = [.success(Data("playing\u{1e}Song\u{1e}Artist".utf8))]
        spotify.refresh(); spotify.disconnect()
        IntegrationsUI.spin(0.2)
        XCTAssertNil(spotify.track); XCTAssertEqual(spotify.status, "Disconnected.")

        spotify.isRunning = { _ in false }
        spotify.refresh(); XCTAssertTrue(spotify.status.hasPrefix("Open Fixture"))
    }

    func testAppleMusicArtwork() {
        let script = Script()
        let music = player("com.apple.Music", script: script)
        let hex = png().map { String(format: "%02X", $0) }.joined()
        script.replies = [.success(Data("playing\u{1e}Song\u{1e}Artist\u{1e}ABC123".utf8)), .success(Data("«data tdta\(hex)»".utf8))]
        music.refresh(command: .next)
        XCTAssertTrue(IntegrationsUI.wait { music.artwork != nil })
        XCTAssertTrue(script.sources[0].contains("exists current track") && script.sources[1].contains("raw data of artwork"))
        script.replies = [.success(Data("playing\u{1e}Song 2\u{1e}Artist\u{1e}DEF456".utf8)), .success(Data("not artwork".utf8))]
        music.refresh(); XCTAssertTrue(IntegrationsUI.wait { !music.busy }); IntegrationsUI.spin(0.1)
        XCTAssertNil(music.artwork)
    }

    func testPollingTimerOnlyWhileConnected() {
        let script = Script()
        let music = player("com.apple.Music", script: script)
        music.timer?.fire(); IntegrationsUI.spin(0.05)
        XCTAssertTrue(script.sources.isEmpty)
        music.connected = true
        music.timer?.fire()
        XCTAssertTrue(IntegrationsUI.wait { script.sources.count == 1 && !music.busy })
    }

    func testRealArtworkFetcherRejectsUntrustedHosts() async {
        let player = MusicPlayer(name: "Fixture", bundleID: "invalid.dockgrove.fixture")
        do { _ = try await player.fetchArtwork(URL(string: "https://example.com/art.png")!); XCTFail("Untrusted artwork host accepted") } catch { }
    }

    func testBoundedProcessKillsAfterTimeout() async throws {
        do { _ = try await Task.detached { try BoundedProcess.run("/bin/sleep", arguments: ["5"], timeout: 0.1) }.value; XCTFail("Timeout accepted") } catch { }
        try await Task.sleep(nanoseconds: 1_300_000_000)
    }

    func testPlayerViewStatesAndActions() {
        let script = Script()
        let player = player("com.spotify.client", script: script)
        var launched = 0
        player.locate = { _ in URL(fileURLWithPath: "/Applications/Fixture.app") }
        player.launch = { _ in launched += 1 }
        for setup in [true, false] { IntegrationsUI.render(MusicPlayerView(player: player), setup: setup) }
        player.connected = true
        player.track = TrackSnapshot(title: "Song", artist: "Artist", playing: true)
        for setup in [true, false] { IntegrationsUI.render(MusicPlayerView(player: player), setup: setup, dark: true) }
        player.track = TrackSnapshot(title: "Song", artist: "Artist", playing: false)
        IntegrationsUI.render(MusicPlayerView(player: player))

        let view = MusicPlayerView(player: player, setupAllowedOverride: true)
        IntegrationsUI.press(IntegrationsUI.body(view), "Open")
        XCTAssertEqual(launched, 1)
        for title in ["Refresh", "Previous", "Play", "Next"] {
            IntegrationsUI.press(IntegrationsUI.body(view), title)
            XCTAssertTrue(IntegrationsUI.wait { !player.busy })
            player.connected = true
        }
        XCTAssertTrue(script.sources.contains { $0.contains("previous track") })
        XCTAssertTrue(script.sources.contains { $0.contains("next track") })
        let access = IntegrationsUI.toggles(in: IntegrationsUI.body(view))
        XCTAssertEqual(access.count, 1)
        guard let allow = access.first else { return }
        XCTAssertTrue(allow.isOn)
        allow.isOn = false
        XCTAssertFalse(player.connected)
        allow.isOn = true
        XCTAssertTrue(IntegrationsUI.wait { !player.busy })
        player.connected = true
        IntegrationsUI.press(IntegrationsUI.body(MusicPlayerView(player: player, setupAllowedOverride: true)), "Remove access")
        XCTAssertFalse(player.connected)
    }
}

// MARK: - GitHub

@MainActor final class IntegrationsGitHubTests: XCTestCase {
    private let summary = Data(#"{"full_name":"o/r","html_url":"https://github.com/o/r","stargazers_count":1,"forks_count":2,"open_issues_count":3,"description":"Fixture"}"#.utf8)
    private let issues = Data(#"[{"id":1,"number":7,"title":"Bug","html_url":"https://github.com/o/r/issues/7","pull_request":{"url":"https://api.github.com/x"}}]"#.utf8)
    private let runs = Data(#"{"workflow_runs":[{"id":2,"name":null,"status":"completed","conclusion":null,"html_url":"https://github.com/o/r/actions/runs/2"}]}"#.utf8)

    private func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.github.com/")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func testErrorsAndRunStatus() throws {
        for error in [GitHubReadError.invalidRepository, .missingCLI, .access, .rateLimited, .timeout, .response] { XCTAssertFalse(error.errorDescription!.isEmpty) }
        let run = try JSONDecoder().decode(RepositoryRuns.self, from: runs).workflow_runs[0]
        XCTAssertEqual(run.displayStatus, "Unknown conclusion")
    }

    func testHTTPFetchOutcomes() async throws {
        let (summary, issues, runs) = (summary, issues, runs)
        var requests: [URLRequest] = []
        let snapshot = try await GitHubClient.fetch("o/r", useCLI: false, http: { request in
            requests.append(request)
            let path = request.url!.absoluteString
            return (path.contains("/issues") ? issues : path.contains("/actions") ? runs : summary, self.response(200))
        })
        XCTAssertEqual(snapshot.repository.full_name, "o/r"); XCTAssertEqual(snapshot.issues.count, 1); XCTAssertNotNil(snapshot.run); XCTAssertNil(snapshot.activityWarning)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "User-Agent"), "DockGrove")

        let partial = try await GitHubClient.fetch("o/r", useCLI: false, http: { request in
            request.url!.absoluteString.hasSuffix("repos/o/r") ? (summary, self.response(200)) : (Data(), self.response(404))
        })
        XCTAssertEqual(partial.activityWarning, "Issues unavailable · Actions unavailable")

        let cases: [(URLResponse, Data, GitHubReadError)] = [
            (URLResponse(url: URL(string: "https://api.github.com/")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), summary, .response),
            (response(429), summary, .rateLimited), (response(403, ["X-RateLimit-Remaining": "0"]), summary, .rateLimited),
            (response(403), summary, .access), (response(404), summary, .access), (response(200), Data(count: 4_000_001), .response)]
        for (reply, body, expected) in cases {
            do { _ = try await GitHubClient.fetch("o/r", useCLI: false, http: { _ in (body, reply) }); XCTFail("Accepted \(expected)") }
            catch { XCTAssertEqual(error as? GitHubReadError, expected) }
        }
        do { _ = try await GitHubClient.fetch("not a repo", useCLI: false); XCTFail("Invalid repository accepted") }
        catch { XCTAssertEqual(error as? GitHubReadError, .invalidRepository) }
    }

    func testDefaultTransportsStayLocal() async throws {
        // The default HTTP transport against a local file base returns a non-HTTP response.
        let folder = try IntegrationsUI.temporaryDirectory(self)
        do { _ = try await GitHubClient.fetch("o/r", useCLI: false, api: folder.appendingPathComponent("api/", isDirectory: true)); XCTFail("File response accepted") }
        catch { XCTAssertNotNil(error) }
        // The widget's default loader rejects an invalid stored repository before any request.
        let store = IntegrationsUI.defaults(self)
        store.set("not a repository", forKey: "githubRepository")
        let widget = GitHubWidget(store: store)
        widget.refresh()
        let settled = await IntegrationsUI.settle { !widget.loading }
        XCTAssertTrue(settled)
        XCTAssertEqual(widget.error, GitHubReadError.invalidRepository.localizedDescription)
    }

    func testDownloadUsesLocalDataURL() async throws {
        let (data, response) = try await GitHubClient.download(URLRequest(url: URL(string: "data:application/json,%5B%5D")!))
        XCTAssertEqual(data, Data("[]".utf8)); XCTAssertFalse(response is HTTPURLResponse)
    }

    func testCLIFetchOutcomes() async throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        func gh(_ mode: String) throws -> [String] { [folder.appendingPathComponent("missing").path, try IntegrationsUI.fixture("SignInFixture", named: "gh-" + mode, in: folder)] }
        let snapshot = try await GitHubClient.fetch("o/r", useCLI: true, cliPaths: try gh("ok"))
        XCTAssertEqual(snapshot.issues.first?.number, 7); XCTAssertEqual(snapshot.run?.displayStatus, "success")
        let partial = try await GitHubClient.fetch("o/r", useCLI: true, cliPaths: try gh("partial"))
        XCTAssertEqual(partial.activityWarning, "Issues unavailable · Actions unavailable")
        for (mode, expected) in [("fail", GitHubReadError.access), ("big", .response)] {
            do { _ = try await GitHubClient.fetch("o/r", useCLI: true, cliPaths: try gh(mode)); XCTFail("Accepted \(mode)") }
            catch { XCTAssertEqual(error as? GitHubReadError, expected) }
        }
        do { _ = try await GitHubClient.fetch("o/r", useCLI: true, cliPaths: try gh("hang"), cliTimeout: 0.3); XCTFail("Hang accepted") }
        catch { XCTAssertEqual(error as? GitHubReadError, .timeout) }
        do { _ = try await GitHubClient.fetch("o/r", useCLI: true, cliPaths: []); XCTFail("Missing CLI accepted") }
        catch { XCTAssertEqual(error as? GitHubReadError, .missingCLI) }
        try await Task.sleep(nanoseconds: 1_200_000_000) // Lets the delayed SIGKILL check run.
    }

    func testWidgetRefreshInvalidationAndTimer() async throws {
        let store = IntegrationsUI.defaults(self)
        let snapshot = GitHubSnapshot(repository: try JSONDecoder().decode(RepositorySummary.self, from: summary), issues: [], run: nil, activityWarning: nil)
        var outcome: Result<GitHubSnapshot, Error> = .success(snapshot)
        var calls: [(String, Bool)] = [], delay: UInt64 = 0
        let fetch: (String, Bool) async throws -> GitHubSnapshot = { repo, cli in
            calls.append((repo, cli))
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            return try outcome.get()
        }
        store.set(true, forKey: "githubAutoRefresh")
        let widget = GitHubWidget(store: store, fetch: fetch)
        XCTAssertTrue(widget.loading)
        widget.refresh() // Ignored while loading.
        await IntegrationsUI.settle { !widget.loading }
        XCTAssertNotNil(widget.snapshot); XCTAssertNotNil(widget.refreshed); XCTAssertEqual(calls.count, 1)

        widget.useCLI = true
        XCTAssertNil(widget.snapshot); XCTAssertTrue(store.bool(forKey: "githubUseCLI"))
        widget.useCLI = true
        widget.autoRefresh = false; XCTAssertFalse(store.bool(forKey: "githubAutoRefresh"))
        outcome = .failure(GitHubReadError.rateLimited)
        widget.refresh(); await IntegrationsUI.settle { !widget.loading }
        XCTAssertEqual(widget.error, GitHubReadError.rateLimited.localizedDescription)
        XCTAssertTrue(calls.last!.1)
        outcome = .failure(URLError(.notConnectedToInternet))
        widget.refresh(); await IntegrationsUI.settle { !widget.loading }
        XCTAssertEqual(widget.error, "Could not load GitHub. Check your connection and try again.")

        // Changing the repository discards responses for the old one.
        delay = 150_000_000
        outcome = .success(snapshot)
        widget.refresh(); widget.repository = "o/other"
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(widget.snapshot)
        outcome = .failure(GitHubReadError.access)
        widget.refresh(); widget.repository = "o/third"
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(widget.error)
        widget.repository = "o/third"
        delay = 0

        let before = calls.count
        widget.timer?.fire(); try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(calls.count, before)
        widget.autoRefresh = true
        widget.timer?.fire()
        let polled = await IntegrationsUI.settle { calls.count == before + 1 }
        XCTAssertTrue(polled)
    }
}
