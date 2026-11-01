import AppKit
import EventKit
import SwiftUI

/// EventKit reads and writes used by the calendar and reminder widgets. Tests use unsaved
/// fixture items through a fake, so no real calendar or reminder is read or changed.
protocol EventStoreAccess: AnyObject {
    func requestEventAccess() async throws -> Bool
    func requestReminderAccess() async throws -> Bool
    func eventsAuthorized() -> Bool
    func eventCalendars() -> [EKCalendar]
    func events(from start: Date, to end: Date, in calendars: [EKCalendar]) -> [EKEvent]
    func incompleteReminders(_ completion: @escaping ([EKReminder]?) -> Void)
    func saveReminder(_ reminder: EKReminder) throws
}
extension EKEventStore: EventStoreAccess {
    func requestEventAccess() async throws -> Bool { try await requestFullAccessToEvents() }
    func requestReminderAccess() async throws -> Bool { try await requestFullAccessToReminders() }
    func eventsAuthorized() -> Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func eventCalendars() -> [EKCalendar] { calendars(for: .event) }
    func events(from start: Date, to end: Date, in calendars: [EKCalendar]) -> [EKEvent] { events(matching: predicateForEvents(withStart: start, end: end, calendars: calendars)) }
    func incompleteReminders(_ completion: @escaping ([EKReminder]?) -> Void) { _ = fetchReminders(matching: predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil), completion: completion) }
    func saveReminder(_ reminder: EKReminder) throws { try save(reminder, commit: true) }
}
@MainActor final class CalendarWidget: ObservableObject {
    let eventStore = EKEventStore()
    let access: EventStoreAccess
    /// Opens system URLs and apps. Tests record the requested URL instead.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private let store: UserDefaults
    @Published var calendars: [EKCalendar] = []
    @Published var events: [EKEvent] = []
    @Published var selected: Set<String> { didSet { store.set(Array(selected), forKey: key); refreshIfAuthorized() } }
    @Published var status = "Connect to read calendars configured on this Mac."
    @Published var connected = false
    @Published var loading = false
    let google: Bool
    private let key: String
    private var observer: NSObjectProtocol?
    private(set) var timer: Timer?
    private var generation = 0
    init(store: UserDefaults, google: Bool = false, access: EventStoreAccess? = nil) {
        self.store = store; self.google = google
        self.access = access ?? eventStore
        key = google ? "googleCalendarSelection" : "calendarSelection"
        selected = Set(store.stringArray(forKey: key) ?? [])
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in Task { @MainActor in if self?.connected == true { self?.refreshIfAuthorized() } } }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in if self?.connected == true { self?.refreshIfAuthorized() } } }
    }
    deinit { timer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    func connect() {
        guard !loading else { return }; loading = true
        let requestID = generation
        Task { @MainActor in
            defer { if requestID == generation { loading = false } }
            do {
                let allowed = try await access.requestEventAccess()
                guard requestID == generation else { return }
                guard allowed else { disconnect(); status = "Calendar access was denied. Enable it in Privacy & Security > Calendars."; return }
                connected = true; refreshIfAuthorized(justAuthorized: true)
            } catch { guard requestID == generation else { return }; disconnect(); status = "Calendar access failed. Check macOS permissions and retry." }
        }
    }
    func disconnect() { generation += 1; loading = false; connected = false; events = []; calendars = []; status = "Disconnected." }
    func refreshIfAuthorized(justAuthorized: Bool = false) {
        guard connected else { return }
        guard justAuthorized || access.eventsAuthorized() else { disconnect(); status = "Calendar permission was removed. Connect again when ready."; return }
        calendars = access.eventCalendars().sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let chosen = calendars.filter { selected.contains($0.calendarIdentifier) }
        if selected.isEmpty && !google {
            // Empty selection means all calendars only for the general Calendar widget.
            load(calendars)
        } else if chosen.isEmpty {
            events = []; status = google ? "Select the calendars from your Google account below. Add the account in Internet Accounts if it is missing." : "Selected calendars are unavailable. Select another calendar."
        } else { load(chosen) }
    }
    private func load(_ calendars: [EKCalendar]) {
        guard !calendars.isEmpty else { events = []; status = "No calendars configured. Add an account in macOS Internet Accounts."; return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        events = access.events(from: now, to: end, in: calendars).sorted { $0.startDate < $1.startDate }
        status = events.isEmpty ? "No events in the next seven days." : "Next seven days · Syncs through macOS Calendar"
    }
    func select(_ calendar: EKCalendar, enabled: Bool) { if enabled { selected.insert(calendar.calendarIdentifier) } else { selected.remove(calendar.calendarIdentifier) } }
}
struct CalendarAgendaView: View {
    @Environment(\.connectionSetupAllowed) private var environmentSetupAllowed
    @ObservedObject var calendar: CalendarWidget
    /// Overrides the environment's setup permission so tests can drive both layouts directly.
    var setupAllowedOverride: Bool?
    private var setupAllowed: Bool { setupAllowedOverride ?? environmentSetupAllowed }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(calendar.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if setupAllowed {
                if calendar.google { Text("Add Google in Internet Accounts, then allow access and select calendars below.").font(.caption) }
                Toggle("Allow calendar access", isOn: Binding(get: { calendar.connected }, set: { $0 ? calendar.connect() : calendar.disconnect() })).disabled(calendar.loading)
                Button("Open Internet Accounts") { calendar.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!) }
            } else { ConnectionSettingsButton() }
            if calendar.connected { Button("Refresh", action: calendar.connect).disabled(calendar.loading) }
            if setupAllowed && !calendar.calendars.isEmpty {
                Text(calendar.google ? "Choose Google calendars" : "Choose calendars (none selected = all)").font(.caption.bold())
                ScrollView { VStack(alignment: .leading) { ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                    Toggle("\(item.source.title) · \(item.title)", isOn: Binding(get: { calendar.selected.contains(item.calendarIdentifier) }, set: { calendar.select(item, enabled: $0) }))
                } }}.frame(maxHeight: 110)
            }
            ScrollView { LazyVStack(alignment: .leading, spacing: 14) { ForEach(Array(calendar.events.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title ?? "Untitled event").font(.headline)
                    Text(event.isAllDay ? event.startDate.formatted(date: .abbreviated, time: .omitted) + " · All day" : event.startDate.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
                    if let url = event.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link("Open event link", destination: url) }
                }
            } }}.frame(maxHeight: 260)
            Button("Open Calendar") { calendar.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        }
    }
}
