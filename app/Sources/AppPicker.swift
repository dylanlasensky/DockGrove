import SwiftUI
import AppKit
import Combine

struct AppPickerView: View {
    @ObservedObject var model: DockModel
    @State private var query = ""
    @State private var selected: String?
    @State private var catalog: [DockApp] = []
    @State private var scanning = false
    @FocusState private var searchFocused: Bool
    static var refreshInterval: TimeInterval = 10
    private let refreshTimer: Publishers.Autoconnect<Timer.TimerPublisher>
    var replacing: DockApp?
    var close: () -> Void
    init(model: DockModel, replacing: DockApp? = nil, close: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        self.replacing = replacing
        self.close = close
        refreshTimer = Timer.publish(every: Self.refreshInterval, on: .main, in: .common).autoconnect()
    }
    var results: [DockApp] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }.sorted {
            let a = $0.name.localizedCaseInsensitiveCompare(search) == .orderedSame
            let b = $1.name.localizedCaseInsensitiveCompare(search) == .orderedSame
            if a != b { return a }
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(replacing.map { "Replace \($0.name)" } ?? "Add an app").font(.title2.bold())
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by application name or path", text: $query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                if !query.isEmpty {
                    Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
                }
            }
            List(selection: $selected) {
                ForEach(results) { app in
                    HStack {
                        Image(nsImage: app.icon).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading) { Text(app.name); Text(app.id).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if model.apps.contains(app) { Text("Pinned").font(.caption).foregroundStyle(.secondary) }
                    }.tag(app.id)
                }
            }.frame(minHeight: 280)
                .overlay {
                    if results.isEmpty {
                        VStack(spacing: 8) {
                            if scanning && catalog.isEmpty {
                                ProgressView("Finding installed applications…")
                            } else {
                                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                                Text(query.isEmpty ? "No applications found" : "No matching applications").font(.headline)
                                Text(query.isEmpty ? "Install an application, then choose Refresh." : "Try another name or clear your search.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }.allowsHitTesting(false)
                    }
                }
            if let error = model.systemError { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Refresh", action: refresh).disabled(scanning)
                if scanning { ProgressView().controlSize(.small).accessibilityLabel("Refreshing applications") }
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button(replacing == nil ? "Add" : "Replace") {
                    guard let app = results.first(where: { $0.id == selected }) else { return }
                    if model.chooseApp(app, replacing: replacing) { close() }
                }.keyboardShortcut(.defaultAction).disabled(!results.contains(where: { $0.id == selected }))
            }
        }.padding(20).frame(width: 560).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(model.scheme)
        .onAppear { refresh(); searchFocused = true }
        .onChange(of: query) {
            if !results.contains(where: { $0.id == selected }) { selected = nil }
            model.systemError = nil
        }
        .onReceive(model.toolkit.$scanningApps) { scanning = $0 }
        .onReceive(model.toolkit.$applications) { values in
            catalog = values
            if !values.contains(where: { $0.id == selected }) { selected = nil }
        }
        .onReceive(refreshTimer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        model.toolkit.scanApplications(force: true)
        catalog = model.toolkit.applications
        if !catalog.contains(where: { $0.id == selected }) { selected = nil }
    }
}

extension DockModel {
    func showAppPicker(replacing: DockApp? = nil) {
        guard canUseFeatures else { settingsAction?(); return }
        systemError = nil
        appPickerWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Choose an application"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppPickerView(model: self, replacing: replacing, close: { [weak window] in window?.close() }))
        appPickerWindow = window
        window.center(); DockSystemEffect.handler(.present(window))
    }
    func rememberApps() { appHistory.append((apps, entryOrder)); if appHistory.count > 20 { appHistory.removeFirst() } }
    func undoAppChange() {
        guard let previous = appHistory.popLast() else { return }
        apps = previous.0; entryOrder = previous.1; persistApps()
    }
    @discardableResult func chooseApp(_ app: DockApp, replacing old: DockApp?) -> Bool {
        guard canUseFeatures else { systemError = "Activate DockGrove to change apps."; return false }
        guard FileManager.default.fileExists(atPath: app.id), app.url.pathExtension == "app" else { systemError = "This application is no longer installed. Refresh the list."; return false }
        guard !apps.contains(app) else { systemError = "That application is already pinned. Choose another app or cancel."; return false }
        if let old {
            guard let index = apps.firstIndex(of: old) else { systemError = "The original tile changed. Close this picker and try again."; return false }
            rememberApps()
            let order = orderedEntries.map(\.id)
            apps[index] = app
            entryOrder = order.map { $0 == "app:" + old.id ? "app:" + app.id : $0 }
        } else { rememberApps(); apps.append(app) }
        persistApps(); systemError = nil; return true
    }
}
