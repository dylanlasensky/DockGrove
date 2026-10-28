import AppKit

@MainActor func runBehaviorTests() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = DockVisibility()
    func check(_ expected: Bool, _ time: Double = 0, enabled: Bool = true, suppressed: Bool = false,
               auto: Bool = false, overlap: Bool = false, inside: Bool = false, edge: Bool = false, interacting: Bool = false) {
        let actual = policy.visible(now: now.addingTimeInterval(time), enabled: enabled, suppressed: suppressed,
            autoHide: auto, overlapping: overlap, pointerInside: inside, pointerAtEdge: edge, interacting: interacting)
        precondition(actual == expected, "Visibility mismatch at \(time)")
    }
    check(true); check(false, suppressed: true, interacting: true)
    check(false, auto: true, inside: true) // A hidden rectangle cannot reveal itself.
    check(false, 1, auto: true, edge: true)
    check(true, 1.3, auto: true, edge: true)
    check(true, 1.5, auto: true, inside: true)
    check(false, 2.3, auto: true)
    check(true, 3, auto: true, interacting: true)
    check(false, 3.1, enabled: false, interacting: true)
    check(false, 4, overlap: true)
    check(false, 5, overlap: true, edge: true)
    check(true, 5.3, overlap: true, edge: true)
    check(false, 5.4, suppressed: true, edge: true)
    check(true, 6)
    let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
    let dock = CGRect(x: -1200, y: -900, width: 800, height: 100)
    precondition(DockVisibility.atEdge(CGPoint(x: -1000, y: -899), screen: screen, dock: dock, top: false))
    precondition(!DockVisibility.atEdge(CGPoint(x: -1000, y: -850), screen: screen, dock: dock, top: false))
    precondition(!DockVisibility.atEdge(CGPoint(x: -200, y: -899), screen: screen, dock: dock, top: false))
    precondition(DockVisibility.coversScreen(screen, screen))
    precondition(!DockVisibility.coversScreen(CGRect(x: -1440, y: -875, width: 1440, height: 875), screen))
    print("PASS: fullscreen/session suppression, physical edge dwell, hide delay, overlap, negative display coordinates")

    precondition(GitHubClient.normalized("https://github.com/dylanlasensky/WaveDock.git") == "dylanlasensky/WaveDock")
    for invalid in ["owner/repo/extra", "../repo", "owner/repo?token=secret", "https://evil.test/repo", "owner/", "owner/.."] { precondition(GitHubClient.normalized(invalid) == nil) }
    let queued = try JSONDecoder().decode(RepositoryRun.self, from: Data(#"{"id":1,"name":"Build","status":"queued","conclusion":null,"html_url":"https://github.com/a/b/actions/runs/1"}"#.utf8))
    precondition(queued.displayStatus == "queued")
    precondition(GitHubClient.safeURL("https://evil.test/run") == nil)
    precondition(GitHubClient.safeURL("https://github.com/a/b") != nil)
    print("PASS: GitHub repository validation, safe links, queued build status")
    let domain = FileManager.default.temporaryDirectory.appendingPathComponent("WaveDockPreferenceProbe-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: domain.appendingPathExtension("plist")) }
    for (raw, expected) in [("0", false), ("1", true), ("false", false), ("true", true)] {
        let value = try SystemDock.cliValue(DockPreference(type: "boolean", value: raw))
        let (code, _) = try SystemDock.run("/usr/bin/defaults", ["write", domain.path, "probe", "-bool", value])
        precondition(code == 0, "Real defaults boolean write failed")
        let (_, data) = try SystemDock.run("/usr/bin/defaults", ["export", domain.path, "-"])
        let object = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        precondition(object["probe"] as? Bool == expected)
    }
    print("PASS: real macOS defaults command accepts restored boolean representations")
    let suite = "WaveDockBehaviorTests." + UUID().uuidString
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    var preferences: [String: DockPreference] = ["autohide": DockPreference(type: "boolean", value: "false"), "autohide-delay": DockPreference(type: "float", value: "0.75")]
    let original = preferences
    var restarts = 0, fail = false
    let manager = DockRestoration(store: store, read: { preferences[$0] }, write: { key, value in
        if fail { throw UsageError.service }; preferences[key] = value
    }, restart: { restarts += 1 })
    try manager.hide(); precondition(preferences["autohide-delay"]?.value == "86400")
    try manager.hide() // Must not replace the original journal with the hidden settings.
    try manager.restore(); precondition(preferences == original && restarts == 3)
    try manager.restore(); precondition(restarts == 3)
    preferences = [:]; try manager.hide(); try manager.restore(); precondition(preferences.isEmpty)
    preferences = original; try manager.hide(); fail = true
    do { try manager.restore(); preconditionFailure("Failed restore must throw") } catch { }
    precondition(store.data(forKey: DockRestoration.key) != nil)
    fail = false; try manager.restore(); precondition(preferences == original)
    fail = true
    do { try manager.hide(); preconditionFailure("Failed write must throw") } catch { }
    precondition(store.data(forKey: DockRestoration.key) != nil)
    fail = false; try manager.restore(); precondition(preferences == original)
    print("PASS: replacement journal, repeated enable, exact restore, absent keys, failed writes, crash recovery")

    let github = GitHubWidget(store: store)
    let summary = try JSONDecoder().decode(RepositorySummary.self, from: Data(#"{"full_name":"owner/repo","html_url":"https://github.com/owner/repo","stargazers_count":1,"forks_count":2,"open_issues_count":3,"description":null}"#.utf8))
    github.snapshot = GitHubSnapshot(repository: summary, issues: [], run: queued, activityWarning: nil)
    let unchanged = github.repository; github.repository = unchanged
    precondition(github.snapshot != nil, "Committing an unchanged text field must preserve the reading")
    github.repository = "other/repo"; precondition(github.snapshot == nil)
    print("PASS: GitHub reading survives unchanged text-field commits; changed repo clears stale data")
    let kit = Toolkit(store: store), utility = kit.utilities
    kit.note = "Saved note"; kit.draftTask = "  Task  "; kit.addTask(); kit.draftTask = "   "; kit.addTask()
    precondition(kit.tasks.count == 1 && kit.tasks[0].title == "Task")
    kit.tasks[0].done = true
    kit.addFile(URL(fileURLWithPath: "/tmp/test")); kit.addFile(URL(fileURLWithPath: "/tmp/test")); kit.addFile(URL(string: "https://example.com")!)
    precondition(kit.files == ["/tmp/test"])
    for kind in ToolKind.allCases { kit.toggle(kind, true); kit.toggle(kind, true) }
    precondition(kit.enabled.count == ToolKind.allCases.count)
    let separatorIndex = kit.enabled.firstIndex(of: "separator")!
    kit.moveWidget(.separator, by: -1); precondition(kit.enabled[separatorIndex - 1] == "separator")
    kit.resetTimer(5); precondition(kit.seconds == 300)
    kit.toggleTimer(); precondition(kit.focusEnd != nil); kit.toggleTimer(); precondition(kit.focusEnd == nil)
    kit.focusEnd = Date().addingTimeInterval(-1); kit.tickNow(); precondition(kit.focusFinished && kit.seconds == 0)
    let restored = Toolkit(store: store)
    precondition(restored.note == "Saved note" && restored.tasks[0].done && restored.files == kit.files && restored.enabled == kit.enabled)
    precondition(!restored.clipboardEnabled && restored.clipboard.isEmpty)
    print("PASS: notes, tasks, shelf deduplication, widget ordering, persistence, focus completion, clipboard opt-in")

    precondition(Bookmark.url("example.com")?.absoluteString == "https://example.com")
    precondition(Bookmark.url("javascript://evil") == nil && Bookmark.url("file:///tmp/test") == nil)
    precondition(Bookmark.url("https://user:password@example.com") == nil)
    precondition(utility.addBookmark(title: "Example", address: "https://example.com"))
    utility.habits = [Habit(title: "Read")]; utility.habits[0].toggle(at: now); utility.habits[0].toggle(at: now)
    precondition(utility.habits[0].completedDays.isEmpty)
    utility.habits[0].toggle(at: now)
    utility.drink(2); precondition(utility.water == 2); utility.drink(-9); precondition(utility.water == 0)
    utility.drink(1); utility.refreshDay(now: Date().addingTimeInterval(86400 * 2)); precondition(utility.water == 0)
    utility.toggleStopwatch(now: now); precondition(utility.elapsed(at: now.addingTimeInterval(5)) == 5)
    utility.toggleStopwatch(now: now.addingTimeInterval(5)); precondition(utility.elapsed(at: now.addingTimeInterval(10)) == 5)
    utility.toggleStopwatch(now: now.addingTimeInterval(10)); precondition(utility.elapsed(at: now.addingTimeInterval(13)) == 8)
    utility.resetStopwatch(); precondition(utility.elapsed(at: now) == 0 && utility.laps.isEmpty)
    precondition(abs(UnitConversion.convert(1, from: "mi", to: "km", category: .length)! - 1.609344) < 0.000001)
    precondition(abs(UnitConversion.convert(32, from: "°F", to: "°C", category: .temperature)!) < 0.000001)
    precondition(abs(UnitConversion.convert(0, from: "°C", to: "K", category: .temperature)! - 273.15) < 0.000001)
    precondition(UnitConversion.convert(1, from: "GiB", to: "MiB", category: .data) == 1024)
    precondition(UnitConversion.convert(1, from: "kg", to: "m", category: .mass) == nil)
    precondition(UnitConversion.convert(.infinity, from: "kg", to: "g", category: .mass) == nil)
    for category in UnitConversion.Category.allCases { for unit in UnitConversion.units(category) {
        precondition(abs(UnitConversion.convert(42, from: unit, to: unit, category: category)! - 42) < 0.000001)
    } }
    let again = Utilities(store: store)
    precondition(again.bookmarks == utility.bookmarks && again.habits[0].completedDays.count == 1)
    precondition(again.zones.allSatisfy { TimeZone(identifier: $0) != nil })
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data().write(to: dir.appendingPathComponent("Beta.txt")); try Data().write(to: dir.appendingPathComponent("Alpha.txt"))
    utility.loadFolder(dir); precondition(utility.sortedFolderItems.map(\.lastPathComponent) == ["Alpha.txt", "Beta.txt"])
    utility.folderQuery = "beta"; precondition(utility.sortedFolderItems.count == 1)
    utility.loadFolder(dir.appendingPathComponent("missing")); precondition(utility.folderItems.isEmpty && utility.status != nil)
    print("PASS: bookmarks, habit toggles, day rollover, stopwatch pause/resume, unit conversions, folder search/error state, world zones")
}
