import AppKit
import SwiftUI
import Combine
import EventKit
import IOKit.ps

struct TaskItem: Codable, Identifiable { var id = UUID(); var title: String; var done = false }
struct DockProfile: Codable, Identifiable {
    var id = UUID(); var name: String; var apps: [String]; var widgets: [String]; var accent: String; var size: Double; var richWidgets: Bool? = nil; var theme: String? = nil; var widthFraction: Double? = nil; var alignment: Double? = nil; var elevation: Double? = nil; var edge: String? = nil; var albumColors: Bool? = nil; var entryOrder: [String]? = nil
}
enum ToolKind: String, CaseIterable, Identifiable {
    case pet, claudeCodeUsage, geminiUsage
    case calculator, currency, voiceMemo, audio, appGroups, webSearch
    case search, focus, notes, tasks, files, system, calendar, clipboard, weather, music
    case bookmarks, folders, stopwatch, water, habits, progress, clocks, converter, capture, colors, controls, reminders, spacer, separator, github
    case windows, googleCalendar, spotify, appleMusic, openaiUsage, anthropicUsage, cursorUsage
    var id: String { rawValue }
    var title: String { switch self {
    case .pet: return "Companion cat"
    case .claudeCodeUsage: return "Claude Code limits"; case .geminiUsage: return "Gemini CLI usage"
    case .calculator: return "Calculator"; case .currency: return "Currency"; case .voiceMemo: return "Voice memo"; case .audio: return "Audio"; case .appGroups: return "App groups"; case .webSearch: return "Web search"
    case .windows: return "Windows"; case .googleCalendar: return "Google Calendar"; case .spotify: return "Spotify"; case .appleMusic: return "Apple Music"; case .openaiUsage: return "OpenAI API usage"; case .anthropicUsage: return "Claude API usage"; case .cursorUsage: return "Cursor team usage"
    case .github: return "GitHub"; case .bookmarks: return "Bookmarks"; case .folders: return "Folders & Downloads"; case .stopwatch: return "Stopwatch"
    case .water: return "Drink water"; case .habits: return "Habits"; case .progress: return "Time progress"; case .clocks: return "World clocks"
    case .converter: return "Converter"; case .capture: return "Screenshot"; case .colors: return "Color picker"; case .controls: return "Quick controls"
    case .reminders: return "Reminders"; case .spacer: return "Space"; case .separator: return "Separator"
    case .weather: return "Weather"; case .music: return "Music"; case .search: return "App search"; case .focus: return "Focus"; case .notes: return "Quick note"; case .tasks: return "Tasks"
    case .files: return "File shelf"; case .system: return "System"; case .calendar: return "Calendar"; case .clipboard: return "Clipboard"
    } }
    var icon: String { switch self {
    case .pet: return "cat"
    case .claudeCodeUsage: return "sparkles"; case .geminiUsage: return "diamond"
    case .calculator: return "equal"; case .currency: return "dollarsign.arrow.circlepath"; case .voiceMemo: return "waveform"; case .audio: return "speaker.wave.2"; case .appGroups: return "square.grid.2x2"; case .webSearch: return "globe"
    case .windows: return "rectangle.split.2x2"; case .googleCalendar: return "calendar.badge.clock"; case .spotify: return "music.note.list"; case .appleMusic: return "music.note"; case .openaiUsage, .anthropicUsage, .cursorUsage: return "chart.bar"
    case .github: return "chevron.left.forwardslash.chevron.right"; case .bookmarks: return "bookmark"; case .folders: return "folder"; case .stopwatch: return "stopwatch"
    case .water: return "drop"; case .habits: return "checkmark.seal"; case .progress: return "chart.pie"; case .clocks: return "globe"
    case .converter: return "arrow.left.arrow.right"; case .capture: return "camera.viewfinder"; case .colors: return "eyedropper"; case .controls: return "switch.2"
    case .reminders: return "list.bullet"; case .spacer: return "space"; case .separator: return "line.diagonal"
    case .weather: return "cloud.sun"; case .music: return "music.note"; case .search: return "magnifyingglass"; case .focus: return "timer"; case .notes: return "note.text"; case .tasks: return "checklist"
    case .files: return "tray.full"; case .system: return "gauge.with.dots.needle.50percent"; case .calendar: return "calendar"; case .clipboard: return "doc.on.clipboard"
    } }
}
@MainActor final class Toolkit: ObservableObject {
    @Published var note: String { didSet { store.set(note, forKey: "quickNote") } }
    @Published var tasks: [TaskItem] { didSet { save(tasks, "tasks") } }
    @Published var files: [String] { didSet { store.set(files, forKey: "shelfFiles") } }
    @Published var enabled: [String] { didSet { store.set(enabled, forKey: "widgets"); if !enabled.contains("system") { monitor.stop() }; if !enabled.contains("claudeCodeUsage") { claudeCodeUsage.stop() }; if !enabled.contains("geminiUsage") { geminiUsage.stop() } } }
    @Published var profiles: [DockProfile] { didSet { save(profiles, "profiles") } }
    @Published var richWidgets: Bool { didSet { store.set(richWidgets, forKey: "richWidgets") } }
    @Published var autoHide: Bool { didSet { store.set(autoHide, forKey: "autoHide") } }
    @Published var hideOnOverlap: Bool { didSet { store.set(hideOnOverlap, forKey: "hideOnOverlap") } }
    @Published var showRunning: Bool { didSet { store.set(showRunning, forKey: "showRunning") } }
    @Published var edge: String { didSet { store.set(edge, forKey: "edge") } }
    @Published var screenIndex: Int { didSet { store.set(screenIndex, forKey: "screenIndex") } }
    @Published var clipboardEnabled = false { didSet { pasteboardChange = NSPasteboard.general.changeCount } }
    @Published var clipboard: [String] = []
    @Published var weatherCity = ""
    @Published var weatherText = "Choose a city"
    @Published var weatherDetail = ""
    @Published var weatherLoading = false
    @Published var query = ""
    @Published var draftTask = ""
    @Published var profileName = ""
    @Published var applications: [DockApp] = []
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
    private var tick: Timer?
    private var pasteboardChange = NSPasteboard.general.changeCount
    private var ticks = 0
    init(store: UserDefaults = .standard) {
        self.store = store
        pet = Companion(defaults: store)
        groups = AppGroups(defaults: store)
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
    func toggle(_ kind: ToolKind, _ value: Bool) { if value { if !enabled.contains(kind.rawValue) { enabled.append(kind.rawValue) } } else { enabled.removeAll { $0 == kind.rawValue } } }
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
        if clipboardEnabled && NSPasteboard.general.changeCount != pasteboardChange {
            pasteboardChange = NSPasteboard.general.changeCount
            let forbidden = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
            guard !(NSPasteboard.general.types ?? []).contains(where: { forbidden.contains($0.rawValue) }),
                  let value = NSPasteboard.general.string(forType: .string), !value.isEmpty, value.utf8.count < 100_000 else { return }
            clipboard.removeAll { $0 == value }; clipboard.insert(value, at: 0); clipboard = Array(clipboard.prefix(20))
        }
    }
    var timerText: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    func toggleTimer() { focusFinished = false; if focusEnd != nil { focusEnd = nil } else { if seconds == 0 { seconds = 1500 }; focusEnd = Date().addingTimeInterval(Double(seconds)) } }
    func resetTimer(_ minutes: Int) { focusEnd = nil; seconds = minutes * 60; focusFinished = false }
    func addTask() { let text = draftTask.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; tasks.append(TaskItem(title: text)); draftTask = "" }
    func addFiles() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { for url in panel.urls { addFile(url) } }
    }
    func addFile(_ url: URL) { guard url.isFileURL, !files.contains(url.path) else { return }; files.append(url.path) }
    @Published private(set) var scanningApps = false
    func scanApplications(force: Bool = false) {
        guard !scanningApps, force || applications.isEmpty else { return }
        scanningApps = true
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        Task {
            let urls = await Task.detached(priority: .utility) { Self.applicationURLs(roots) }.value
            let found = urls.map { DockApp(url: $0) }
            if applications != found { applications = found }
            scanningApps = false
        }
    }
    nonisolated private static func applicationURLs(_ roots: [String]) -> [URL] {
        var found = Set<URL>()
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator where url.pathExtension == "app" { found.insert(url.standardizedFileURL) }
        }
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if FileManager.default.fileExists(atPath: finder.path) { found.insert(finder) }
        return found.sorted {
            let comparison = $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
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
        guard !LicenseConfiguration.commercial else { weatherText = "Weather unavailable"; weatherDetail = "A commercially approved weather service must be configured before this feature can be enabled."; return }
        let city = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty, !weatherLoading else { return }
        weatherLoading = true
        Task { @MainActor in
            defer { weatherLoading = false }
            do {
                var search = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                search.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en")]
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: search.url!); request.timeoutInterval = 15
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let place = (json["results"] as? [[String: Any]])?.first,
                      let lat = place["latitude"] as? Double, let lon = place["longitude"] as? Double else { throw UsageError.service }
                var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                forecast.queryItems = [URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)), URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"), URLQueryItem(name: "temperature_unit", value: "fahrenheit")]
                request = URLRequest(url: forecast.url!); request.timeoutInterval = 15
                let (weather, reply) = try await session.data(for: request)
                guard (reply as? HTTPURLResponse)?.statusCode == 200,
                      let object = try JSONSerialization.jsonObject(with: weather) as? [String: Any], let current = object["current"] as? [String: Any], let temperature = current["temperature_2m"] as? Double else { throw UsageError.service }
                weatherText = "\(Int(temperature.rounded()))°F"
                let feels = current["apparent_temperature"] as? Double ?? temperature
                weatherDetail = "\(place["name"] as? String ?? city) · Feels like \(Int(feels.rounded()))°F · Updated \(Date().formatted(date: .omitted, time: .shortened))"
            } catch { weatherText = "Unavailable"; weatherDetail = "Could not load this city. Check the spelling and connection, then retry." }
        }
    }
}
