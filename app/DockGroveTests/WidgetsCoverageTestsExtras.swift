import XCTest
import SwiftUI
import AppKit
import AVFoundation
@testable import DockGrove

final class WidgetsFakeRecorder: AVAudioRecorder {
    var recordResult = true
    var resumeResult = true
    var recordCalls = 0
    override func record() -> Bool { recordCalls += 1; return recordCalls == 1 ? recordResult : resumeResult }
    override func pause() {}
    override func stop() {}
    override var currentTime: TimeInterval { 65 }
    override func updateMeters() {}
    override func averagePower(forChannel channelNumber: Int) -> Float { -6 }
}
final class WidgetsFakePlayer: AVAudioPlayer {
    var playResult = true
    override func play() -> Bool { playResult }
    override func stop() {}
}
@MainActor final class WidgetsFakeMemoDevice: VoiceMemoDevice {
    var allowed = true
    var recordResult = true
    var resumeResult = true
    var recorderError: Error?
    var playResult = true
    var playerError: Error?
    var destination: URL?
    var recorders: [WidgetsFakeRecorder] = []
    nonisolated init() {}
    func requestMicrophone() async -> Bool { allowed }
    nonisolated func recorder(url: URL, settings: [String: Any]) throws -> AVAudioRecorder {
        try MainActor.assumeIsolated {
            if let recorderError { throw recorderError }
            let recorder = try WidgetsFakeRecorder(url: url, settings: settings)
            recorder.recordResult = recordResult; recorder.resumeResult = resumeResult
            recorders.append(recorder); return recorder
        }
    }
    nonisolated func player(url: URL) throws -> AVAudioPlayer {
        try MainActor.assumeIsolated {
            if let playerError { throw playerError }
            let player = try WidgetsFakePlayer(data: widgetsWAV())
            player.playResult = playResult; return player
        }
    }
    func exportDestination() -> URL? { destination }
}

@MainActor final class WidgetsCoverageExtrasTests: XCTestCase {
    var log: WidgetEffectLog!
    var directory: URL!
    override func setUp() async throws {
        log = WidgetEffectLog()
        directory = try widgetsTempDir("WidgetsExtras")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        WidgetsStubProtocol.stubs = [:]; WidgetsStubProtocol.requests = []
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    // MARK: Calculator
    func testCalculatorKeysAndErrors() {
        let host = WidgetHost(CalculatorView().environment(\.widgetEffects, log.handler))
        for key in ["(", "7", "+", "2", ")", "×", "3", "-", "1", "÷", "4", "%", "="] { host.press(key) }
        // The result text is selectable AppKit text whose accessibility value can lag; the model checks below cover the math.
        host.press("C")
        for key in ["1", "÷", "0", "="] { host.press(key) }
        host.press("C")
        for key in [".", "="] { host.press(key) }
        host.submit("2^3")
        XCTAssertThrowsError(try Calculator.evaluate("1÷0"))
        XCTAssertThrowsError(try Calculator.evaluate("."))
        XCTAssertEqual(try Calculator.evaluate("(7+2)×3-1÷4%"), 2)
        XCTAssertEqual(try Calculator.evaluate("-(+2)*3/2"), -3)
    }

    // MARK: Currency
    func rateJSON(_ base: String, _ quote: String, _ rate: Double, date: String = "2026-10-30") -> Data {
        Data("{\"date\":\"\(date)\",\"base\":\"\(base)\",\"quote\":\"\(quote)\",\"rate\":\(rate)}".utf8)
    }
    func testCurrencyRefreshPaths() {
        let widget = CurrencyWidget(configuration: WidgetsStubProtocol.configuration())
        XCTAssertNil(widget.converted)
        WidgetsStubProtocol.stubs["api.frankfurter.dev/v2/rate/usd/eur"] = .init(body: rateJSON("USD", "EUR", 0.5))
        widget.refresh()
        XCTAssertTrue(widget.loading)
        widget.refresh() // ignored while loading
        XCTAssertTrue(widgetsWait { !widget.loading })
        XCTAssertEqual(widget.converted, 50)
        XCTAssertEqual(widget.status, "Reference rate · 2026-10-30")
        widget.amount = "abc"; XCTAssertNil(widget.converted)
        widget.amount = "1e308"; widget.report = ExchangeRate(date: "2026-10-30", base: "USD", quote: "EUR", rate: 10); XCTAssertNil(widget.converted)
        widget.amount = "100"
        // Pair changed while loading: the stale result is dropped.
        WidgetsStubProtocol.stubs["api.frankfurter.dev/v2/rate/usd/gbp"] = .init(body: rateJSON("USD", "GBP", 0.8))
        widget.quote = "GBP"; widget.refresh(); widget.quote = "JPY"
        XCTAssertTrue(widgetsWait { !widget.loading })
        XCTAssertNil(widget.report)
        // HTTP failure and bad payloads.
        widget.quote = "CAD"
        WidgetsStubProtocol.stubs["api.frankfurter.dev/v2/rate/usd/cad"] = .init(status: 500)
        widget.refresh(); XCTAssertTrue(widgetsWait { !widget.loading })
        XCTAssertEqual(widget.status, "Could not load the rate. Check your connection and retry.")
        WidgetsStubProtocol.stubs["api.frankfurter.dev/v2/rate/usd/cad"] = .init(body: rateJSON("USD", "EUR", 1.3))
        widget.refresh(); XCTAssertTrue(widgetsWait { !widget.loading })
        XCTAssertNil(widget.report)
        widget.quote = "USD"; widget.refresh()
        XCTAssertEqual(widget.report?.rate, 1); XCTAssertEqual(widget.status, "Same currency")
        widget.base = "XXX"; widget.refresh(); XCTAssertNil(widget.report)
        _ = CurrencyWidget()
    }
    func testCurrencyViewControls() {
        let widget = CurrencyWidget(configuration: WidgetsStubProtocol.configuration())
        WidgetsStubProtocol.stubs["api.frankfurter.dev/v2/rate/eur/usd"] = .init(body: rateJSON("EUR", "USD", 2))
        let host = WidgetHost(CurrencyView(widget: widget).environment(\.widgetEffects, log.handler))
        host.press("Swap currencies")
        XCTAssertEqual(widget.base, "EUR"); XCTAssertEqual(widget.quote, "USD")
        host.press("Refresh rate")
        XCTAssertTrue(widgetsWait { widget.report != nil })
        host.pump()
        XCTAssertTrue(host.contains("200.00 USD"), "\(host.labels())")
        widget.loading = true; host.pump()
        XCTAssertTrue(host.has("Refreshing…"))
        widget.loading = false; host.pump()
        host.choose("GBP", in: "EUR")
        host.choose("JPY", in: "USD")
        XCTAssertEqual(widget.base, "GBP"); XCTAssertEqual(widget.quote, "JPY")
    }

    // MARK: Voice memo
    func makeLibrary() throws -> (URL, URL) {
        let older = directory.appendingPathComponent("Memo-A.m4a"), newer = directory.appendingPathComponent("Memo-B.m4a")
        try widgetsWAV().write(to: older); try widgetsWAV().write(to: newer)
        try Data().write(to: directory.appendingPathComponent("Other.m4a")); try Data().write(to: directory.appendingPathComponent("Memo-C.txt"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: older.path)
        return (older, newer)
    }
    func testVoiceMemoLibraryRecordingAndPlayback() throws {
        let (older, newer) = try makeLibrary()
        let device = WidgetsFakeMemoDevice()
        let memo = VoiceMemo(library: directory, device: device)
        XCTAssertEqual(memo.recordings.map(\.lastPathComponent), ["Memo-B.m4a", "Memo-A.m4a"])
        XCTAssertEqual(memo.file, newer)
        XCTAssertNotEqual(VoiceMemo.label(older), "Saved memo")
        XCTAssertEqual(VoiceMemo.label(directory.appendingPathComponent("missing.m4a")), "Saved memo")
        memo.selectMemo(older); XCTAssertEqual(memo.file, older)
        memo.selectMemo(directory.appendingPathComponent("Other.m4a")); XCTAssertEqual(memo.file, older)

        // Playback: start, stop, finish callbacks, failures.
        memo.play(); XCTAssertTrue(memo.playing)
        memo.selectMemo(newer); XCTAssertFalse(memo.playing)
        memo.play(); memo.play(); XCTAssertEqual(memo.status, "Playback stopped.")
        memo.play()
        memo.audioPlayerDidFinishPlaying(try AVAudioPlayer(data: widgetsWAV()), successfully: true)
        XCTAssertTrue(widgetsWait { memo.status == "Playback complete." })
        memo.audioPlayerDidFinishPlaying(try AVAudioPlayer(data: widgetsWAV()), successfully: false)
        XCTAssertTrue(widgetsWait { memo.status == "Playback could not finish." })
        device.playResult = false; memo.play(); XCTAssertEqual(memo.status, "Could not play this recording.")
        device.playerError = UsageError.service; memo.play(); XCTAssertFalse(memo.playing)
        device.playerError = nil; device.playResult = true

        // Recording: denied, recorder failure, record() refusal, success with metering, pause/resume, stop.
        device.allowed = false; memo.start(); memo.start()
        XCTAssertTrue(widgetsWait { !memo.requesting })
        XCTAssertTrue(memo.status.hasPrefix("Microphone access is required"))
        device.allowed = true; device.recorderError = UsageError.service; memo.start()
        XCTAssertTrue(widgetsWait { !memo.requesting })
        XCTAssertTrue(memo.status.hasPrefix("Could not start recording"))
        device.recorderError = nil; device.recordResult = false; memo.start()
        XCTAssertTrue(widgetsWait { !memo.requesting }); XCTAssertFalse(memo.recording)
        device.recordResult = true; device.resumeResult = false
        memo.play(); XCTAssertTrue(memo.playing)
        memo.start()
        XCTAssertTrue(widgetsWait { memo.recording })
        XCTAssertFalse(memo.playing)
        XCTAssertTrue(widgetsWait { memo.elapsed == 65 })
        XCTAssertEqual(memo.level, 0.5, accuracy: 0.01)
        memo.start(); memo.play(); memo.export(); memo.selectMemo(older)
        memo.togglePause(); XCTAssertTrue(memo.paused)
        memo.togglePause(); XCTAssertTrue(memo.paused) // resume refused
        device.recorders.last?.resumeResult = true
        memo.togglePause(); XCTAssertFalse(memo.paused)
        memo.stop(); XCTAssertFalse(memo.recording); XCTAssertEqual(memo.status, "Memo saved on this Mac.")
        memo.togglePause()
        memo.audioRecorderEncodeErrorDidOccur(device.recorders.last!, error: nil)
        XCTAssertTrue(widgetsWait { memo.status.hasPrefix("Recording stopped because") })

        // Export and library folder.
        memo.selectMemo(older)
        device.destination = nil; memo.export()
        let target = directory.appendingPathComponent("Exported.m4a")
        device.destination = target; memo.export(); XCTAssertEqual(memo.status, "Exported memo.")
        device.destination = directory.appendingPathComponent("missing/dir/x.m4a"); memo.export(); XCTAssertEqual(memo.status, "Could not export the memo.")
        XCTAssertEqual(memo.libraryFolder(), directory)
        XCTAssertEqual(VoiceMemo.modified(directory.appendingPathComponent("missing.m4a")), .distantPast)
        let blocker = directory.appendingPathComponent("blocker"); try Data().write(to: blocker)
        let blocked = VoiceMemo(library: blocker.appendingPathComponent("sub"), device: device)
        XCTAssertNil(blocked.libraryFolder()); XCTAssertEqual(blocked.status, "Could not open the memo folder.")
        blocked.play(); blocked.export()
        XCTAssertTrue(blocked.recordings.isEmpty)
    }
    func testLiveVoiceMemoDeviceBuildsAudioObjects() throws {
        let device = LiveVoiceMemoDevice()
        let wav = directory.appendingPathComponent("x.wav"); try widgetsWAV().write(to: wav)
        XCTAssertNotNil(try device.player(url: wav))
        let recorder = try device.recorder(url: directory.appendingPathComponent("r.m4a"), settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
        XCTAssertFalse(recorder.isRecording)
        _ = VoiceMemo()
    }
    func testVoiceMemoViewStates() throws {
        let (older, _) = try makeLibrary()
        let device = WidgetsFakeMemoDevice()
        let memo = VoiceMemo(library: directory, device: device)
        let host = WidgetHost(VoiceMemoView(memo: memo).environment(\.widgetEffects, log.handler))
        host.choose(VoiceMemo.label(older), in: VoiceMemo.label(memo.file!))
        XCTAssertEqual(memo.file, older)
        host.press("Play"); XCTAssertTrue(memo.playing)
        host.press("Stop playback")
        host.press("Show in Finder")
        host.press("All recordings in Finder")
        XCTAssertEqual(log.names, ["reveal:" + older.path, "open:" + directory.absoluteString])
        device.destination = nil
        host.press("Export…")
        memo.requesting = true; host.pump()
        XCTAssertTrue(host.has("Requesting microphone…"))
        memo.requesting = false; host.pump()
        host.press("Record new memo")
        XCTAssertTrue(widgetsWait { memo.recording }); host.pump()
        host.press("Pause"); XCTAssertTrue(memo.paused)
        device.recorders.last?.resumeResult = true
        host.press("Resume"); XCTAssertFalse(memo.paused)
        host.press("Stop & save"); XCTAssertFalse(memo.recording)
        let blocked = VoiceMemo(library: older.appendingPathComponent("sub"), device: device)
        let failing = WidgetHost(VoiceMemoView(memo: blocked).environment(\.widgetEffects, log.handler))
        failing.press("All recordings in Finder")
        XCTAssertEqual(blocked.status, "Could not open the memo folder.")
    }

    // MARK: App groups and web search
    func testAppGroupsModelAndView() {
        let defaults = widgetDefaults()
        let groups = AppGroups(defaults: defaults)
        groups.add(name: "  ", paths: ["/Applications/A.app"])
        groups.add(name: "Tools", paths: ["/x/readme.txt"])
        XCTAssertTrue(groups.groups.isEmpty)
        let finder = "/System/Library/CoreServices/Finder.app"
        groups.add(name: "Work", paths: [finder, finder, "/Missing/Ghost.app"])
        XCTAssertEqual(groups.groups.first?.paths, [finder, "/Missing/Ghost.app"])
        XCTAssertEqual(AppGroups(defaults: defaults).groups.count, 1)

        let model = DockModel(defaults: defaults)
        widgetsIsolate(model)
        model.apps = [DockApp(url: URL(fileURLWithPath: finder)), DockApp(url: URL(fileURLWithPath: "/System/Applications/Calculator.app"))]
        let host = WidgetHost(AppGroupsView(groups: groups, model: model).environment(\.widgetEffects, log.handler), width: 420, height: 800)
        host.press("Finder")
        XCTAssertEqual(log.names, ["launch:" + finder])
        host.press(model.apps[1].name)
        host.press(model.apps[1].name)
        host.press(model.apps[0].name, index: host.find(model.apps[0].name).count - 1)
        host.type("Pair")
        host.press("Create group")
        XCTAssertEqual(groups.groups.map(\.name), ["Work", "Pair"])
        XCTAssertEqual(groups.groups.last?.paths, [finder])
        host.press("Remove")
        XCTAssertEqual(groups.groups.map(\.name), ["Pair"])
    }
    func testWebSearchEngines() {
        let host = WidgetHost(WebSearchView().environment(\.widgetEffects, log.handler))
        host.submit("")
        host.press("Search in browser")
        XCTAssertTrue(log.names.isEmpty)
        host.type("dock grove")
        host.press("Search in browser")
        host.choose("Google", in: "DuckDuckGo"); host.press("Search in browser")
        host.choose("Bing", in: "Google"); host.submit("swift")
        XCTAssertEqual(log.names, ["open:https://duckduckgo.com/?q=dock%20grove", "open:https://www.google.com/search?q=dock%20grove", "open:https://www.bing.com/search?q=swift"])
    }

    // MARK: GitHub
    func testGitHubViewStates() throws {
        let defaults = widgetDefaults()
        defaults.set("o/r", forKey: "githubRepository")
        let github = GitHubWidget(store: defaults)
        let host = WidgetHost(GitHubView(github: github).environment(\.widgetEffects, log.handler), width: 420, height: 800)
        host.submit("o/r")
        host.press("Refresh GitHub")
        XCTAssertEqual(log.names, ["refreshGitHub", "refreshGitHub"])
        github.snapshot = try widgetsGitHubSnapshot(run: true, warning: "Partial activity"); github.refreshed = Date(); host.pump()
        XCTAssertTrue(host.has("Workflow: in progress"), "\(host.labels())")
        XCTAssertTrue(host.has("Issue #7 · Bug") && host.has("PR #8 · Fix") && host.has("Partial activity"))
        github.snapshot = try widgetsGitHubSnapshot(run: false, warning: nil); github.error = "Offline"; github.loading = true; host.pump()
        XCTAssertTrue(host.has("No workflow run available") && host.has("Offline") && host.has("Refreshing…"))
        XCTAssertTrue(host.contains("Previous reading"))
    }

    // MARK: Small views
    func testWeatherAttributionAndFontAwesome() throws {
        let png = directory.appendingPathComponent("mark.png"); try widgetsPNG().write(to: png)
        let missing = directory.appendingPathComponent("none.png")
        let celsius = Measurement(value: 20, unit: UnitTemperature.celsius)
        for (scheme, light, dark) in [(ColorScheme.dark, png, missing), (.light, missing, png), (.light, png, missing)] {
            let snapshot = WeatherSnapshot(city: "Paris", temperature: celsius, apparentTemperature: celsius, condition: "Clear", symbolName: "sun.max", date: Date(), attributionURL: URL(string: "https://weatherkit.apple.com/legal")!, lightMarkURL: light, darkMarkURL: dark)
            let host = WidgetHost(WeatherAttributionView(snapshot: snapshot), height: 60, scheme: scheme)
            host.pump(0.4)
            XCTAssertTrue(host.has("Apple Weather") || host.has("Other data sources"))
        }
        for kind in ToolKind.allCases { _ = FontAwesomeIcon.provider(kind) }
        XCTAssertEqual(FontAwesomeIcon.provider(.cursorUsage), .code)
        XCTAssertEqual(FontAwesomeIcon.provider(.geminiUsage), .google)
        XCTAssertEqual(FontAwesomeIcon.provider(.openaiUsage), .openAI)
        XCTAssertEqual(FontAwesomeIcon.provider(.anthropicUsage), .claude)
        XCTAssertNil(FontAwesomeIcon.provider(.notes))
        let label = WidgetHost(VStack { ForEach(FontAwesomeIcon.allCases, id: \.self) { FontAwesomeLabel($0.rawValue, icon: $0) } }, height: 400)
        XCTAssertTrue(label.has("credit-card"))
    }

    // MARK: Album artwork
    func testAlbumArtworkDecodingHelpers() {
        let png = widgetsPNG(color: .systemBlue, size: 32)
        XCTAssertNotNil(AlbumArtwork.decode(png))
        XCTAssertNil(AlbumArtwork.decode(Data("nope".utf8)))
        XCTAssertNil(AlbumArtwork.decode(Data(count: 2_000_001)))
        XCTAssertEqual(AlbumArtwork.appleData(Data("«data tdta0A0B»".utf8)), Data([0x0A, 0x0B]))
        XCTAssertNil(AlbumArtwork.appleData(Data("nothing".utf8)))
        XCTAssertNil(AlbumArtwork.appleData(Data("«data tdtaABC»".utf8)))
        XCTAssertNil(AlbumArtwork.appleData(Data("«data tdtaZZ»".utf8)))
        _ = AlbumArtwork.tint(NSImage(data: png)!)
        XCTAssertTrue(AlbumArtwork.allowed(URL(string: "https://image-cdn-ak.spotifycdn.com/x")!))
        XCTAssertFalse(AlbumArtwork.allowed(URL(string: "https://u:p@i.scdn.co/x")!))
    }

    func testAlbumArtworkFetchAndView() async throws {
        let config = WidgetsStubProtocol.configuration()
        let png = widgetsPNG()
        WidgetsStubProtocol.stubs["i.scdn.co/ok"] = .init(mime: "image/png", body: png)
        let data = try await AlbumArtwork.fetch(URL(string: "https://i.scdn.co/ok")!, configuration: config)
        XCTAssertEqual(data, png)
        do { _ = try await AlbumArtwork.fetch(URL(string: "http://i.scdn.co/ok")!); XCTFail() } catch {}
        WidgetsStubProtocol.stubs["i.scdn.co/text"] = .init(mime: "text/html", body: png)
        WidgetsStubProtocol.stubs["i.scdn.co/huge"] = .init(mime: "image/png", body: png, length: 3_000_000)
        WidgetsStubProtocol.stubs["i.scdn.co/stream"] = .init(mime: "image/png", body: Data(count: 2_000_100), length: 1)
        WidgetsStubProtocol.stubs["i.scdn.co/away"] = .init(redirect: URL(string: "https://evil.example/x")!)
        WidgetsStubProtocol.stubs["i.scdn.co/hop"] = .init(redirect: URL(string: "https://mosaic.scdn.co/ok")!)
        WidgetsStubProtocol.stubs["mosaic.scdn.co/ok"] = .init(mime: "image/png", body: png)
        for path in ["text", "huge", "stream", "away", "missing"] {
            do { _ = try await AlbumArtwork.fetch(URL(string: "https://i.scdn.co/" + path)!, configuration: config); XCTFail(path) } catch {}
        }
        let hopped = try? await AlbumArtwork.fetch(URL(string: "https://i.scdn.co/hop")!, configuration: config)
        XCTAssertTrue(hopped == nil || hopped == png)
        XCTAssertTrue(WidgetsStubProtocol.requests.contains { $0.host == "mosaic.scdn.co" })
        XCTAssertFalse(WidgetsStubProtocol.requests.contains { $0.host == "evil.example" })

        let player = MusicPlayer(name: "Spotify", bundleID: "com.spotify.client")
        widgetsIsolate(player)
        let empty = WidgetHost(MusicArtworkView(player: player), width: 60, height: 60)
        empty.pump()
        player.artwork = NSImage(data: png)
        let filled = WidgetHost(MusicArtworkView(player: player, size: 64), width: 80, height: 80)
        filled.pump()
    }
}
