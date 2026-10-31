import SwiftUI
import AppKit

extension DockEntry {
    static let applicationsID = "applications"
}

extension DockModel {
    /// The Applications stack always leads the Dock; it sits outside `entryOrder` so it cannot be reordered away.
    var dockEntries: [DockEntry] { (showApplicationsStack ? [.applications] : []) + orderedEntries }
}

struct ApplicationsStackTile: View {
    @ObservedObject var model: DockModel
    @StateObject private var interaction = TileInteraction()
    private static let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    var body: some View {
        VStack(spacing: 4) {
            Button { AppsLauncher.shared.toggle(model: model) } label: {
                Image(nsImage: Self.folderIcon).resizable().interpolation(.high).frame(width: model.iconSize, height: model.iconSize)
                    .scaleEffect(interaction.hovered ? 1.13 : 1).offset(y: interaction.hovered ? -4 : 0)
            }.buttonStyle(.plain).help("Applications").accessibilityLabel("Applications")
            Circle().fill(.clear).frame(width: 4, height: 4)
        }
        .onHover { interaction.hovered = $0 }
        .animation(.spring(response: 0.23, dampingFraction: 0.65), value: interaction.hovered)
        .contextMenu {
            Button("Open Applications Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
            Button("Refresh Applications") { model.toolkit.scanApplications(force: true) }
        }
    }
}

/// Full-screen app browser modelled on the macOS Apps app: blurred desktop, centred search, paged icon grid.
@MainActor final class AppsLauncher {
    static let shared = AppsLauncher()
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { AppsLauncher.shared.close() }
    }
    private(set) var panel: NSPanel?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    let pager = AppsPager()

    func toggle(model: DockModel) { panel == nil ? show(model: model) : close() }

    func show(model: DockModel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let panel = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        pager.page = 0
        let root = AppsLauncherView(model: model, kit: model.toolkit, pager: pager) { [weak self] in self?.close() }
            .preferredColorScheme(model.scheme)
        panel.contentView = NSHostingView(rootView: root)
        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        self.panel = panel
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.pager.scroll(event); return nil
        } as Any)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { AppsLauncher.shared.close() }
        }
        model.toolkit.scanApplications(force: true)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil); panel.contentView = nil }
        }
    }
}

/// Current page plus trackpad/wheel paging, shared by the launcher window and its view.
@MainActor final class AppsPager: ObservableObject {
    @Published var page = 0
    var count = 1
    private var travel: CGFloat = 0
    private var turnedThisGesture = false

    func go(_ target: Int) { withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { page = max(0, min(count - 1, target)) } }

    func scroll(_ event: NSEvent) {
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty && !event.hasPreciseScrollingDeltas) {
            travel = 0; turnedThisGesture = false
        }
        guard event.momentumPhase.isEmpty, !turnedThisGesture else { return }
        let horizontal = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
        travel += horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 60 : 1
        guard abs(travel) >= threshold else { return }
        go(page + (travel < 0 ? 1 : -1))
        turnedThisGesture = event.hasPreciseScrollingDeltas
        travel = 0
    }
}

private struct LauncherBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct AppsLauncherView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var pager: AppsPager
    var close: () -> Void
    @State private var query = ""
    @State private var shown = false
    @State private var drag: CGFloat = 0
    @FocusState private var searchFocused: Bool
    static let columns = 7, rows = 5
    private var results: [DockApp] { kit.appIndex.search(query) }
    private var pages: [[DockApp]] {
        let perPage = Self.columns * Self.rows, all = results
        return all.isEmpty ? [[]] : stride(from: 0, to: all.count, by: perPage).map { Array(all[$0..<min($0 + perPage, all.count)]) }
    }

    var body: some View {
        let pages = pages
        ZStack {
            LauncherBackdrop().ignoresSafeArea()
            Color.black.opacity(0.12).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .gesture(DragGesture(minimumDistance: 16).onChanged { drag = $0.translation.width }.onEnded(finishDrag))
            VStack(spacing: 0) {
                searchField.padding(.top, 54)
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            page(pages[index], first: index == 0, in: geo.size).frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .offset(x: -CGFloat(pager.page) * geo.size.width + drag)
                }
                .clipped()
                .overlay { emptyState }
                dots(count: pages.count).padding(.bottom, 44)
            }
            .scaleEffect(shown ? 1 : 1.06).opacity(shown ? 1 : 0)
        }
        .onAppear {
            pager.count = pages.count
            searchFocused = true
            withAnimation(.easeOut(duration: 0.22)) { shown = true }
        }
        .onChange(of: query) { pager.page = 0 }
        .onChange(of: pages.count) { _, count in pager.count = count; if pager.page >= count { pager.page = max(0, count - 1) } }
        .onKeyPress(.leftArrow) { guard query.isEmpty else { return .ignored }; pager.go(pager.page - 1); return .handled }
        .onKeyPress(.rightArrow) { guard query.isEmpty else { return .ignored }; pager.go(pager.page + 1); return .handled }
        .onExitCommand(perform: close)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $query).textFieldStyle(.plain).focused($searchFocused)
                .onSubmit { if let first = results.first { launch(first) } }
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search").help("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).frame(width: 260, height: 30)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
    }

    private func page(_ apps: [DockApp], first: Bool, in size: CGSize) -> some View {
        let cellWidth = min(170, (size.width - 160) / CGFloat(Self.columns))
        let cellHeight = min(150, size.height / CGFloat(Self.rows))
        let icon = min(96, cellWidth * 0.64, cellHeight * 0.66)
        let grid = Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: Self.columns)
        return LazyVGrid(columns: grid, spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { offset, app in
                AppsLauncherIcon(app: app, name: kit.appIndex.name(of: app), iconSize: icon,
                                 highlighted: first && offset == 0 && !query.isEmpty,
                                 pinned: model.apps.contains(app),
                                 launch: { launch(app) }, pin: { model.pin(app) })
                    .frame(width: cellWidth, height: cellHeight)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 28)
    }

    @ViewBuilder private func dots(count: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                Button { pager.go(index) } label: {
                    Circle().fill(Color.primary.opacity(index == pager.page ? 0.85 : 0.28)).frame(width: 7, height: 7)
                        .padding(4).contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("Page \(index + 1) of \(count)")
            }
        }
        .frame(height: 16)
        .opacity(count > 1 ? 1 : 0)
    }

    @ViewBuilder private var emptyState: some View {
        if results.isEmpty {
            Group {
                if kit.scanningApps && kit.appIndex.count == 0 { ProgressView("Finding installed applications…") }
                else { Text(query.isEmpty ? "No applications found" : "No Results").font(.title2.weight(.medium)).foregroundStyle(.secondary) }
            }.allowsHitTesting(false)
        }
    }

    private func finishDrag(_ value: DragGesture.Value) {
        let threshold: CGFloat = 120
        if value.predictedEndTranslation.width < -threshold { pager.go(pager.page + 1) }
        else if value.predictedEndTranslation.width > threshold { pager.go(pager.page - 1) }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { drag = 0 }
    }

    private func launch(_ app: DockApp) { kit.recordLaunch(app, query: query); model.open(app); close() }
}

private struct AppsLauncherIcon: View {
    let app: DockApp
    let name: String
    let iconSize: CGFloat
    let highlighted: Bool
    let pinned: Bool
    let launch: () -> Void
    let pin: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: launch) {
            VStack(spacing: 8) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(highlighted ? 0.14 : hovered ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(app.id)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contextMenu {
            Button("Open", action: launch)
            Button("Keep in Dock", action: pin).disabled(pinned)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1).animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
