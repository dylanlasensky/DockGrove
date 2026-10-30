import AppKit
import SwiftUI

/// Derives the camera housing from Apple's public display geometry, never a model-name list.
struct NotchGeometry: Equatable {
    let screen: CGRect
    let housing: CGRect
    init?(screen: CGRect, topInset: CGFloat, left: CGRect?, right: CGRect?) {
        guard topInset.isFinite, topInset > 0, topInset < screen.height / 4,
              let left, let right, left.width > 0, right.width > 0,
              left.maxX < right.minX, left.minX >= screen.minX, right.maxX <= screen.maxX,
              abs(left.maxY - screen.maxY) < 1, abs(right.maxY - screen.maxY) < 1 else { return nil }
        self.screen = screen
        housing = CGRect(x: left.maxX, y: screen.maxY - topInset, width: right.minX - left.maxX, height: topInset)
    }
    init?(display: NSScreen) {
        self.init(screen: display.frame, topInset: display.safeAreaInsets.top, left: display.auxiliaryTopLeftArea, right: display.auxiliaryTopRightArea)
    }
    func panelFrame(expanded: Bool) -> CGRect {
        let width = min(screen.width - 32, expanded ? max(520, housing.width + 120) : housing.width + 100)
        let height: CGFloat = housing.height + (expanded ? 164 : 0)
        let x = min(screen.maxX - width - 16, max(screen.minX + 16, housing.midX - width / 2))
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
    static var compatibleDisplay: NSScreen? { NSScreen.screens.first { NotchGeometry(display: $0) != nil } }
}

struct NotchHoverState {
    private var started: TimeInterval?
    private var lastInside: TimeInterval = 0
    private var openedByHover = false
    private var armed = true
    mutating func manualChange(expanded: Bool) {
        started = nil; openedByHover = false; armed = expanded
    }
    mutating func update(now: TimeInterval, trigger: Bool, inside: Bool, expanded: Bool, interacting: Bool) -> Bool? {
        if !trigger { armed = true; started = nil }
        if expanded {
            if inside || interacting { lastInside = now }
            else if openedByHover && now - lastInside >= 0.7 {
                openedByHover = false; started = nil; return false
            }
        } else if trigger && armed {
            if started == nil { started = now }
            if now - (started ?? now) >= 0.18 {
                started = nil; lastInside = now; openedByHover = true; return true
            }
        }
        return nil
    }
}

extension DockModel {
    var notchWidgets: [ToolKind] {
        let pinned = orderedEntries.compactMap { entry -> ToolKind? in
            if case .tool(let kind) = entry { return kind }; return nil
        }
        var seen = Set<ToolKind>()
        return (pinned + ToolKind.allCases).filter { $0 != .spacer && $0 != .separator && canAccess($0) && seen.insert($0).inserted }
    }
}

@MainActor final class NotchController: ObservableObject {
    @Published var expanded = false
    @Published var selectedWidget: ToolKind?
    private(set) var panel: DockPanel!
    private let model: DockModel
    private var hover = NotchHoverState()
    @Published private(set) var geometry: NotchGeometry?
    init(model: DockModel) {
        self.model = model
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "DockGrove Notch"
        panel.isFloatingPanel = true; panel.level = .statusBar; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: NotchShelfView(model: model, controller: self))
    }
    func setExpanded(_ value: Bool, fromHover: Bool = false) {
        if !fromHover { hover.manualChange(expanded: value) }
        selectedWidget = nil; expanded = value
        if let geometry { panel.setFrame(geometry.panelFrame(expanded: value), display: true) }
    }
    func hide() {
        hover = NotchHoverState()
        selectedWidget = nil
        if expanded { expanded = false }
        panel.orderOut(nil); panel.ignoresMouseEvents = true
    }
    func update(suppressed: Bool) {
        guard model.notchEnabled, model.visible, model.canUseFeatures, !suppressed,
              let display = NotchGeometry.compatibleDisplay, let geometry = NotchGeometry(display: display),
              !Self.fullscreen(on: display) else { hide(); geometry = nil; return }
        if let selectedWidget, !model.canAccess(selectedWidget) { self.selectedWidget = nil }
        if geometry != self.geometry { setExpanded(false); self.geometry = geometry }
        let mouse = NSEvent.mouseLocation
        if let expand = hover.update(now: Date.timeIntervalSinceReferenceDate,
                                     trigger: geometry.panelFrame(expanded: false).contains(mouse),
                                     inside: panel.frame.contains(mouse), expanded: expanded,
                                     interacting: selectedWidget != nil) {
            setExpanded(expand, fromHover: true)
        }
        let frame = geometry.panelFrame(expanded: expanded)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.ignoresMouseEvents = false
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    private static func fullscreen(on screen: NSScreen) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let data = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: data) else { return false }
            return DockVisibility.coversScreen(rect, frame)
        }
    }
}

struct NotchShelfView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var controller: NotchController
    @State private var page = 0
    @State private var query = ""
    private var widgets: [ToolKind] {
        model.notchWidgets.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        let pages = max(1, (widgets.count + 2) / 3)
        let current = min(page, pages - 1)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { controller.setExpanded(!controller.expanded) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.grid.2x2.fill")
                        if controller.expanded { Text("DockGrove").fontWeight(.semibold) }
                    }.font(.system(size: 11)).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.accessibilityLabel(controller.expanded ? "Collapse DockGrove notch" : "Expand DockGrove notch")
                // This region is physically covered by the camera housing. Never put controls here.
                Color.clear.frame(width: controller.geometry?.housing.width ?? 185).allowsHitTesting(false).accessibilityHidden(true)
                Button { controller.setExpanded(!controller.expanded) } label: {
                    Image(systemName: controller.expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.accessibilityLabel(controller.expanded ? "Collapse notch" : "Open notch widgets")
            }.frame(height: controller.geometry?.housing.height ?? 32)
            if controller.expanded {
                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find a widget", text: $query).textFieldStyle(.plain).font(.caption)
                        }.frame(width: 200)
                        Spacer()
                        Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }.disabled(current == 0).accessibilityLabel("Previous notch page")
                        Text("\(current + 1)/\(pages)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button { page = min(pages - 1, current + 1) } label: { Image(systemName: "chevron.right") }.disabled(current == pages - 1).accessibilityLabel("Next notch page")
                    }
                    HStack(spacing: 10) {
                        ForEach(Array(widgets.dropFirst(current * 3).prefix(3))) { kind in
                            Button {
                                guard model.canAccess(kind) else { return }
                                if kind == .search { model.toolkit.scanApplications() }
                                controller.selectedWidget = kind
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: kind.icon).font(.title2)
                                    Text(kind.title).font(.caption.weight(.medium)).lineLimit(1)
                                }.frame(maxWidth: .infinity, minHeight: 78)
                                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                            }.accessibilityLabel("Open " + kind.title + " from notch")
                        }
                    }
                    if widgets.isEmpty { Text("No matching widgets").font(.caption).foregroundStyle(.secondary) }
                    Text("All your unlocked widgets · Dock favorites first").font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(14).frame(height: 164)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white).background(.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: controller.expanded ? 22 : 10, bottomTrailingRadius: controller.expanded ? 22 : 10))
            .buttonStyle(.plain).preferredColorScheme(.dark)
            .onChange(of: query) { _, _ in page = 0 }
            .popover(item: $controller.selectedWidget, arrowEdge: .bottom) { kind in
                if model.canAccess(kind) {
                    VStack(alignment: .leading, spacing: 15) {
                        Label(kind.title, systemImage: kind.icon).font(.headline)
                        Divider()
                        ToolTile(kind: kind, model: model, kit: model.toolkit).contents
                    }.padding(22).frame(width: 350).preferredColorScheme(.dark)
                }
            }
    }
}

struct NotchSettingsView: View {
    @ObservedObject var model: DockModel
    @State private var displayName = NotchGeometry.compatibleDisplay?.localizedName
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Notch quick access", systemImage: "macbook").font(.headline)
                Spacer()
                Text(displayName == nil ? "Not available on this display" : "Compatible Mac detected").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                VStack(spacing: 0) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 80, height: 15)
                    HStack(spacing: 15) { Image(systemName: "magnifyingglass"); Image(systemName: "timer"); Image(systemName: "checklist") }
                        .font(.caption).foregroundStyle(.white).frame(width: 152, height: 46)
                        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                }.frame(width: 190, height: 85, alignment: .top).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable notch access", isOn: $model.notchEnabled).disabled(displayName == nil && !model.notchEnabled)
                    Text(displayName.map { "Open your Dock widgets from the notch on " + $0 + "." } ?? "Connect a display with a built-in camera notch to use this feature.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.notchEnabled && displayName != nil { Button("Open notch") { model.openNotchAction?() } }
                }
            }
            Text("Hover over the notch or click either side to open it. Browse all unlocked widgets; your Dock favorites appear first. Hides in full screen, on lock, and during sleep.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.primary.opacity(0.07)))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in displayName = NotchGeometry.compatibleDisplay?.localizedName }
    }
}

@MainActor func runNotchTests(output: URL?) throws {
    let base = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
    let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    precondition(NotchGeometry(screen: base, topInset: 0, left: nil, right: nil) == nil)
    precondition(NotchGeometry(screen: base, topInset: 32, left: nil, right: right) == nil)
    precondition(NotchGeometry(screen: base, topInset: .nan, left: left, right: right) == nil)
    precondition(NotchGeometry(screen: base, topInset: 32, left: right, right: left) == nil)
    for offset in [CGPoint.zero, CGPoint(x: -1512, y: 120), CGPoint(x: 300, y: -982)] {
        let screen = base.offsetBy(dx: offset.x, dy: offset.y)
        let geometry = NotchGeometry(screen: screen, topInset: 32, left: left.offsetBy(dx: offset.x, dy: offset.y), right: right.offsetBy(dx: offset.x, dy: offset.y))!
        precondition(geometry.housing.width == 185)
        for expanded in [false, true] {
            let frame = geometry.panelFrame(expanded: expanded)
            precondition(screen.contains(frame))
            precondition(abs(frame.midX - geometry.housing.midX) < 0.01)
            precondition(frame.maxY == screen.maxY, "The shelf must anchor in the notch row")
            precondition(frame.width > geometry.housing.width + 90, "Controls need space beside the camera")
            if !expanded { precondition(frame.minY == geometry.housing.minY, "Collapsed mode must stay entirely in the notch row") }
        }
    }
    let suite = "DockGroveNotchTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set([], forKey: "apps"); defaults.set(false, forKey: "showRunning")
    defaults.set(["search", "focus", "tasks"], forKey: "widgets")
    let model = DockModel(defaults: defaults)
    precondition(!model.notchEnabled)
    model.notchEnabled = true
    precondition(DockModel(defaults: defaults).notchEnabled)
    precondition(model.notchWidgets.contains(.search) && model.notchWidgets.contains(.focus))
    precondition(!model.notchWidgets.contains(.spacer) && !model.notchWidgets.contains(.separator))
    precondition(model.notchWidgets.allSatisfy { model.canAccess($0) })
    precondition(Set(model.notchWidgets).count == model.notchWidgets.count)
    precondition(model.notchWidgets.count == ToolKind.allCases.filter { $0 != .spacer && $0 != .separator && model.canAccess($0) }.count)
    var hover = NotchHoverState()
    precondition(hover.update(now: 0, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    precondition(hover.update(now: 0.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    precondition(hover.update(now: 0.5, trigger: false, inside: false, expanded: true, interacting: false) == nil)
    precondition(hover.update(now: 0.7, trigger: false, inside: false, expanded: true, interacting: true) == nil)
    precondition(hover.update(now: 1.5, trigger: false, inside: false, expanded: true, interacting: false) == false)
    hover.manualChange(expanded: true)
    precondition(hover.update(now: 10, trigger: false, inside: false, expanded: true, interacting: false) == nil)
    hover.manualChange(expanded: false)
    precondition(hover.update(now: 11, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    precondition(hover.update(now: 12, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    _ = hover.update(now: 13, trigger: false, inside: false, expanded: false, interacting: false)
    _ = hover.update(now: 14, trigger: true, inside: true, expanded: false, interacting: false)
    precondition(hover.update(now: 14.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    let controller = NotchController(model: model)
    controller.setExpanded(true); controller.selectedWidget = .focus
    controller.update(suppressed: true)
    precondition(!controller.panel.isVisible && !controller.expanded && controller.selectedWidget == nil)
    model.notchEnabled = false; controller.setExpanded(true)
    controller.update(suppressed: false)
    precondition(!controller.panel.isVisible && !controller.expanded)
    if let output {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let geometry = NotchGeometry(screen: base, topInset: 32, left: left, right: right)!
        for expanded in [false, true] {
            controller.setExpanded(expanded)
            let view = controller.panel.contentView!
            controller.panel.setFrame(geometry.panelFrame(expanded: expanded), display: true)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(expanded ? "notch-expanded.png" : "notch-collapsed.png"))
        }
    }
    controller.hide()
    print("PASS: notch compatibility, invalid/missing geometry, negative display origins, camera-safe frames, preference persistence, disabled/suppressed cleanup, hover dwell/leave/click behavior, complete access-gated widget catalog and renders")
}
