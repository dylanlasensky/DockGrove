import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// The window list an app tile's Windows sheet reads; WindowManager is the live source.
@MainActor protocol AppWindowListing: ObservableObject {
    var windows: [ManagedWindow] { get }
    var status: String { get }
    var trusted: Bool { get }
    var selectedID: String { get set }
    func requestAccess()
    func refresh()
    func focus()
}
extension WindowManager: AppWindowListing {}

/// System work behind Dock tiles and windows, replaceable so tests never activate DockGrove,
/// open Finder or other apps, or hide or quit real applications.
@MainActor enum DockSystemEffect {
    case present(NSWindow)
    case open(URL)
    case reveal([URL])
    case openFiles([URL], application: URL, completion: (NSRunningApplication?, Error?) -> Void)
    case setHidden(NSRunningApplication, Bool)
    case terminate(NSRunningApplication)
    case forceTerminate(NSRunningApplication)
    static var handler: (DockSystemEffect) -> Void = DockSystemEffect.perform
    /// Keys held while a menu is built; Option turns Quit into Force Quit.
    static var modifiers: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    static func perform(_ effect: DockSystemEffect) {
        switch effect {
        case .present(let window): window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        case .open(let url): NSWorkspace.shared.open(url)
        case .reveal(let urls): NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .openFiles(let urls, let application, let completion):
            NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completion)
        case .setHidden(let app, let hidden): if hidden { app.hide() } else { app.unhide() }
        case .terminate(let app): app.terminate()
        case .forceTerminate(let app): app.forceTerminate()
        }
    }
}

struct AppWindowsView<Manager: AppWindowListing>: View {
    @ObservedObject var manager: Manager
    let app: DockApp
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(app.name) windows").font(.headline)
            Text(manager.status).font(.caption)
            if !manager.trusted { Button("Allow Accessibility", action: manager.requestAccess) }
            Button("Refresh", action: manager.refresh)
            List(manager.windows.filter { $0.owner.bundleURL?.standardizedFileURL.path == app.id }) { window in
                Button(window.title + (window.isMinimized ? " — Minimized" : "")) { manager.selectedID = window.id; manager.focus() }
            }.frame(height: 240)
            Text("Choose a window to restore and bring it forward.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 440).onAppear { manager.refresh() }
    }
}
extension ManagedWindow {
    /// The window's own title, without the owning app's name that the Windows widget leads with.
    var menuTitle: String {
        let prefix = WindowManager.windowTitle(app: owner.localizedName, window: "", fallback: "")
        return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }
}
extension DockModel {
    func runningApplication(_ app: DockApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == app.id }
    }
    func showAppWindows(_ app: DockApp) {
        guard canUseFeatures else { settingsAction?(); return }
        appPickerWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "App windows"
        window.contentView = NSHostingView(rootView: AppWindowsView(manager: toolkit.windows, app: app).preferredColorScheme(scheme))
        appPickerWindow = window; window.center(); DockSystemEffect.handler(.present(window))
    }
    func acceptFiles(_ providers: [NSItemProvider], for app: DockApp) -> Bool {
        guard canUseFeatures else { return false }
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }
        for provider in supported {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    guard self.canUseFeatures else { return }
                    DockSystemEffect.handler(.openFiles([url], application: app.url) { _, error in
                        if error != nil { Task { @MainActor in self.systemError = "This app could not open the dropped file." } }
                    })
                }
            }
        }
        return true
    }
}

/// A stable system control outside paged and removable Dock content.
struct WindowShelfButton: View {
    @ObservedObject var manager: WindowManager
    var enabled: Bool
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "cube.transparent")
                .font(.system(size: 22)).frame(width: 40, height: 46)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!enabled)
        .help("Open and minimized windows")
        .accessibilityLabel("Open and minimized windows")
        .popover(isPresented: $presented) {
            WindowShelfView(manager: manager) { presented = false }
        }
    }
}

enum WindowShelfFilter: String, CaseIterable {
    case all = "All", minimized = "Minimized", open = "Open"
    func includes(_ window: ManagedWindow) -> Bool {
        self == .all || (self == .minimized ? window.isMinimized : !window.isMinimized)
    }
}

struct WindowShelfView: View {
    @ObservedObject var manager: WindowManager
    var dismiss: () -> Void
    @State private var query = ""
    @State private var filter = WindowShelfFilter.all
    private let clock = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    var matches: [ManagedWindow] {
        manager.windows.filter { filter.includes($0) && (query.isEmpty || $0.title.localizedStandardContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your windows").font(.headline)
                Spacer()
                Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh windows").accessibilityLabel("Refresh windows").disabled(manager.loading)
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
            }
            if !manager.trusted {
                Text("Allow Accessibility to find and restore windows from your apps.").foregroundStyle(.secondary)
                Button("Allow Accessibility", action: manager.requestAccess)
                Text(manager.status).font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Search apps or window titles", text: $query)
                Picker("Show windows", selection: $filter) {
                    ForEach(WindowShelfFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if matches.isEmpty {
                    ContentUnavailableView(manager.loading ? "Finding windows…" : "No matching windows", systemImage: "macwindow", description: Text(query.isEmpty ? "Open an app window or choose another filter." : "Try a different app or window title."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(matches) { window in
                                Button {
                                    manager.selectedID = window.id
                                    manager.focus()
                                    if manager.status == "Window brought forward." { dismiss() }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: window.owner.icon ?? NSImage()).resizable().frame(width: 30, height: 30)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(window.menuTitle).lineLimit(1)
                                            Text(window.owner.localizedName ?? "App").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: window.isMinimized ? "minus.square" : "macwindow").foregroundStyle(.secondary)
                                        Text(window.isMinimized ? "Minimized" : "Open").font(.caption).foregroundStyle(.secondary)
                                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                                .contextMenu {
                                    Button(window.isMinimized ? "Restore window" : "Bring forward") { manager.selectedID = window.id; manager.focus() }
                                    if !window.isMinimized { Button("Minimize window") { manager.selectedID = window.id; manager.minimize(); manager.refresh() } }
                                }.accessibilityLabel("\(window.title), \(window.isMinimized ? "minimized" : "open"). Restore window")
                            }
                        }
                    }.frame(maxHeight: 320)
                }
                Text("Browser tabs appear under their containing window.").font(.caption).foregroundStyle(.secondary)
                Text(manager.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }.padding(18).frame(width: 420)
        .onAppear { manager.refresh() }
        .onReceive(clock) { _ in manager.refresh() }
    }
}
