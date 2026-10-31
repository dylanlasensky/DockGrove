import AppKit
import WeatherKit
import SwiftUI
import Combine
import EventKit
import IOKit.ps

struct TaskItem: Codable, Identifiable { var id = UUID(); var title: String; var done = false }
struct DockProfile: Codable, Identifiable {
    var id = UUID(); var name: String; var apps: [String]; var widgets: [String]; var accent: String; var size: Double; var richWidgets: Bool? = nil; var theme: String? = nil; var widthFraction: Double? = nil; var alignment: Double? = nil; var elevation: Double? = nil; var edge: String? = nil; var albumColors: Bool? = nil; var entryOrder: [String]? = nil; var widgetShapes: [String: String]? = nil; var toolbarHeight: Double? = nil; var fitToolbarToContent: Bool? = nil
}
@MainActor final class Toolkit: ObservableObject {
    @Published var note: String { didSet { store.set(note, forKey: "quickNote") } }
    @Published var tasks: [TaskItem] { didSet { save(tasks, "tasks") } }
    @Published var files: [String] { didSet { store.set(files, forKey: "shelfFiles") } }
    @Published var enabled: [String] { didSet { store.set(enabled, forKey: "widgets"); if !enabled.contains("system") { monitor.stop() }; if !enabled.contains("claudeCodeUsage") { claudeCodeUsage.stop() }; if !enabled.contains("geminiUsage") { geminiUsage.stop() } } }
    @Published var profiles: [DockProfile] { didSet { save(profiles, "profiles") } }
    @Published var widgetShapes: [String: String] { didSet { store.set(widgetShapes, forKey: "widgetShapes") } }
    @Published var richWidgets: Bool { didSet { store.set(richWidgets, forKey: "richWidgets") } }
    @Published var autoHide: Bool { didSet { store.set(autoHide, forKey: "autoHide") } }
    @Published var hideOnOverlap: Bool { didSet { store.set(hideOnOverlap, forKey: "hideOnOverlap") } }
    @Published var showRunning: Bool { didSet { store.set(showRunning, forKey: "showRunning") } }
    @Published var edge: String { didSet { store.set(edge, forKey: "edge") } }
    @Published var screenIndex: Int { didSet { store.set(screenIndex, forKey: "screenIndex") } }
    @Published var clipboardEnabled = false { didSet { pasteboardChange = pasteboard.changeCount } }
    /// Clipboard history source; tests substitute a private named pasteboard.
    var pasteboard = NSPasteboard.general
    /// System side effects, replaceable so tests never show panels or reach Apple Weather.
    var chooseFiles: () -> [URL] = Toolkit.runFilePanel
    var weatherFetch: @MainActor (String) async throws -> WeatherSnapshot = AppleWeatherClient.fetch(city:)
    var applicationRoots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    static func runFilePanel() -> [URL] {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
    @Published var clipboard: [String] = []
    @Published var weatherCity = "" {
        didSet {
            if weatherCity != oldValue {
                weatherRequestRevision &+= 1
                weatherSnapshot = nil
                weatherText = "Choose a city"
                weatherDetail = ""
            }
        }
    }
    @Published var weatherSnapshot: WeatherSnapshot?
    private var weatherRequestRevision: UInt = 0
    @Published var weatherText = "Choose a city"
    @Published var weatherDetail = ""
    @Published var weatherLoading = false
    @Published var query = ""
    @Published var draftTask = ""
    @Published var profileName = ""
    /// Assigning apps directly (instead of scanning) rebuilds the search index to match.
    @Published var applications: [DockApp] = [] {
        didSet {
            guard appIndex.apps != applications else { return }
            appIndex = AppSearchIndex(applications.map { AppSearchIndex.Record(path: $0.url.path, name: $0.name, bundleIdentifier: Bundle(url: $0.url)?.bundleIdentifier, modified: nil, aliases: [], lookups: [:]) })
        }
    }
    @Published var seconds = 25 * 60
    @Published var focusEnd: Date?
    @Published var focusFinished = false
    @Published var battery = "Desktop"
    @Published var memory = ""
    @Published var storage = ""
    let pet: Companion
    let monitor = SystemMonitor()
    let audio = AudioControl()
    let currency = CurrencyWidget()
    let voiceMemo = VoiceMemo()
    let groups: AppGroups
    private var observers = Set<AnyCancellable>()
    let calendar: CalendarWidget
    let googleCalendar: CalendarWidget
    let spotify = MusicPlayer(name: "Spotify", bundleID: "com.spotify.client")
    let appleMusic = MusicPlayer(name: "Apple Music", bundleID: "com.apple.Music")
    let windows = WindowManager()
    let claudeCodeUsage = LocalAIWidget(.claude)
    let geminiUsage = LocalAIWidget(.gemini)
    let openaiUsage = AIUsageWidget(.openai)
    let anthropicUsage = AIUsageWidget(.anthropic)
    let cursorUsage = AIUsageWidget(.cursor)
    let github: GitHubWidget
    let utilities: Utilities
    let store: UserDefaults
    private(set) var tick: Timer?
    private var pasteboardChange = NSPasteboard.general.changeCount
    private var ticks = 0
    /// Whether StoreKit tiers gate widgets; a build setting, injectable so both modes are testable.
    let purchasesEnabled: Bool
    init(store: UserDefaults = .standard, purchasesEnabled: Bool = PurchaseConfiguration.enabled) {
        self.store = store
        self.purchasesEnabled = purchasesEnabled
        pet = Companion(defaults: store)
        groups = AppGroups(defaults: store)
        widgetShapes = WidgetShapeStyle.validated(store.dictionary(forKey: "widgetShapes") as? [String: String] ?? [:])
        richWidgets = store.object(forKey: "richWidgets") as? Bool ?? true
        calendar = CalendarWidget(store: store)
        googleCalendar = CalendarWidget(store: store, google: true)
        utilities = Utilities(store: store)
        github = GitHubWidget(store: store)
        note = store.string(forKey: "quickNote") ?? ""
        tasks = Self.decode([TaskItem].self, store: store, key: "tasks") ?? []
        profiles = Self.decode([DockProfile].self, store: store, key: "profiles") ?? []
        files = store.stringArray(forKey: "shelfFiles") ?? []
        enabled = store.stringArray(forKey: "widgets") ?? ["search", "focus", "tasks"]
        hideOnOverlap = store.bool(forKey: "hideOnOverlap")
        autoHide = store.bool(forKey: "autoHide"); showRunning = store.object(forKey: "showRunning") as? Bool ?? true
        edge = store.string(forKey: "edge") ?? "Bottom"; screenIndex = store.integer(forKey: "screenIndex")
        for publisher in [pet.objectWillChange, claudeCodeUsage.objectWillChange, geminiUsage.objectWillChange, monitor.objectWillChange, audio.objectWillChange, currency.objectWillChange, voiceMemo.objectWillChange, groups.objectWillChange, calendar.objectWillChange, googleCalendar.objectWillChange, spotify.objectWillChange, appleMusic.objectWillChange, openaiUsage.objectWillChange, anthropicUsage.objectWillChange, cursorUsage.objectWillChange] {
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        }
        sampleSystem()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tickNow() } }
    }
    deinit { tick?.invalidate() }
    private static func decode<T: Decodable>(_ type: T.Type, store: UserDefaults, key: String) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    private func save<T: Encodable>(_ value: T, _ key: String) { if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) } }
    func canAccess(_ kind: ToolKind) -> Bool {
        !purchasesEnabled || PurchaseManager.shared.tier >= kind.requiredAccess
    }
    func stopLockedWidgets() {
        if !canAccess(.system) { monitor.stop() }
        if !canAccess(.claudeCodeUsage) { claudeCodeUsage.stop() }
        if !canAccess(.geminiUsage) { geminiUsage.stop() }
        if !canAccess(.clipboard) { clipboard = [] }
    }
    func toggle(_ kind: ToolKind, _ value: Bool) { guard !value || canAccess(kind) else { return }; if value { if !enabled.contains(kind.rawValue) { enabled.append(kind.rawValue) } } else { enabled.removeAll { $0 == kind.rawValue } } }
    func moveWidget(_ kind: ToolKind, by offset: Int) {
        guard let i = enabled.firstIndex(of: kind.rawValue), enabled.indices.contains(i + offset) else { return }
        enabled.swapAt(i, i + offset)
    }
    func tickNow() {
        if let end = focusEnd {
            seconds = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if seconds == 0 { focusEnd = nil; focusFinished = true; pet.state.reward(); NSSound(named: "Glass")?.play() }
        }
        ticks += 1
        if ticks % 15 == 0 { sampleSystem(); pet.tick() }
        if canAccess(.clipboard) && clipboardEnabled && pasteboard.changeCount != pasteboardChange {
            pasteboardChange = pasteboard.changeCount
            let forbidden = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
            guard pasteboard.types?.contains(where: { forbidden.contains($0.rawValue) }) != true,
                  let value = pasteboard.string(forType: .string), !value.isEmpty, value.utf8.count < 100_000 else { return }
            clipboard.removeAll { $0 == value }; clipboard.insert(value, at: 0); clipboard = Array(clipboard.prefix(20))
        }
    }
    var timerText: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    func toggleTimer() { focusFinished = false; if focusEnd != nil { focusEnd = nil } else { if seconds == 0 { seconds = 1500 }; focusEnd = Date().addingTimeInterval(Double(seconds)) } }
    func resetTimer(_ minutes: Int) { focusEnd = nil; seconds = minutes * 60; focusFinished = false }
    func addTask() { let text = draftTask.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; tasks.append(TaskItem(title: text)); draftTask = "" }
    func addFiles() {
        for url in chooseFiles() { addFile(url) }
    }
    func addFile(_ url: URL) { guard url.isFileURL, !files.contains(url.path) else { return }; files.append(url.path) }
    @Published private(set) var scanningApps = false
    @Published private(set) var appIndex = AppSearchIndex()
    lazy var appIndexStore = AppIndexStore.shared
    func scanApplications(force: Bool = false) {
        guard !scanningApps, force || applications.isEmpty else { return }
        scanningApps = true
        let roots = applicationRoots
        let store = appIndexStore
        Task {
            // Show the cached catalog at once, then reconcile it with the disk.
            let cached = await Task.detached(priority: .userInitiated) { store.load() }.value
            if applications.isEmpty, !cached.isEmpty { publish(AppSearchIndex(cached)) }
            let scanned = await Task.detached(priority: .utility) { Self.applicationRecords(roots, cached: cached, seeds: store.seedAliases()) }.value
            // Lookups learned while the scan ran must survive it.
            let current = appIndex
            let records = scanned.map { record -> AppSearchIndex.Record in
                guard let live = current.record(atPath: record.path) else { return record }
                var merged = record; merged.aliases = live.aliases; merged.lookups = live.lookups; return merged
            }
            if records != cached { store.saveLater(records) }
            if records != appIndex.records { publish(AppSearchIndex(records)) }
            scanningApps = false
        }
    }
    private func publish(_ index: AppSearchIndex) {
        appIndex = index
        if applications != index.apps { applications = index.apps }
    }
    /// Remember that `query` led to `app`, so the next identical search ranks it first.
    func recordLaunch(_ app: DockApp, query: String) {
        guard let next = appIndex.recordingLaunch(of: app, query: query) else { return }
        appIndex = next
        appIndexStore.saveLater(next.records)
    }
    /// Unchanged bundles keep their cached record; new or modified ones are re-read, keeping their aliases and lookups.
    /// New apps start with aliases from the bundled seed, matched by bundle identifier, then name.
    nonisolated static func applicationRecords(_ roots: [String], cached: [AppSearchIndex.Record] = [], seeds: [String: [String]] = [:]) -> [AppSearchIndex.Record] {
        var found: [URL: Date?] = [:]
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator where url.pathExtension == "app" {
                found[url.standardizedFileURL] = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
        }
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if FileManager.default.fileExists(atPath: finder.path) { found[finder] = try? finder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let previous = AppSearchIndex(cached)
        let records = found.map { url, modified -> AppSearchIndex.Record in
            let old = previous.record(atPath: url.path)
            if let old, old.modified == modified { return old }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let bundle = Bundle(url: url)?.bundleIdentifier
            let aliases = old?.aliases ?? bundle.flatMap { seeds[AppSearchIndex.fold($0)] } ?? seeds[AppSearchIndex.fold(name)] ?? []
            return AppSearchIndex.Record(path: url.path, name: name, bundleIdentifier: bundle, modified: modified, aliases: aliases, lookups: old?.lookups ?? [:])
        }
        return records.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
    }
    func sampleSystem() {
        memory = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory) + " RAM installed"
        if let data = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()), let free = data[.systemFreeSize] as? NSNumber {
            storage = ByteCountFormatter.string(fromByteCount: free.int64Value, countStyle: .file) + " disk available"
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let current = values[kIOPSCurrentCapacityKey] as? Int, let max = values[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    battery = "\(current * 100 / max)%" + ((values[kIOPSIsChargingKey] as? Bool == true) ? " charging" : " battery")
                }
            }
        }
    }
    func fetchWeather() {
        Task { @MainActor in await loadWeather() }
    }

    func loadWeather(using custom: (@MainActor (String) async throws -> WeatherSnapshot)? = nil) async {
        let fetch = custom ?? weatherFetch
        let query = weatherCity
        let revision = weatherRequestRevision
        let city = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty, !weatherLoading else { return }
        weatherLoading = true
        defer { weatherLoading = false }
        do {
            let snapshot = try await fetch(city)
            // An in-flight response must never appear under a newly entered city.
            guard weatherRequestRevision == revision else { return }
            weatherSnapshot = snapshot
            weatherText = WeatherSnapshot.fahrenheit(snapshot.temperature)
            weatherDetail = "\(snapshot.city) · \(snapshot.condition) · Feels like \(WeatherSnapshot.fahrenheit(snapshot.apparentTemperature)) · Updated \(snapshot.date.formatted(date: .omitted, time: .shortened))"
        } catch {
            guard weatherRequestRevision == revision else { return }
            weatherSnapshot = nil
            weatherText = "Unavailable"
            if error is WeatherLookupError {
                weatherDetail = "City not found. Try adding a state or country."
            } else if let weatherError = error as? WeatherError, weatherError == .permissionDenied {
                weatherDetail = "Apple Weather isn’t available in this build."
            } else {
                weatherDetail = "Could not load Apple Weather. Check the city and your connection, then retry."
            }
        }
    }
}
