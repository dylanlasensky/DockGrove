import AppKit

@MainActor func runIntegrationTests() async throws {
    // Validate whole-tile paging at laptop, external-display and narrow resolutions.
    for screenWidth in [640.0, 800, 1024, 1280, 1440, 1920, 2560, 3840] {
        for iconSize in [36.0, 48, 64] {
            let widths: [CGFloat] = Array(repeating: CGFloat(iconSize + 8), count: 40) + [28, 177] + ToolKind.allCases.map { DockEntry.tool($0).width(iconSize: iconSize) } + [100]
            let width = DockPageLayout.bodyWidth(screenWidth: screenWidth, naturalWidth: widths.reduce(0, +) + Double(widths.count - 1) * DockPageLayout.gap)
            let capacity = width - DockPageLayout.chrome
            let pages = DockPageLayout.pages(widths: widths, available: capacity)
            precondition(width + 24 <= screenWidth)
            precondition(pages.flatMap { $0 } == Array(widths.indices), "Every app and widget must remain reachable exactly once")
            for page in pages { precondition(page.map { widths[$0] }.reduce(0, +) + Double(max(0, page.count - 1)) * DockPageLayout.gap <= capacity, "A tile crosses the page boundary") }
        }
    }
    precondition(DockPageLayout.pages(widths: [], available: 600) == [[]])
    print("PASS: dense Dock with 40 apps and every widget fits whole tiles at 24 screen/icon configurations")
    for area in [CGRect(x: 0, y: 25, width: 1440, height: 795), CGRect(x: -1920, y: -800, width: 1920, height: 1000)] {
        let current = CGRect(x: 40, y: 50, width: 4000, height: 2000)
        for placement in WindowPlacement.allCases { precondition(area.contains(placement.frame(in: area, current: current))) }
        let left = WindowPlacement.left.frame(in: area, current: current), right = WindowPlacement.right.frame(in: area, current: current)
        precondition(left.maxX == right.minX && left.width + right.width == area.width)
        precondition(WindowPlacement.topLeft.frame(in: area, current: current).origin == area.origin)
        precondition(WindowPlacement.bottomRight.frame(in: area, current: current).maxY == area.maxY)
        precondition(WindowPlacement.center.frame(in: area, current: current) == area)
    }
    print("PASS: all ten window layouts, display boundaries, negative origins, oversized centering")
    let track = try TrackSnapshot.decode(Data("playing\u{1e}Title\nwith newline\u{1e}Artist\n".utf8))
    precondition(track.playing && track.title == "Title\nwith newline" && track.artist == "Artist")
    let emptyArtist = try TrackSnapshot.decode(Data("paused\u{1e}Track\u{1e}\n".utf8)); precondition(emptyArtist.artist.isEmpty)
    do {
        _ = try TrackSnapshot.decode(Data("error\u{1e}-1743\u{1e} \n".utf8))
        preconditionFailure("Denied Automation became a track")
    } catch let error as MusicReadFailure { precondition(error.message.contains("denied Automation")) }
    for invalid in ["", "error", "other\u{1e}title\u{1e}artist"] { do { _ = try TrackSnapshot.decode(Data(invalid.utf8)); preconditionFailure("Bad music data accepted") } catch { } }
    let process = try await Task.detached { try BoundedProcess.run("/usr/bin/printf", arguments: ["music"], timeout: 2) }.value
    precondition(String(decoding: process, as: UTF8.self) == "music")
    let began = Date()
    do { _ = try await Task.detached { try BoundedProcess.run("/bin/sleep", arguments: ["5"], timeout: 0.2) }.value; preconditionFailure("Timeout accepted") } catch { }
    precondition(Date().timeIntervalSince(began) < 2)
    let music = MusicPlayer(name: "Test player", bundleID: "invalid.wavedock.test.player")
    music.track = track; music.connected = true; music.refresh(); precondition(!music.connected && music.track == nil)
    music.disconnect(); precondition(!music.busy && music.track == nil)
    print("PASS: music states, empty artist, multiline titles, invalid responses, bounded process timeout, exited player clears stale track")
    let suite = "WaveDockCalendarTests." + UUID().uuidString, defaults: UserDefaults
    defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let google = CalendarWidget(store: defaults, google: true), calendar = CalendarWidget(store: defaults)
    google.selected = ["google-calendar-id"]; calendar.selected = ["local-calendar-id"]
    precondition(CalendarWidget(store: defaults, google: true).selected == ["google-calendar-id"])
    precondition(CalendarWidget(store: defaults).selected == ["local-calendar-id"])
    google.disconnect(); precondition(!google.connected && google.events.isEmpty && google.calendars.isEmpty)
    precondition(!calendar.connected && calendar.events.isEmpty)
    print("PASS: separate Google/general calendar selections, persistence, no implicit access, disconnect clearing")

    let openAI = Data(#"{"data":[{"results":[{"input_tokens":100,"output_tokens":20}]}],"has_more":false,"next_page":null}"#.utf8)
    let claude = Data(#"{"data":[{"results":[{"uncached_input_tokens":100,"cache_read_input_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":10,"ephemeral_1h_input_tokens":5},"output_tokens":20}]}],"has_more":false,"next_page":null}"#.utf8)
    let cursor = Data(#"{"data":[{"agentRequests":2,"chatRequests":3,"composerRequests":4,"totalTabsAccepted":5}]}"#.utf8)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for (provider, data, expected) in [(AIProvider.openai, openAI, [Int64(100),20]), (.anthropic, claude, [165,20]), (.cursor, cursor, [2,3,4,5])] {
        var requests = 0
        let report = try await AIUsageClient.fetch(provider, key: "fixture-only", now: now) { request in
            requests += 1
            precondition(request.url?.scheme == "https")
            precondition(!(request.url?.absoluteString.contains("fixture-only") ?? true))
            if provider == .openai { precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only" && request.httpMethod == "GET") }
            if provider == .anthropic { precondition(request.value(forHTTPHeaderField: "x-api-key") == "fixture-only" && request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01") }
            if provider == .cursor { precondition(request.httpMethod == "POST" && request.httpBody != nil && request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("fixture-only:".utf8).base64EncodedString()) }
            return (data, 200)
        }
        precondition(requests == 1 && report.totals == expected && report.end == now && report.end.timeIntervalSince(report.start) == 7 * 86400)
        for status in [401, 403, 429, 500, 302] {
            do { _ = try await AIUsageClient.fetch(provider, key: "fixture-only") { _ in (data, status) }; preconditionFailure("HTTP error accepted") } catch { precondition(error is AIUsageFailure) }
        }
        do { _ = try provider.decode(Data(#"{"data":[{}]}"#.utf8)); preconditionFailure("Missing usage became zero") } catch { }
    }
    let page1 = Data(#"{"data":[{"results":[{"input_tokens":100,"output_tokens":20}]}],"has_more":true,"next_page":"page2"}"#.utf8)
    var pageCalls = 0
    let paginated = try await AIUsageClient.fetch(.openai, key: "fixture-only") { request in
        pageCalls += 1
        if pageCalls == 2 { precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "page", value: "page2")) == true) }
        return (pageCalls == 1 ? page1 : openAI, 200)
    }
    precondition(pageCalls == 2 && paginated.totals == [200,40])
    do { _ = try await AIUsageClient.fetch(.openai, key: "fixture-only") { _ in (page1, 200) }; preconditionFailure("Pagination loop accepted") } catch { }
    for invalid in [#"{"data":[{"results":[{"input_tokens":-1,"output_tokens":2}]}],"has_more":false}"#, #"{"data":[{"results":[{"input_tokens":true,"output_tokens":2}]}],"has_more":false}"#, #"{"data":[],"has_more":true,"next_page":null}"#] {
        do { _ = try AIProvider.openai.decode(Data(invalid.utf8)); preconditionFailure("Malformed totals accepted") } catch { }
    }
    let empty = try AIProvider.openai.decode(Data(#"{"data":[],"has_more":false}"#.utf8)); precondition(empty.totals == [0,0])
    print("PASS: OpenAI/Claude/Cursor requests and totals, HTTP/auth/rate-limit errors, pagination, repeated cursor rejection, missing/negative/bool data rejection, valid zero usage")
}
