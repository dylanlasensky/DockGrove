import AppKit
import SwiftUI
import EventKit
import ServiceManagement

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var address: String
    static func url(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
struct Habit: Codable, Identifiable {
    var id = UUID(); var title: String; var completedDays: [String] = []
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    mutating func toggle(at date: Date) {
        let day = Self.day(date)
        if completedDays.contains(day) { completedDays.removeAll { $0 == day } }
        else { completedDays.append(day); completedDays = Array(completedDays.suffix(366)) }
    }
}
struct UnitConversion {
    enum Category: String, CaseIterable { case length = "Length", mass = "Mass", temperature = "Temperature", data = "Data" }
    static func units(_ category: Category) -> [String] {
        switch category {
        case .length: return ["m", "km", "cm", "in", "ft", "mi"]
        case .mass: return ["kg", "g", "lb", "oz"]
        case .temperature: return ["°C", "°F", "K"]
        case .data: return ["B", "KB", "MB", "GB", "KiB", "MiB", "GiB"]
        }
    }
    static func convert(_ value: Double, from: String, to: String, category: Category) -> Double? {
        guard value.isFinite, units(category).contains(from), units(category).contains(to) else { return nil }
        if category == .temperature {
            let c = from == "°F" ? (value - 32) * 5 / 9 : from == "K" ? value - 273.15 : value
            return to == "°F" ? c * 9 / 5 + 32 : to == "K" ? c + 273.15 : c
        }
        let factors: [String: Double] = ["m": 1, "km": 1000, "cm": 0.01, "in": 0.0254, "ft": 0.3048, "mi": 1609.344, "kg": 1, "g": 0.001, "lb": 0.45359237, "oz": 0.028349523125, "B": 1, "KB": 1000, "MB": 1e6, "GB": 1e9, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824]
        let result = value * factors[from]! / factors[to]!
        return result.isFinite ? result : nil
    }
}

@MainActor final class Utilities: ObservableObject {
    let store: UserDefaults
    @Published var bookmarks: [Bookmark] { didSet { save(bookmarks, "bookmarks") } }
    @Published var habits: [Habit] { didSet { save(habits, "habits") } }
    @Published var zones: [String] { didSet { store.set(zones, forKey: "worldClockZones") } }
    @Published var water = 0
    @Published var waterGoal: Int { didSet { store.set(waterGoal, forKey: "waterGoal") } }
    @Published var waterReminder: Bool { didSet { store.set(waterReminder, forKey: "waterReminder"); nextDrink = Date().addingTimeInterval(3600) } }
    @Published var waterDue = false
    @Published var stopwatchStart: Date?
    @Published var stopwatchElapsed: TimeInterval = 0
    @Published var laps: [TimeInterval] = []
    @Published var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var folderItems: [URL] = []
    @Published var folderQuery = ""
    @Published var folderSort = "Name"
    @Published var status: String?
    @Published var colorHex = "#FFFFFF"
    @Published var reminders: [EKReminder] = []
    @Published var remindersStatus = "Connect to view and complete Apple Reminders."
    @Published var loginEnabled = LoginService.status() == .enabled
    @Published var busy = false
    /// System services. Tests replace these with fakes; the defaults are the real macOS services.
    var reminderStore: EventStoreAccess = EKEventStore()
    var chooseDirectory: (NSOpenPanel) -> URL? = SystemPicker.run
    var sampleColor: (@escaping (NSColor?) -> Void) -> Void = SystemPicker.sampleColor
    var capture: @Sendable () -> Int32? = Utilities.interactiveCapture
    var setLoginItem: (Bool) throws -> Void = LoginService.set
    var loginStatus: () -> SMAppService.Status = LoginService.status
    var chime: () -> Void = Utilities.playChime
    private(set) var timer: Timer?
    var nextDrink = Date().addingTimeInterval(3600)
    private var waterDay = ""
    init(store: UserDefaults) {
        self.store = store
        bookmarks = Self.read([Bookmark].self, store, "bookmarks") ?? []
        habits = Self.read([Habit].self, store, "habits") ?? []
        zones = store.stringArray(forKey: "worldClockZones") ?? ["America/New_York", "Europe/London", "Asia/Tokyo"]
        waterGoal = max(1, store.object(forKey: "waterGoal") as? Int ?? 8)
        waterReminder = store.bool(forKey: "waterReminder")
        waterDay = store.string(forKey: "waterDay") ?? ""
        water = store.integer(forKey: "waterCount")
        refreshDay()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.refreshDay()
            if self.waterReminder && Date() >= self.nextDrink {
                self.waterDue = true; self.nextDrink = Date().addingTimeInterval(3600); self.chime()
            }
        } }
    }
    deinit { timer?.invalidate() }
    private static func read<T: Decodable>(_ t: T.Type, _ store: UserDefaults, _ key: String) -> T? { store.data(forKey: key).flatMap { try? JSONDecoder().decode(t, from: $0) } }
    private func save<T: Encodable>(_ value: T, _ key: String) { if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) } }
    func refreshDay(now: Date = Date()) {
        let day = Habit.day(now)
        if day != waterDay { water = 0; waterDay = day; store.set(day, forKey: "waterDay"); store.set(0, forKey: "waterCount") }
    }
    func drink(_ delta: Int) { refreshDay(); water = max(0, water + delta); store.set(water, forKey: "waterCount"); waterDue = false }
    func elapsed(at now: Date) -> TimeInterval { stopwatchElapsed + (stopwatchStart.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    func toggleStopwatch(now: Date = Date()) {
        if stopwatchStart != nil { stopwatchElapsed = elapsed(at: now); stopwatchStart = nil }
        else { stopwatchStart = now }
    }
    func resetStopwatch() { stopwatchStart = nil; stopwatchElapsed = 0; laps = [] }
    func addBookmark(title: String, address: String) -> Bool {
        guard let url = Bookmark.url(address) else { status = "Enter an http or https website address."; return false }
        bookmarks.append(Bookmark(title: title.isEmpty ? url.host! : title, address: url.absoluteString)); status = nil; return true
    }
    func loadFolder(_ url: URL? = nil) {
        if let url { folder = url; folderQuery = "" }
        do {
            folderItems = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            status = nil
        } catch { folderItems = []; status = "This folder cannot be read. Choose another folder or grant access in System Settings." }
    }
    var sortedFolderItems: [URL] {
        folderItems.filter { folderQuery.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(folderQuery) }.sorted {
            if folderSort == "Newest" {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
    static func playChime() { NSSound(named: "Glass")?.play() }
    nonisolated static func interactiveCapture() -> Int32? { (try? SystemDock.run("/usr/sbin/screencapture", ["-i", "-c"]))?.0 }
    func chooseFolder() { let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; if let url = chooseDirectory(p) { loadFolder(url) } }
    func pickColor() {
        sampleColor { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
            Task { @MainActor in self?.colorHex = hex }
        }
    }
    func screenshot() {
        guard !busy else { return }; busy = true; status = "Select a region. Escape cancels. The image is copied to your clipboard."
        // Interactive system capture owns its own permission flow and cancellation UI.
        let capture = capture
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = capture()
            Task { @MainActor in self?.busy = false; self?.status = result == 0 ? "Capture finished. If you selected a region, paste the image with ⌘V." : "Capture cancelled or unavailable. Check Screen Recording permission." }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { try setLoginItem(enabled)
            loginEnabled = loginStatus() == .enabled
            status = loginStatus() == .requiresApproval ? "Approve DockGrove in System Settings > General > Login Items." : nil
        } catch { status = "Could not change login startup. Install DockGrove in Applications and try again." }
    }
    func loadReminders() {
        Task { @MainActor [self] in
            do {
                guard try await reminderStore.requestReminderAccess() else { remindersStatus = "Reminders permission was not granted."; return }
                reminderStore.incompleteReminders { [weak self] items in
                    Task { @MainActor in self?.reminders = (items ?? []).sorted { ($0.title ?? "") < ($1.title ?? "") }; self?.remindersStatus = "Incomplete reminders · Refresh to sync changes" }
                }
            } catch { remindersStatus = "Reminders are unavailable. Check permission in System Settings." }
        }
    }
    func completeReminder(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do { try reminderStore.saveReminder(reminder); reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier } }
        catch { reminder.isCompleted = false; remindersStatus = "Could not save this reminder. Refresh and try again." }
    }
}

/// Modal system pickers. Callers expose instance seams so tests never present them.
@MainActor enum SystemPicker {
    static func run(_ panel: NSOpenPanel) -> URL? { panel.runModal() == .OK ? panel.url : nil }
    static func sampleColor(_ handler: @escaping (NSColor?) -> Void) { NSColorSampler().show(selectionHandler: handler) }
}
/// The app's login item. `set` registers or unregisters DockGrove with macOS.
enum LoginService {
    static func status() -> SMAppService.Status { SMAppService.mainApp.status }
    static func set(_ enabled: Bool) throws { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
}

enum TestEnvironment {
    /// True inside an `xcodebuild test` host process.
    static let isXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
