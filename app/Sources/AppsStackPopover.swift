import SwiftUI
import AppKit

/// The Dock's "View Content As" choices for a stack. Fan rises from a bottom Dock only, as on macOS
/// where docks on other edges lose Fan; Automatic picks Fan for small stacks and Grid otherwise.
enum StackViewStyle: String, CaseIterable, Identifiable {
    case fan, grid, list, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fan: return "Fan"
        case .grid: return "Grid"
        case .list: return "List"
        case .automatic: return "Automatic"
        }
    }
    /// The concrete style to draw: never `.automatic`, and never `.fan` when the stack opens downward.
    func resolved(itemCount: Int, opensUpward: Bool) -> StackViewStyle {
        switch self {
        case .automatic: return opensUpward && itemCount <= StackPopoverLayout.fanLimit ? .fan : .grid
        case .fan: return opensUpward ? .fan : .list
        case .grid, .list: return self
        }
    }
}

extension DockModel {
    static let applicationsStackStyleKey = "applicationsStackView"
    var applicationsStackStyle: StackViewStyle {
        get { defaults.string(forKey: Self.applicationsStackStyleKey).flatMap(StackViewStyle.init(rawValue:)) ?? .automatic }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Self.applicationsStackStyleKey) }
    }
    /// The edge the Dock actually sits on; replacing the system Dock always lays out at the bottom.
    var effectiveEdge: String { replacingDock ? "Bottom" : toolkit.edge }
}

/// Where a stack popover sits: its panel frame in screen coordinates (arrow included), whether it
/// rises above the tile, and the arrow tip's x offset from the panel's left edge.
struct StackPopoverPlacement: Equatable {
    var frame: CGRect
    var opensUpward: Bool
    var arrowX: CGFloat
}

/// Pure sizing and anchoring math for the stack popover, kept free of windows so it is testable.
enum StackPopoverLayout {
    static let arrowHeight: CGFloat = 11, arrowWidth: CGFloat = 24, gap: CGFloat = 2, margin: CGFloat = 8, cornerRadius: CGFloat = 18
    static let fanLimit = 12
    static let gridCell = CGSize(width: 96, height: 100), gridMaxColumns = 7, gridMaxRows = 5, gridPadding: CGFloat = 16
    static let listWidth: CGFloat = 260, listRow: CGFloat = 24, listMaxRows = 18
    static let fanWidth: CGFloat = 340, fanRow: CGFloat = 56
    static let footer: CGFloat = 44

    static func gridColumns(count: Int) -> Int { min(gridMaxColumns, max(3, Int(Double(max(count, 1)).squareRoot().rounded(.up)))) }

    /// The popover's content size (without the arrow) for a resolved style and item count.
    static func contentSize(style: StackViewStyle, count: Int) -> CGSize {
        switch style {
        case .list:
            return CGSize(width: listWidth, height: CGFloat(min(max(count, 1), listMaxRows)) * listRow + 12 + footer)
        case .fan:
            return CGSize(width: fanWidth, height: CGFloat(min(count, fanLimit) + 1) * fanRow + 8)
        case .grid, .automatic:
            let columns = gridColumns(count: count)
            let rows = min(gridMaxRows, max(1, (count + columns - 1) / columns))
            return CGSize(width: CGFloat(columns) * gridCell.width + gridPadding * 2, height: CGFloat(rows) * gridCell.height + gridPadding * 2 + footer)
        }
    }

    /// Anchors `content` to the tile at `anchor`: above it on a bottom Dock, below it on a top Dock,
    /// and on a floating Dock above unless there is more room below. The frame is clamped to
    /// `visible` (shrinking height so the grid scrolls) and the arrow keeps pointing at the tile.
    static func place(content: CGSize, anchor: CGRect, visible: CGRect, edge: String) -> StackPopoverPlacement {
        let wanted = content.height + arrowHeight
        let roomAbove = visible.maxY - margin - (anchor.maxY + gap)
        let roomBelow = anchor.minY - gap - (visible.minY + margin)
        let up: Bool
        switch edge {
        case "Top": up = false
        case "Floating": up = roomAbove >= wanted || roomAbove >= roomBelow
        default: up = true
        }
        let height = max(arrowHeight + cornerRadius * 2, min(wanted, up ? roomAbove : roomBelow))
        let width = min(content.width, visible.width - margin * 2)
        let x = min(max(anchor.midX - width / 2, visible.minX + margin), visible.maxX - margin - width)
        let y = up ? anchor.maxY + gap : anchor.minY - gap - height
        let inset = min(width / 2, cornerRadius + arrowWidth / 2)
        let arrowX = min(max(anchor.midX - x, inset), width - inset)
        return StackPopoverPlacement(frame: CGRect(x: x, y: y, width: width, height: height), opensUpward: up, arrowX: arrowX)
    }
}

/// Rounded panel with a callout arrow on the edge facing the Dock tile.
struct StackCalloutShape: Shape {
    var arrowOnBottom: Bool
    var arrowX: CGFloat
    func path(in rect: CGRect) -> Path {
        let h = StackPopoverLayout.arrowHeight, w = StackPopoverLayout.arrowWidth
        let body = arrowOnBottom ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - h)
                                 : CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
        var path = Path(roundedRect: body, cornerRadius: StackPopoverLayout.cornerRadius, style: .continuous)
        let x = rect.minX + arrowX
        var arrow = Path()
        if arrowOnBottom {
            arrow.move(to: CGPoint(x: x - w / 2, y: body.maxY - 1))
            arrow.addQuadCurve(to: CGPoint(x: x, y: rect.maxY), control: CGPoint(x: x - w / 6, y: body.maxY))
            arrow.addQuadCurve(to: CGPoint(x: x + w / 2, y: body.maxY - 1), control: CGPoint(x: x + w / 6, y: body.maxY))
        } else {
            arrow.move(to: CGPoint(x: x - w / 2, y: body.minY + 1))
            arrow.addQuadCurve(to: CGPoint(x: x, y: rect.minY), control: CGPoint(x: x - w / 6, y: body.minY))
            arrow.addQuadCurve(to: CGPoint(x: x + w / 2, y: body.minY + 1), control: CGPoint(x: x + w / 6, y: body.minY))
        }
        arrow.closeSubpath()
        path.addPath(arrow)
        return path
    }
}

/// Keyboard selection inside the open stack: arrows move, Return opens, typing jumps by name.
@MainActor final class StackNavigator: ObservableObject {
    @Published var selection: Int?
    var names: [String] = []
    /// Items per row; 1 for List, -1 for Fan (whose first item sits nearest the Dock, so Up moves forward).
    var columns = 1
    var activate: (Int) -> Void = { _ in }

    func reset(names: [String], columns: Int) { self.names = names; self.columns = columns; selection = nil }

    func move(_ delta: Int) {
        guard !names.isEmpty else { return }
        guard let current = selection else { selection = delta < 0 ? names.count - 1 : 0; return }
        selection = min(max(0, current + delta), names.count - 1)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123: move(-1); return true
        case 124: move(1); return true
        case 125: move(columns); return true
        case 126: move(-columns); return true
        case 36, 76:
            if let selection { activate(selection) }
            return true
        default:
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let typed = event.charactersIgnoringModifiers?.lowercased(), typed.count == 1,
                  typed.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains),
                  let index = names.firstIndex(where: { $0.lowercased().hasPrefix(typed) }) else { return false }
            selection = index
            return true
        }
    }
}

/// Clicking the Applications stack: a Dock-anchored popover in Fan, Grid or List style, like a
/// macOS Dock stack, rather than a full-screen launcher.
@MainActor final class AppsStackPopover {
    static let shared = AppsStackPopover()
    final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { AppsStackPopover.shared.close(restorePrevious: true) }
        override func keyDown(with event: NSEvent) { if !AppsStackPopover.shared.navigator.handleKey(event) { super.keyDown(with: event) } }
    }
    private(set) var panel: NSPanel?
    private(set) var placement: StackPopoverPlacement?
    private(set) var style: StackViewStyle = .grid
    private(set) var apps: [DockApp] = []
    private(set) var anchor: CGRect = .zero
    /// Brings the popover on screen through the system-effect seam, so tests never show it.
    var present: (NSPanel) -> Void = { DockSystemEffect.handler(.present($0)) }
    /// A click on the tile first dismisses the popover (click-outside or losing key); the tile's own
    /// action that follows within this window must not reopen it.
    var dismissalGrace: TimeInterval = 0.35
    let navigator = StackNavigator()
    private weak var model: DockModel?
    private var previousApplication: NSRunningApplication?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var dismissedAt: Date?

    /// The stack's contents: every catalogued application, in the stack's "Sort by" order.
    static func contents(of kit: Toolkit, sort: StackSortOrder = .name) -> [(app: DockApp, name: String)] {
        let index = kit.appIndex
        let apps: [DockApp] = index.apps
        let byName: [(app: DockApp, name: String)] = zip(apps, index.records).map { ($0, $1.name.isEmpty ? $0.name : $1.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard sort != .name else { return byName }
        let urls: [URL] = byName.map { $0.app.url }
        let rank: [URL: Int] = Dictionary(sort.sorted(urls).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return byName.sorted { (rank[$0.app.url] ?? .max) < (rank[$1.app.url] ?? .max) }
    }

    func toggle(model: DockModel, anchor: CGRect?) {
        if panel != nil { close(restorePrevious: true); return }
        if let dismissedAt, Date().timeIntervalSince(dismissedAt) < dismissalGrace { self.dismissedAt = nil; return }
        let anchor = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main ?? NSScreen.screens.first
        show(model: model, anchor: anchor, visible: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    func show(model: DockModel, anchor: CGRect, visible: CGRect) {
        let previous = panel == nil ? NSWorkspace.shared.frontmostApplication : previousApplication
        close()
        dismissedAt = nil
        previousApplication = previous
        self.model = model
        self.anchor = anchor
        model.toolkit.scanApplications()
        let contents = Self.contents(of: model.toolkit, sort: model.stackSort)
        apps = contents.map(\.app)
        let edge = model.effectiveEdge
        // Fan needs to know the direction first; directions only differ on a floating Dock.
        let probe = StackPopoverLayout.place(content: StackPopoverLayout.contentSize(style: .grid, count: apps.count), anchor: anchor, visible: visible, edge: edge)
        style = model.applicationsStackStyle.resolved(itemCount: apps.count, opensUpward: probe.opensUpward)
        let placement = StackPopoverLayout.place(content: StackPopoverLayout.contentSize(style: style, count: apps.count), anchor: anchor, visible: visible, edge: edge)
        self.placement = placement
        let columns: Int
        switch style {
        case .grid, .automatic: columns = StackPopoverLayout.gridColumns(count: apps.count)
        case .list: columns = 1
        case .fan: columns = -1
        }
        navigator.reset(names: contents.map(\.name), columns: columns)
        navigator.activate = { [weak self] index in
            guard let self, self.apps.indices.contains(index) else { return }
            self.launch(self.apps[index])
        }

        let panel = Panel(contentRect: placement.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = style != .fan
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isReleasedWhenClosed = false
        let root = AppsStackView(model: model, kit: model.toolkit, navigator: navigator, style: style, placement: placement, items: contents,
                                 launch: { [weak self] in self?.launch($0) }, openInFinder: { [weak self] in self?.openInFinder() })
            .preferredColorScheme(model.scheme)
        panel.contentView = NSHostingView(rootView: root)
        panel.setFrame(placement.frame, display: false)
        panel.alphaValue = 0
        present(panel)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.14; panel.animator().alphaValue = 1 }
        self.panel = panel
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            if let self, event.window !== self.panel { self.dismiss() }
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: clicks) { _ in
            MainActor.assumeIsolated { AppsStackPopover.shared.dismiss() }
        } as Any)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { AppsStackPopover.shared.dismiss() }
        }
    }

    /// Closes because the user clicked elsewhere or the popover lost focus.
    func dismiss() {
        guard panel != nil else { return }
        close()
        dismissedAt = Date()
    }

    func close(restorePrevious: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        if restorePrevious, let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication.activate() }
        previousApplication = nil
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil); panel.contentView = nil }
        }
    }

    func launch(_ app: DockApp) {
        let model = model
        close()
        model?.open(app)
    }

    func openInFinder() {
        close()
        DockSystemEffect.handler(.open(URL(fileURLWithPath: "/Applications")))
    }
}

/// Records the tile's backing view so a click can find its on-screen rectangle.
final class StackAnchor: ObservableObject {
    weak var view: NSView?
    var screenRect: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

struct StackAnchorView: NSViewRepresentable {
    let anchor: StackAnchor
    func makeNSView(context: Context) -> NSView { let view = NSView(); anchor.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

struct AppsStackView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var navigator: StackNavigator
    let style: StackViewStyle
    let placement: StackPopoverPlacement
    let items: [(app: DockApp, name: String)]
    var launch: (DockApp) -> Void
    var openInFinder: () -> Void

    private var arrowOnBottom: Bool { placement.opensUpward }
    private var shape: StackCalloutShape { StackCalloutShape(arrowOnBottom: arrowOnBottom, arrowX: placement.arrowX) }

    var body: some View {
        Group {
            if style == .fan { fan }
            else {
                VStack(spacing: 0) {
                    if items.isEmpty { empty } else if style == .list { list } else { grid }
                    footer
                }
                .padding(arrowOnBottom ? .bottom : .top, StackPopoverLayout.arrowHeight)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
                .clipShape(shape)
            }
        }
        .frame(width: placement.frame.width, height: placement.frame.height)
        .onExitCommand { AppsStackPopover.shared.close(restorePrevious: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Applications stack")
    }

    @ViewBuilder private var empty: some View {
        if items.isEmpty {
            Group {
                if kit.scanningApps { ProgressView("Finding installed applications…") }
                else { Text("No applications found").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(StackPopoverLayout.gridCell.width), spacing: 0), count: StackPopoverLayout.gridColumns(count: items.count))
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.app.id) { index, item in
                        StackItemButton(app: item.app, name: item.name, selected: navigator.selection == index, style: .grid) { launch(item.app) }
                            .frame(width: StackPopoverLayout.gridCell.width, height: StackPopoverLayout.gridCell.height)
                            .id(index)
                    }
                }
                .padding(StackPopoverLayout.gridPadding)
            }
            .onChange(of: navigator.selection) { _, index in if let index { proxy.scrollTo(index) } }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.app.id) { index, item in
                        StackItemButton(app: item.app, name: item.name, selected: navigator.selection == index, style: .list) { launch(item.app) }
                            .frame(height: StackPopoverLayout.listRow)
                            .id(index)
                    }
                }
                .padding(.horizontal, 6).padding(.top, 6)
            }
            .onChange(of: navigator.selection) { _, index in if let index { proxy.scrollTo(index) } }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            Button(action: openInFinder) {
                Label("Open in Finder", systemImage: "arrow.forward.circle").font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Open in Finder").help("Open Applications in Finder")
        }
        .frame(height: StackPopoverLayout.footer)
    }

    /// Items rise from the tile along a gentle arc, nearest first, with "Open in Finder" on top.
    private var fan: some View {
        let shown = Array(items.prefix(StackPopoverLayout.fanLimit).enumerated())
        let row = StackPopoverLayout.fanRow, bottom = placement.frame.height - StackPopoverLayout.arrowHeight
        return ZStack(alignment: .topLeading) {
            ForEach(shown, id: \.element.app.id) { index, item in
                StackItemButton(app: item.app, name: item.name, selected: navigator.selection == index, style: .fan) { launch(item.app) }
                    .frame(width: placement.frame.width, height: row)
                    .rotationEffect(.degrees(-Double(index) * 0.9), anchor: .trailing)
                    .position(x: placement.arrowX + Self.fanOffset(index), y: bottom - row * (CGFloat(index) + 0.5))
            }
            Button(action: openInFinder) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("Open in Finder").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                    Image(systemName: "arrow.forward.circle.fill").font(.system(size: 34)).foregroundStyle(.white, .gray).frame(width: 48, height: 48)
                    Spacer().frame(width: StackPopoverLayout.fanWidth / 2 - 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Open in Finder").help("Open Applications in Finder")
            .frame(width: placement.frame.width, height: row)
            .position(x: placement.arrowX + Self.fanOffset(shown.count), y: bottom - row * (CGFloat(shown.count) + 0.5))
        }
        .frame(width: placement.frame.width, height: placement.frame.height, alignment: .topLeading)
    }

    /// Horizontal drift of the fan's `index`th item away from the tile.
    static func fanOffset(_ index: Int) -> CGFloat { CGFloat(index * index) * 0.55 }
}

private struct StackItemButton: View {
    let app: DockApp
    let name: String
    let selected: Bool
    let style: StackViewStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) { label.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .help(name)
            .onHover { hovered = $0 }
            .contextMenu {
                Button("Open", action: action)
                Button("Show in Finder") { DockSystemEffect.handler(.reveal([app.url])) }
            }
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .list:
            HStack(spacing: 7) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 18, height: 18)
                Text(name).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(maxHeight: .infinity)
            .foregroundStyle(selected || hovered ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected || hovered ? Color.accentColor : .clear))
        case .fan:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 3)
                    .background(selected || hovered ? Color.accentColor : Color.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 48, height: 48).shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                Spacer().frame(width: StackPopoverLayout.fanWidth / 2 - 24)
            }
        default:
            VStack(spacing: 5) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 56, height: 56)
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(selected ? 0.18 : hovered ? 0.09 : 0)))
        }
    }
}
