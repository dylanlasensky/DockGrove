import AppKit
import SwiftUI
import Combine
import EventKit
import IOKit.ps

struct TaskItem: Codable, Identifiable { var id = UUID(); var title: String; var done = false }
struct DockProfile: Codable, Identifiable {
    var id = UUID(); var name: String; var apps: [String]; var widgets: [String]; var accent: String; var size: Double
}
enum ToolKind: String, CaseIterable, Identifiable {
    case search, focus, notes, tasks, files, system, calendar, clipboard, weather, music
    var id: String { rawValue }
    var title: String { switch self {
    case .weather: return "Weather"; case .music: return "Music"; case .search: return "App search"; case .focus: return "Focus"; case .notes: return "Quick note"; case .tasks: return "Tasks"
    case .files: return "File shelf"; case .system: return "System"; case .calendar: return "Calendar"; case .clipboard: return "Clipboard"
    } }
    var icon: String { switch self {
    case .weather: return "cloud.sun"; case .music: return "music.note"; case .search: return "magnifyingglass"; case .focus: return "timer"; case .notes: return "note.text"; case .tasks: return "checklist"
    case .files: return "tray.full"; case .system: return "gauge.with.dots.needle.50percent"; case .calendar: return "calendar"; case .clipboard: return "doc.on.clipboard"
    } }
}
@MainActor final class Toolkit: ObservableObject {
    @Published var note: String { didSet { store.set(note, forKey: "quickNote") } }
    @Published var tasks: [TaskItem] { didSet { save(tasks, "tasks") } }
    @Published var files: [String] { didSet { store.set(files, forKey: "shelfFiles") } }
    @Published var enabled: [String] { didSet { store.set(enabled, forKey: "widgets") } }
    @Published var profiles: [DockProfile] { didSet { save(profiles, "profiles") } }
    @Published var autoHide: Bool { didSet { store.set(autoHide, forKey: "autoHide") } }
    @Published var showRunning: Bool { didSet { store.set(showRunning, forKey: "showRunning") } }
    @Published var edge: String { didSet { store.set(edge, forKey: "edge") } }
    @Published var screenIndex: Int { didSet { store.set(screenIndex, forKey: "screenIndex") } }
    @Published var clipboardEnabled = false { didSet { pasteboardChange = NSPasteboard.general.changeCount } }
    @Published var clipboard: [String] = []
    @Published var weatherCity = ""
    @Published var weatherText = "Choose a city"
    @Published var weatherDetail = ""
    @Published var weatherLoading = false
    @Published var musicSource = "Spotify"
    @Published var musicTitle = "Connect a player"
    @Published var musicArtist = ""
    @Published var musicConnected = false
    @Published var musicError: String?
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
    @Published var events: [EKEvent] = []
    @Published var calendarStatus = "Connect to see your next seven days."
    let store: UserDefaults
    private let eventStore = EKEventStore()
    private var tick: Timer?
    private var pasteboardChange = NSPasteboard.general.changeCount
    private var ticks = 0
    init(store: UserDefaults = .standard) {
        self.store = store
        note = store.string(forKey: "quickNote") ?? ""
        tasks = Self.decode([TaskItem].self, store: store, key: "tasks") ?? []
        profiles = Self.decode([DockProfile].self, store: store, key: "profiles") ?? []
        files = store.stringArray(forKey: "shelfFiles") ?? []
        enabled = store.stringArray(forKey: "widgets") ?? ["search", "focus", "tasks"]
        autoHide = store.bool(forKey: "autoHide"); showRunning = store.object(forKey: "showRunning") as? Bool ?? true
        edge = store.string(forKey: "edge") ?? "Bottom"; screenIndex = store.integer(forKey: "screenIndex")
        sampleSystem()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tickNow() } }
    }
    deinit { tick?.invalidate() }
    private static func decode<T: Decodable>(_ type: T.Type, store: UserDefaults, key: String) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    private func save<T: Encodable>(_ value: T, _ key: String) { if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) } }
    func toggle(_ kind: ToolKind, _ value: Bool) { if value { if !enabled.contains(kind.rawValue) { enabled.append(kind.rawValue) } } else { enabled.removeAll { $0 == kind.rawValue } } }
    func tickNow() {
        if let end = focusEnd {
            seconds = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if seconds == 0 { focusEnd = nil; focusFinished = true; NSSound(named: "Glass")?.play() }
        }
        ticks += 1
        if ticks % 15 == 0 { sampleSystem() }
        if ticks % 10 == 0 && musicConnected { readMusic() }
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
    func scanApplications() {
        guard applications.isEmpty else { return }
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var found: [DockApp] = []
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator where url.pathExtension == "app" { found.append(DockApp(url: url)) }
        }
        applications = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    func readMusic(command: String? = nil) {
        let bundle = musicSource == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundle }) else {
            musicError = "Open \(musicSource) and play a track first."; return
        }
        let application = musicSource == "Spotify" ? "Spotify" : "Music"
        let action = ["playpause", "next track", "previous track"].contains(command ?? "") ? command! : ""
        let source = "with timeout of 3 seconds\ntell application \"\(application)\"\n\(action)\nreturn {name of current track, artist of current track}\nend tell\nend timeout"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            musicError = "Allow WaveDock to control \(application) in System Settings > Privacy & Security > Automation, then reconnect."
            musicConnected = false; return
        }
        musicTitle = result.atIndex(1)?.stringValue ?? "Nothing playing"
        musicArtist = result.atIndex(2)?.stringValue ?? ""
        musicError = nil; musicConnected = true
    }
    func loadCalendar() {
        Task { @MainActor in
            do {
                guard try await eventStore.requestFullAccessToEvents() else { calendarStatus = "Calendar access was not granted. You can change it in System Settings."; return }
                let predicate = eventStore.predicateForEvents(withStart: Date(), end: Date().addingTimeInterval(7 * 86400), calendars: nil)
                events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
                calendarStatus = events.isEmpty ? "No events in the next seven days." : "Next seven days"
            } catch { calendarStatus = "Calendar could not be loaded. Check permission in System Settings." }
        }
    }
}
