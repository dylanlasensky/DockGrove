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
    @StateObject private var anchor = StackAnchor()
    private static let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    var body: some View {
        VStack(spacing: 4) {
            Button { AppsStackPopover.shared.toggle(model: model, anchor: anchor.screenRect) } label: {
                face.frame(width: model.iconSize, height: model.iconSize)
                    .background(StackAnchorView(anchor: anchor))
                    .scaleEffect(interaction.hovered ? 1.13 : 1).offset(y: interaction.hovered ? -4 : 0)
            }.buttonStyle(.plain).help("Applications").accessibilityLabel("Applications")
            Circle().fill(.clear).frame(width: 4, height: 4)
        }
        .onHover { interaction.hovered = $0 }
        .animation(.spring(response: 0.23, dampingFraction: 0.65), value: interaction.hovered)
        .contextMenu { ApplicationsStackMenu(model: model) }
    }
    /// Display as Folder shows the folder icon; Stack piles up the first apps in the chosen sort order.
    @ViewBuilder private var face: some View {
        let top = model.stackDisplay == .stack ? model.stackPreview(count: 3) : []
        if top.isEmpty {
            Image(nsImage: Self.folderIcon).resizable().interpolation(.high)
        } else {
            ZStack {
                ForEach(Array(top.enumerated().reversed()), id: \.element.id) { index, app in
                    Image(nsImage: app.icon).resizable().interpolation(.high)
                        .scaleEffect(1 - CGFloat(index) * 0.08).offset(y: CGFloat(index) * -3)
                }
            }
        }
    }
}

extension DockModel {
    /// The stack's first apps in `stackSort` order, cached until the order or the app index changes.
    func stackPreview(count: Int) -> [DockApp] {
        let apps = toolkit.appIndex.apps
        let key = [stackSort.rawValue, String(count), String(apps.count), String(describing: apps.first?.id), String(describing: apps.last?.id)].joined(separator: "|")
        if let cache = stackPreviewCache, cache.key == key { return cache.apps }
        let top = stackSort.sorted(apps.map(\.url)).prefix(count).map(DockApp.init(url:))
        stackPreviewCache = (key, top)
        return top
    }
}

/// The Mac Dock's folder menu for the Applications stack, then DockGrove's extras.
struct ApplicationsStackMenu: View {
    @ObservedObject var model: DockModel
    private static let folder = URL(fileURLWithPath: "/Applications")
    var body: some View {
        Menu("Sort by") {
            ForEach(StackSortOrder.allCases) { order in
                Toggle(order.title, isOn: Binding(get: { model.stackSort == order }, set: { _ in model.stackSort = order }))
            }
        }
        Menu("Display as") {
            ForEach(StackDisplayStyle.allCases) { style in
                Toggle(style.title, isOn: Binding(get: { model.stackDisplay == style }, set: { _ in model.stackDisplay = style }))
            }
        }
        Menu("View content as") {
            ForEach(StackViewStyle.allCases) { style in
                Toggle(style.title, isOn: Binding(get: { model.applicationsStackStyle == style }, set: { _ in model.applicationsStackStyle = style }))
            }
        }
        Divider()
        Menu("Options") {
            Button("Remove from Dock") { model.showApplicationsStack = false }
            Button("Show in Finder") { DockSystemEffect.handler(.reveal([Self.folder])) }
        }
        Divider()
        Button("Open \u{201C}Applications\u{201D}") { DockSystemEffect.handler(.open(Self.folder)) }
        Divider()
        Button("Refresh Applications") { model.toolkit.scanApplications(force: true) }
    }
}

/// App chooser modelled on the macOS Apps view: a glass search capsule floating above a separate
/// glass panel of large icons, in the upper middle of the screen. View and category choices sit in
/// the capsule's "…" menu. It never covers the whole desktop.
@MainActor final class AppsLauncher {
    static let shared = AppsLauncher()
    /// What clicking an app does: open it, pin it to the Dock (the + tile), or swap it into a tile.
    enum Mode: Equatable {
        case launch, add, replace(DockApp)
        var title: String? {
            switch self {
            case .launch: return nil
            case .add: return "Add an app to the Dock"
            case .replace(let app): return "Replace " + app.name
            }
        }
    }
    static let barSize = CGSize(width: 518, height: 80)
    static let barGap: CGFloat = 11, resultsCornerRadius: CGFloat = 42
    /// The transparent window holding both pieces.
    static let panelSize = CGSize(width: 842, height: 610)
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { AppsLauncher.shared.close(restorePrevious: true) }
        override func keyDown(with event: NSEvent) { if !AppsLauncher.shared.chooser.handleKey(event) { super.keyDown(with: event) } }
        /// A click beside the glass dismisses like a click outside; no other app receives it, so focus goes back.
        override func sendEvent(_ event: NSEvent) {
            let point = CGPoint(x: event.locationInWindow.x, y: frame.height - event.locationInWindow.y)
            if [.leftMouseDown, .rightMouseDown].contains(event.type), !AppsLauncher.hits(point, in: frame.size) { AppsLauncher.shared.close(restorePrevious: true) }
            else { super.sendEvent(event) }
        }
    }
    private(set) var panel: NSPanel?
    /// The open launcher's mode; add and replace edit the Dock, so they close when the licence lapses.
    private(set) var mode: Mode = .launch
    /// Brings the chooser on screen through the system-effect seam, so tests never show a real window.
    var present: (NSPanel) -> Void = { DockSystemEffect.handler(.present($0)) }
    /// Pops the capsule's "…" menu just below its button; tests read the menu without tracking it.
    var presentOptions: (NSMenu, NSView) -> Void = { menu, button in menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button) }
    private var previousApplication: NSRunningApplication?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    let chooser = AppsChooserState()

    /// Centred horizontally and sitting in the upper part of the visible frame, like Spotlight.
    static func frame(in visible: NSRect) -> NSRect {
        let width = min(panelSize.width, visible.width - 48), height = min(panelSize.height, visible.height - 48)
        let top = visible.maxY - max(24, (visible.height - height) * 0.3)
        return NSRect(x: (visible.midX - width / 2).rounded(), y: (top - height).rounded(), width: width, height: height)
    }

    /// Where the two glass pieces sit in a window of `size`, with a top-left origin.
    static func pieces(in size: CGSize) -> (bar: CGRect, results: CGRect) {
        let barWidth = min(barSize.width, size.width), resultsTop = barSize.height + barGap
        return (CGRect(x: ((size.width - barWidth) / 2).rounded(), y: 0, width: barWidth, height: barSize.height),
                CGRect(x: 0, y: resultsTop, width: size.width, height: max(0, size.height - resultsTop)))
    }

    /// Whether a top-left window point lands on the capsule or the results panel, not the gap or corners.
    static func hits(_ point: CGPoint, in size: CGSize) -> Bool {
        let pieces = pieces(in: size)
        return Capsule().path(in: pieces.bar).contains(point)
            || RoundedRectangle(cornerRadius: resultsCornerRadius, style: .continuous).path(in: pieces.results).contains(point)
    }

    func toggle(model: DockModel) { panel == nil ? show(model: model) : close(restorePrevious: true) }

    func show(model: DockModel, mode: Mode = .launch, query: String = "") {
        let previous = panel == nil ? NSWorkspace.shared.frontmostApplication : previousApplication
        close()
        previousApplication = previous
        self.mode = mode
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = Self.frame(in: screen.visibleFrame)
        let panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear
        // The window shadow is cut from the content's alpha, so it waits until both pieces have landed.
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        chooser.reset(query: query, defaults: model.defaults)
        chooser.columns = AppsChooserState.columns(fitting: frame.width)
        let root = AppsLauncherView(model: model, kit: model.toolkit, state: chooser, mode: mode, close: { [weak self] in self?.close(restorePrevious: true) },
                                    entered: { [weak panel] in panel?.hasShadow = true; panel?.invalidateShadow() })
            .preferredColorScheme(model.scheme)
        panel.contentView = NSHostingView(rootView: root)
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        present(panel)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.16; panel.animator().alphaValue = 1 }
        self.panel = panel
        // Arrow keys move the selection even while the search field is editing.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.chooser.handleKey(event) else { return event }
            return nil
        } as Any)
        // A click in another app or on the desktop dismisses it, like Spotlight.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { AppsLauncher.shared.close() }
        } as Any)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { AppsLauncher.shared.close() }
        }
        model.toolkit.scanApplications(force: true)
    }

    /// Closes an add or replace launcher, which needs an active licence; a plain launch launcher stays open.
    func closeEditing() { if mode != .launch { close() } }

    func close(restorePrevious: Bool = false) {
        guard let panel else { return }
        self.panel = nil; mode = .launch
        // End editing first: the search field's system completion list otherwise stays attached to
        // this panel and asserts when the next window comes on screen.
        panel.makeFirstResponder(nil)
        if restorePrevious, let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication.activate() }
        previousApplication = nil
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil); panel.contentView = nil }
        }
    }
}

/// The categories the Apps view groups apps into, derived from each bundle's `LSApplicationCategoryType`.
enum AppCategory: String, CaseIterable {
    case productivity = "Productivity & Finance", creativity = "Creativity", developer = "Developer Tools",
         utilities = "Utilities", social = "Social", entertainment = "Entertainment", reading = "Information & Reading",
         education = "Education", games = "Games", health = "Health & Fitness", other = "Other"

    init(categoryType: String?, path: String) {
        let kind = categoryType?.lowercased().replacingOccurrences(of: "public.app-category.", with: "") ?? ""
        switch kind {
        case "business", "productivity", "finance": self = .productivity
        case "graphics-design", "photography", "video", "music": self = .creativity
        case "developer-tools": self = .developer
        case "utilities": self = .utilities
        case "social-networking": self = .social
        case "entertainment": self = .entertainment
        case "news", "reference", "weather", "books", "magazines", "lifestyle": self = .reading
        case "education", "kids": self = .education
        case "healthcare-fitness", "medical", "sports": self = .health
        case _ where kind == "games" || kind.hasSuffix("-games"): self = .games
        default: self = path.contains("/Utilities/") ? .utilities : .other
        }
    }

    private static var cache: [String: AppCategory] = [:]
    static func of(_ app: DockApp) -> AppCategory {
        if let known = cache[app.id] { return known }
        let category = AppCategory(categoryType: Bundle(url: app.url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String, path: app.id)
        cache[app.id] = category
        return category
    }
}

/// Runs one "…" menu choice; the menu item keeps it alive through `representedObject`.
private final class AppsChooserMenuAction: NSObject {
    private let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @MainActor @objc func choose() { run() }
}

/// Search text, category tag, keyboard selection and icon/list layout, shared by the panel and its view.
@MainActor final class AppsChooserState: ObservableObject {
    enum Layout: String { case icons, list }
    @Published var query = ""
    @Published var category: AppCategory?
    @Published var selection = 0
    @Published var layout = Layout.icons { didSet { defaults?.set(layout.rawValue, forKey: "appsChooserLayout") } }
    /// Number of visible results, kept current by the view so arrow keys can clamp.
    var count = 0
    static let maxColumns = 7
    /// Grid columns in this window, which also sets how far Up and Down move.
    var columns = maxColumns
    private var defaults: UserDefaults?
    /// As many of the seven columns as fit 76pt cells beside the grid's 20pt margins.
    static func columns(fitting width: CGFloat) -> Int { max(1, min(maxColumns, Int((width - 40) / 76))) }
    var searchIsEmpty: Bool { AppSearchIndex.fold(query).isEmpty }

    func reset(query: String, defaults: UserDefaults) {
        self.defaults = nil
        layout = defaults.string(forKey: "appsChooserLayout").flatMap(Layout.init(rawValue:)) ?? .icons
        self.defaults = defaults
        self.query = query; category = nil; selection = 0
    }

    /// Alphabetical while the search is empty, otherwise the index's ranking; then the category tag.
    func results(in index: AppSearchIndex) -> [DockApp] {
        let matches = searchIsEmpty
            ? index.apps.sorted { index.name(of: $0).localizedStandardCompare(index.name(of: $1)) == .orderedAscending }
            : index.search(query)
        guard let category else { return matches }
        return matches.filter { AppCategory.of($0) == category }
    }

    /// Icons or list, then the categories that actually have apps, ticked like inline pickers.
    func optionsMenu(apps: [DockApp]) -> NSMenu {
        let menu = NSMenu(), present = Set(apps.map(AppCategory.of))
        func add(_ title: String, symbol: String? = nil, on: Bool, _ choose: @escaping @MainActor () -> Void) {
            let action = AppsChooserMenuAction(choose)
            let item = menu.addItem(withTitle: title, action: #selector(AppsChooserMenuAction.choose), keyEquivalent: "")
            item.target = action; item.representedObject = action; item.state = on ? .on : .off
            item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        }
        add("View as Icons", symbol: "square.grid.2x2", on: layout == .icons) { self.layout = .icons }
        add("View as List", symbol: "list.bullet", on: layout == .list) { self.layout = .list }
        menu.addItem(.separator())
        add("All Categories", on: category == nil) { self.category = nil }
        for option in AppCategory.allCases where present.contains(option) {
            add(option.rawValue, on: category == option) { self.category = option }
        }
        return menu
    }

    func move(_ delta: Int) { if count > 0 { selection = max(0, min(count - 1, selection + delta)) } }

    /// Up/Down move by a row; Left/Right move by one icon in the grid and stay with the text in the list.
    func handleKey(_ event: NSEvent) -> Bool {
        let row = layout == .icons ? columns : 1
        switch event.keyCode {
        case 125: move(row)
        case 126: move(-row)
        case 124 where layout == .icons: move(1)
        case 123 where layout == .icons: move(-1)
        default: return false
        }
        return true
    }
}

struct AppsLauncherView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var state: AppsChooserState
    var mode: AppsLauncher.Mode = .launch
    var close: () -> Void
    /// Runs once the entrance animation has finished.
    var entered: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @StateObject private var optionsButton = StackAnchor()
    @FocusState private var searchFocused: Bool
    init(model: DockModel, kit: Toolkit, state: AppsChooserState, mode: AppsLauncher.Mode = .launch, close: @escaping () -> Void, entered: @escaping () -> Void = {}) {
        self.model = model; self.kit = kit; self.state = state; self.mode = mode; self.close = close; self.entered = entered
    }

    var body: some View {
        let results = state.results(in: kit.appIndex)
        VStack(spacing: AppsLauncher.barGap) {
            searchBar(results)
            resultsPanel(results)
        }
        .scaleEffect(Self.entranceScale(shown: shown, reduceMotion: reduceMotion)).opacity(shown ? 1 : 0)
        .onAppear {
            state.count = results.count
            searchFocused = true
            withAnimation(Self.entrance(reduceMotion: reduceMotion)) { shown = true } completion: { entered() }
        }
        .onChange(of: state.query) { state.selection = 0 }
        .onChange(of: state.category) { state.selection = 0 }
        .onChange(of: results.count) { _, count in state.count = count; state.selection = min(state.selection, max(0, count - 1)) }
        .onExitCommand(perform: close)
    }

    /// Reduce Motion keeps the fade and drops the scale and spring.
    static func entranceScale(shown: Bool, reduceMotion: Bool) -> CGFloat { shown || reduceMotion ? 1 : 0.96 }
    static func entrance(reduceMotion: Bool) -> Animation { reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.28, dampingFraction: 0.82) }

    private func searchBar(_ results: [DockApp]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 21, weight: .medium)).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(mode.title ?? "Search", text: $state.query).textFieldStyle(.plain).font(.system(size: 24)).focused($searchFocused)
                .onSubmit { if results.indices.contains(state.selection) { choose(results[state.selection]) } }
            if !state.query.isEmpty {
                Button { state.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 17)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search").help("Clear search")
            }
            optionsMenu
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: AppsLauncher.barSize.width, minHeight: AppsLauncher.barSize.height, maxHeight: AppsLauncher.barSize.height)
        .background(DockPlate(theme: model.theme, cornerRadius: AppsLauncher.barSize.height / 2))
    }

    /// A plain button over an NSMenu: unlike SwiftUI's Menu, accessibility clients can reach and press it.
    private var optionsMenu: some View {
        Button {
            if let view = optionsButton.view { AppsLauncher.shared.presentOptions(state.optionsMenu(apps: kit.appIndex.apps), view) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary).frame(width: 30, height: 30).contentShape(Rectangle())
                .background(StackAnchorView(anchor: optionsButton))
        }
        .buttonStyle(.plain).fixedSize()
        .help("View and category options").accessibilityLabel("View and category options")
    }

    private func resultsPanel(_ results: [DockApp]) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppsLauncher.resultsCornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            if mode != .launch, let error = model.systemError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).padding(.top, 14)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if state.layout == .icons { grid(results) } else { list(results) }
                }
                .onChange(of: state.selection) { _, index in
                    if results.indices.contains(index) { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(results[index].id) } }
                }
            }
            .overlay { emptyState(results) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .background(DockPlate(theme: model.theme, cornerRadius: AppsLauncher.resultsCornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mode.title ?? "Applications")
    }

    private func grid(_ results: [DockApp]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: state.columns), spacing: 2) {
            ForEach(Array(results.enumerated()), id: \.element.id) { offset, app in
                item(app, offset: offset, list: false).id(app.id)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func list(_ results: [DockApp]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(results.enumerated()), id: \.element.id) { offset, app in
                item(app, offset: offset, list: true).id(app.id)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }

    private func item(_ app: DockApp, offset: Int, list: Bool) -> some View {
        AppsLauncherIcon(app: app, name: kit.appIndex.name(of: app), category: AppCategory.of(app).rawValue, list: list,
                         selected: offset == state.selection, pinned: model.apps.contains(app), badged: mode != .launch,
                         choose: { choose(app) }, launch: { launch(app) }, pin: { model.pin(app) })
    }

    @ViewBuilder private func emptyState(_ results: [DockApp]) -> some View {
        if results.isEmpty {
            Group {
                if kit.scanningApps && kit.appIndex.count == 0 { ProgressView("Finding installed applications…") }
                else { Text(state.searchIsEmpty && state.category == nil ? "No applications found" : "No Results").font(.title3.weight(.medium)).foregroundStyle(.secondary) }
            }.allowsHitTesting(false)
        }
    }

    private func launch(_ app: DockApp) { kit.recordLaunch(app, query: state.query); close(); model.open(app) }
    /// Clicking an app: launch it, or add/replace a Dock tile and close once the model accepts it.
    private func choose(_ app: DockApp) {
        switch mode {
        case .launch: launch(app)
        case .add, .replace:
            guard !(mode == .add && model.apps.contains(app)) else { return }
            if case .replace(let old) = mode { guard model.chooseApp(app, replacing: old) else { return } }
            else { guard model.chooseApp(app, replacing: nil) else { return } }
            kit.recordLaunch(app, query: state.query); close()
        }
    }
}

private struct AppsLauncherIcon: View {
    let app: DockApp
    let name: String
    let category: String
    let list: Bool
    let selected: Bool
    let pinned: Bool
    /// Add and replace modes mark apps already in the Dock.
    let badged: Bool
    let choose: () -> Void
    let launch: () -> Void
    let pin: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: choose) {
            Group {
                if list {
                    HStack(spacing: 10) {
                        icon(28)
                        Text(name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(category).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10).frame(height: 38)
                } else {
                    VStack(spacing: 8) {
                        icon(64)
                        Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 8).frame(maxWidth: .infinity)
                }
            }
            .background(RoundedRectangle(cornerRadius: list ? 10 : 18, style: .continuous).fill(Color.primary.opacity(selected ? 0.14 : hovered ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(name)
        .accessibilityValue(badged && pinned ? "Already in the Dock" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(app.id)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
        .contextMenu {
            Button("Open", action: launch)
            Button("Keep in Dock", action: pin).disabled(pinned)
            Button("Show in Finder") { DockSystemEffect.handler(.reveal([app.url])) }
        }
    }

    private func icon(_ size: CGFloat) -> some View {
        Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if badged && pinned {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: size * 0.28)).foregroundStyle(.white, .green)
                        .accessibilityHidden(true).help("Already in the Dock")
                }
            }
            .opacity(badged && pinned ? 0.55 : 1)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1).animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
