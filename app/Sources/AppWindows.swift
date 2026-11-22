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
    @discardableResult func focus() async -> Bool
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
    static var runningApplications: () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }
    static func perform(_ effect: DockSystemEffect) {
        switch effect {
        case .present(let window): window.deminiaturize(nil); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
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
                Button(window.title + (window.isMinimized ? " — Minimized" : "")) { manager.selectedID = window.id; Task { await manager.focus() } }
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
        DockSystemEffect.runningApplications().first { $0.bundleURL?.standardizedFileURL.path == app.id }
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
    var body: some View {
        Button { manager.showOverview() } label: {
            Image(systemName: "cube.transparent")
                .font(.system(size: 22)).frame(width: 40, height: 46)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!enabled)
        .help("Open and minimized windows")
        .accessibilityLabel("Open and minimized windows")
    }
}

private final class WindowOverviewWindow: NSWindow {
    var onClose: (() -> Void)?
    func fit(in visibleFrame: NSRect, centered: Bool) {
        let available = visibleFrame.insetBy(dx: 16, dy: 16)
        let size = NSSize(width: min(frame.width, available.width), height: min(frame.height, available.height))
        minSize = NSSize(width: min(620, available.width), height: min(440, available.height))
        let origin = centered
            ? NSPoint(x: available.midX - size.width / 2, y: available.midY - size.height / 2)
            : NSPoint(x: min(max(frame.minX, available.minX), available.maxX - size.width), y: min(max(frame.minY, available.minY), available.maxY - size.height))
        setFrame(NSRect(origin: origin, size: size), display: false)
    }
    override func close() {
        onClose?()
        contentView = nil
        super.close()
    }
}

extension WindowManager {
    func showOverview(visibleFrame: NSRect? = nil) {
        let visibleFrame = visibleFrame ?? NSScreen.main?.visibleFrame
        if let overviewWindow {
            overviewWindow.deminiaturize(nil)
            if let visibleFrame, !overviewWindow.styleMask.contains(.fullScreen) { (overviewWindow as? WindowOverviewWindow)?.fit(in: visibleFrame, centered: false) }
            DockSystemEffect.handler(.present(overviewWindow)); refresh(); return
        }
        // A real key window, rather than a popover on a nonactivating Dock panel, lets
        // search always accept typing and gives the overview room to grow.
        let window = WindowOverviewWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Your windows"
        window.minSize = NSSize(width: 620, height: 440)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        let host = NSHostingView(rootView: WindowShelfView(manager: self) { [weak window] in window?.close() })
        // AppKit owns the resizable viewport. A growing list must not turn SwiftUI's
        // ideal content height into an offscreen window frame.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.onClose = { [weak self] in self?.cancelDiscovery(); self?.overviewWindow = nil }
        overviewWindow = window
        window.center()
        if let visibleFrame { window.fit(in: visibleFrame, centered: true) }
        DockSystemEffect.handler(.present(window))
    }
}

enum WindowShelfFilter: String, CaseIterable {
    case all = "All", minimized = "Minimized", open = "Open"
    func includes(_ window: ManagedWindow) -> Bool {
        self == .all || (self == .minimized ? window.isMinimized : !window.isMinimized)
    }
}

struct WindowShelfGroup: Identifiable {
    let id: pid_t
    let name: String
    let windows: [ManagedWindow]
    static func make(from windows: [ManagedWindow]) -> [WindowShelfGroup] {
        Dictionary(grouping: windows, by: { $0.owner.processIdentifier }).map { pid, windows in
            WindowShelfGroup(id: pid, name: windows.first?.owner.localizedName ?? "App", windows: windows.sorted { $0.menuTitle.localizedStandardCompare($1.menuTitle) == .orderedAscending })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct WindowShelfView: View {
    @ObservedObject var manager: WindowManager
    var refreshEvents: AnyPublisher<Date, Never> = Timer.publish(every: 3, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
    var dismiss: () -> Void
    @State private var query = ""
    @State private var filter = WindowShelfFilter.all
    @FocusState private var searchFocused: Bool
    var matches: [ManagedWindow] {
        let search = AppSearchIndex.fold(query)
        return manager.windows.filter { filter.includes($0) && (search.isEmpty || AppSearchIndex.fold($0.title).contains(search)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your windows").font(.system(size: 27, weight: .bold))
                    Text("Pick up where you left off.").foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                    DockSystemEffect.handler(.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")))
                } label: { Label("Mission Control", systemImage: "rectangle.3.group") }
                    .help("Show live window previews with macOS Mission Control")
                    .accessibilityLabel("Mission Control")
                if manager.loading { ProgressView().controlSize(.small).accessibilityLabel("Finding windows") }
                Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh windows").accessibilityLabel("Refresh windows").disabled(manager.loading || manager.acting)
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
            }
            if !manager.trusted {
                VStack(spacing: 14) {
                    Image(systemName: "macwindow.badge.plus").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("Bring all your windows together").font(.title2.weight(.semibold))
                    Text("Allow Accessibility to find, minimize and restore windows from your apps.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Allow Accessibility", action: manager.requestAccess).buttonStyle(.borderedProminent)
                    Text(manager.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Already allowed access? macOS may need you to enable it again for this installed build.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
            } else {
                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search apps or window titles", text: $query).textFieldStyle(.plain)
                            .focused($searchFocused)
                            .onSubmit { if let first = WindowShelfGroup.make(from: matches).first?.windows.first { restore(first) } }
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    Picker("Show windows", selection: $filter) {
                        ForEach(WindowShelfFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Show windows").frame(width: 230)
                }
                if matches.isEmpty {
                    ContentUnavailableView(manager.loading ? "Finding windows…" : "No matching windows", systemImage: "macwindow", description: Text(query.isEmpty ? "Open an app window or choose another filter." : "Try a different app or window title."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(WindowShelfGroup.make(from: matches)) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 7) {
                                        Text(group.name).font(.headline)
                                        Text("\(group.windows.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    }
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 178, maximum: 280), spacing: 12)], spacing: 12) {
                                        ForEach(group.windows) { window in
                                            Button { restore(window) } label: { WindowShelfCard(window: window) }
                                                .buttonStyle(.plain).disabled(manager.acting)
                                                .contextMenu { WindowShelfActions(manager: manager, window: window) }
                                                .accessibilityLabel("\(window.title), \(window.isMinimized ? "minimized" : "open"). Restore window")
                                        }
                                    }
                                }
                            }
                        }.padding(2)
                    }.frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
                HStack(alignment: .top, spacing: 16) {
                    Text(manager.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Spacer(minLength: 0)
                    Text("\(matches.count) \(matches.count == 1 ? "window" : "windows")")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                }
                Text("Browser tabs stay inside their browser window. This overview shows app windows, including minimized ones.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { manager.refresh(); searchFocused = true }
        .onReceive(refreshEvents) { _ in
            if let window = manager.overviewWindow {
                guard window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) else { return }
            }
            manager.refresh()
        }
        .onDisappear { manager.cancelDiscovery() }
    }
    private func restore(_ window: ManagedWindow) {
        manager.selectedID = window.id
        Task { if await manager.focus() { dismiss() } }
    }
}

private struct WindowShelfCard: View {
    let window: ManagedWindow
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: window.owner.icon ?? NSImage()).resizable().frame(width: 34, height: 34)
                Spacer()
                Image(systemName: window.isMinimized ? "minus.square" : "macwindow")
                    .foregroundStyle(window.isMinimized ? Color.secondary : Color.accentColor)
            }
            Text(window.menuTitle).font(.system(size: 13, weight: .medium)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            HStack(spacing: 5) {
                Circle().fill(window.isMinimized ? Color.secondary : Color.accentColor).frame(width: 5, height: 5)
                Text(window.isMinimized ? "Minimized" : "Open").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hovering ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onHover { hovering = $0 }
    }
}

/// Shared menu controls can be exercised without opening a system menu or touching real windows.
struct WindowShelfActions: View {
    @ObservedObject var manager: WindowManager
    let window: ManagedWindow
    var body: some View {
        Group {
            Button(window.isMinimized ? "Restore window" : "Bring forward") {
                manager.selectedID = window.id
                Task { await manager.focus() }
            }
            if !window.isMinimized {
                Button("Minimize window") {
                    manager.selectedID = window.id
                    Task { await manager.minimize() }
                }
            }
        }.disabled(manager.acting)
    }
}
