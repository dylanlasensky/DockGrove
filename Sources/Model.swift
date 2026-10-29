import AppKit
import SwiftUI
import Combine

struct DockApp: Identifiable, Equatable {
    let url: URL
    var id: String { url.path }
    var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var isRunning: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL } }
}

@MainActor final class DockModel: ObservableObject {
    @Published var apps: [DockApp] = []
    @Published var iconSize: Double { didSet { defaults.set(iconSize, forKey: "iconSize") } }
    @Published var accent: String { didSet { defaults.set(accent, forKey: "accent") } }
    @Published var showClock: Bool { didSet { defaults.set(showClock, forKey: "showClock") } }
    @Published var usageEnabled: Bool { didSet { defaults.set(usageEnabled, forKey: "usageEnabled") } }
    @Published var customCLI: String { didSet { defaults.set(customCLI, forKey: "customCLI") } }
    @Published var selectedBucket: String { didSet { defaults.set(selectedBucket, forKey: "selectedBucket") } }
    @Published var usage: UsageResponse?
    @Published var usageError: String?
    @Published var fetching = false
    @Published var refreshed: Date?
    @Published var replacingDock = false
    @Published var visible = true { didSet { defaults.set(visible, forKey: "dockVisible") } }
    @Published var dockName: String { didSet { defaults.set(String(dockName.prefix(40)), forKey: "dockName") } }
    @Published var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    @Published var widthFraction: Double { didSet { defaults.set(widthFraction, forKey: "widthFraction") } }
    @Published var alignment: Double { didSet { defaults.set(alignment, forKey: "alignment") } }
    @Published var elevation: Double { didSet { defaults.set(elevation, forKey: "elevation") } }
    @Published var albumColors: Bool { didSet { defaults.set(albumColors, forKey: "albumColors") } }
    @Published var showUsageCard: Bool { didSet { defaults.set(showUsageCard, forKey: "showUsageCard") } }
    @Published var snappingEnabled: Bool { didSet { defaults.set(snappingEnabled, forKey: "snappingEnabled") } }
    @Published var snapRequiresOption: Bool { didSet { defaults.set(snapRequiresOption, forKey: "snapRequiresOption") } }
    var isAdditionalDock = false
    var manageDocksAction: (() -> Void)?
    var screenID: String { get { defaults.string(forKey: "screenID") ?? "" } set { defaults.set(newValue, forKey: "screenID") } }
    var selectedScreen: NSScreen? {
        if let found = NSScreen.screens.first(where: { Self.displayID($0) == screenID }) { return found }
        return NSScreen.screens.isEmpty ? nil : NSScreen.screens[min(max(0, toolkit.screenIndex), NSScreen.screens.count-1)]
    }
    static func displayID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return screen.localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }
    var scheme: ColorScheme? { theme == "System" ? nil : theme == "Pearl" ? .light : .dark }

    @Published var systemError: String?
    let toolkit: Toolkit
    let defaults: UserDefaults
    var settingsAction: (() -> Void)?
    var closeSettingsAction: (() -> Void)?
    var changeDockAction: ((Bool) -> Void)?
    var visibilityAction: (() -> Void)?
    private var timer: Timer?
    private var observations: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dockName = defaults.string(forKey: "dockName") ?? "Main Dock"
        theme = defaults.string(forKey: "theme") ?? "Glass"
        widthFraction = min(1,max(0.35,defaults.object(forKey: "widthFraction") as? Double ?? 1))
        alignment = min(1,max(0,defaults.object(forKey: "alignment") as? Double ?? 0.5))
        elevation = min(1,max(0,defaults.object(forKey: "elevation") as? Double ?? 0.5))
        albumColors = defaults.object(forKey: "albumColors") as? Bool ?? true
        showUsageCard = defaults.object(forKey: "showUsageCard") as? Bool ?? true
        snappingEnabled = defaults.bool(forKey: "snappingEnabled")
        snapRequiresOption = defaults.object(forKey: "snapRequiresOption") as? Bool ?? true
        visible = defaults.object(forKey: "dockVisible") as? Bool ?? true
        toolkit = Toolkit(store: defaults)
        defaults.register(defaults: ["iconSize": 48.0, "accent": "White", "showClock": true, "usageEnabled": false])
        iconSize = defaults.double(forKey: "iconSize")
        accent = defaults.string(forKey: "accent") ?? "White"
        showClock = defaults.bool(forKey: "showClock")
        usageEnabled = defaults.bool(forKey: "usageEnabled")
        customCLI = defaults.string(forKey: "customCLI") ?? ""
        selectedBucket = defaults.string(forKey: "selectedBucket") ?? "codex"
        if let paths = defaults.stringArray(forKey: "apps") {
            apps = paths.map { DockApp(url: URL(fileURLWithPath: $0)) }.filter { FileManager.default.fileExists(atPath: $0.id) }
        } else {
            let paths = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Messages.app", "/Applications/Spotify.app", "/Applications/ChatGPT.app", "/System/Applications/System Settings.app"]
            apps = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { DockApp(url: URL(fileURLWithPath: $0)) }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.objectWillChange.send() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in if self?.usageEnabled == true { self?.refreshUsage() } }
        }
        if usageEnabled { refreshUsage() }
    }

    deinit {
        timer?.invalidate()
        for observation in observations { NSWorkspace.shared.notificationCenter.removeObserver(observation) }
    }

    var dockHeight: Double { max(64, iconSize + 20) + 44 }
    var color: Color { (theme == "Pearl" || theme == "System") && accent == "White" ? .primary : AccentPalette.color(accent) }
    var activeBucket: LimitBucket? { usage?.buckets.first { $0.0 == selectedBucket }?.1 ?? usage?.buckets.first?.1 }
    func persistApps() { defaults.set(apps.map(\.id), forKey: "apps") }
    func open(_ app: DockApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, _ in }
    }
    func addApps() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.title = "Pin apps to WaveDock"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.allowedContentTypes = [.applicationBundle]
        if picker.runModal() == .OK {
            for url in picker.urls where !apps.contains(where: { $0.url == url }) { apps.append(DockApp(url: url)) }
            persistApps()
        }
    }
    func remove(_ app: DockApp) { apps.removeAll { $0.id == app.id }; persistApps() }
    func move(_ app: DockApp, by offset: Int) {
        guard let index = apps.firstIndex(of: app), apps.indices.contains(index + offset) else { return }
        apps.swapAt(index, index + offset); persistApps()
    }
    var runningApps: [DockApp] {
        guard toolkit.showRunning else { return [] }
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { $0.bundleURL.map { DockApp(url: $0) } }.filter { !apps.contains($0) && $0.url.lastPathComponent != "WaveDock.app" }
    }
    func pin(_ app: DockApp) { if !apps.contains(app) { apps.append(app); persistApps() } }
    func reorder(_ path: String, before target: DockApp) {
        guard let origin = apps.firstIndex(where: { $0.id == path }), let dest = apps.firstIndex(of: target), origin != dest else { return }
        let item = apps.remove(at: origin); apps.insert(item, at: origin < dest ? dest - 1 : dest); persistApps()
    }
    func saveProfile() {
        let name = toolkit.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        toolkit.profiles.append(DockProfile(name: name, apps: apps.map(\.id), widgets: toolkit.enabled, accent: accent, size: iconSize, richWidgets: toolkit.richWidgets, theme: theme, widthFraction: widthFraction, alignment: alignment, elevation: elevation, edge: toolkit.edge, albumColors: albumColors)); toolkit.profileName = ""
    }
    func applyProfile(_ profile: DockProfile) {
        if let value=profile.theme, ["Glass","Graphite","Pearl","System"].contains(value) { theme=value }
        if let value=profile.widthFraction,value.isFinite { widthFraction=min(1,max(0.35,value)) }
        if let value=profile.alignment,value.isFinite { alignment=min(1,max(0,value)) }
        if let value=profile.elevation,value.isFinite { elevation=min(1,max(0,value)) }
        if let value=profile.edge,["Top","Bottom","Floating"].contains(value), !replacingDock { toolkit.edge=value }
        if let value=profile.albumColors { albumColors=value }
        if let rich = profile.richWidgets { toolkit.richWidgets = rich }
        var seen = Set<String>()
        apps = profile.apps.filter { seen.insert($0).inserted && FileManager.default.fileExists(atPath: $0) && $0.hasSuffix(".app") }.map { DockApp(url: URL(fileURLWithPath: $0)) }
        seen.removeAll()
        toolkit.enabled = profile.widgets.filter { ToolKind(rawValue: $0) != nil && seen.insert($0).inserted }; accent = profile.accent; iconSize = max(32, min(64, profile.size)); persistApps()
    }
    func exportProfiles() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "WaveDock-layouts.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try JSONEncoder().encode(toolkit.profiles).write(to: url, options: .atomic) } catch { systemError = "Could not export layouts." }
        }
    }
    func importProfiles() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = attributes[.size] as? NSNumber, size.intValue <= 1_000_000 else { throw UsageError.service }
                let data = try Data(contentsOf: url); guard data.count <= 1_000_000 else { throw UsageError.service }
                let imported = try JSONDecoder().decode([DockProfile].self, from: data)
                for var profile in imported.prefix(100) { profile.id = UUID(); toolkit.profiles.append(profile) }
            } catch { systemError = "This file is not a valid WaveDock layout export." }
        }
    }
    func refreshUsage() {
        guard !fetching else { return }
        fetching = true
        let custom = customCLI
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try UsageClient.fetch(custom: custom) }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.fetching = false
                switch result {
                case .success(let response): self.usage = response; self.refreshed = Date(); self.usageError = nil
                case .failure(let error): self.usageError = (error as? UsageError)?.localizedDescription ?? "Could not read usage. Check your Codex connection in Settings."
                }
            }
        }
    }
}
