import AppKit
import SwiftUI
import Combine

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
    static func normalizedWidth(_ value: Double) -> Double { value.isFinite ? min(1600, max(600, value)) : 760 }
    func panelFrame(expanded: Bool, preferredWidth: Double = 760) -> CGRect {
        guard expanded else { return housing }
        let width = min(screen.width - 32, max(CGFloat(Self.normalizedWidth(preferredWidth)), housing.width + 120))
        let height: CGFloat = housing.height + 112
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
            let begin = started ?? now
            started = begin
            if now - begin >= 0.18 {
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

@MainActor final class NotchController: NSObject, ObservableObject, NSSharingServiceDelegate {
    @Published var expanded = false
    @Published var selectedWidget: ToolKind?
    @Published var showingFiles = false
    @Published var fileDragActive = false
    @Published var trayMessage: String?
    @Published var activeDropDestination: NotchDropDestination?
    @Published var airDropFiles: [URL] = []
    @Published var airDropReview = false
    @Published var airDropMessage = "Drop files to share nearby"
    private var airDropService: NSSharingService?
    private let airDropAction: (([URL]) -> Bool)?
    /// System hooks, replaceable so tests never show AirDrop, open panels or read the real displays.
    var makeAirDropService: () -> NSSharingService? = { NSSharingService(named: .sendViaAirDrop) }
    var chooseFiles: (String) -> [URL]? = NotchController.runOpenPanel(message:)
    var compatibleDisplay: () -> NSScreen? = { NotchGeometry.compatibleDisplay }
    var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }
    var clock: () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    var airDropBusy: Bool { airDropService != nil }
    var expandedWidth: CGFloat { geometry?.panelFrame(expanded: true, preferredWidth: model.notchWidth).width ?? CGFloat(NotchGeometry.normalizedWidth(model.notchWidth)) }
    var defaultDropDestination: NotchDropDestination { expanded && showingFiles && airDropReview ? .airDrop : .tray }
    func activateDropZone(_ destination: NotchDropDestination) {
        guard canAccept(destination) else { return }
        if destination == .airDrop && !airDropReview {
            setExpanded(true); showingFiles = true; airDropReview = true
        } else { addFiles(to: destination) }
    }
    func clearAirDropFiles() {
        guard !airDropBusy else { return }
        airDropFiles = []; airDropMessage = "Drop files to share nearby"
    }
    func removeAirDropFile(_ url: URL) {
        guard !airDropBusy else { return }
        airDropFiles.removeAll { $0 == url }
    }
    func canAccept(_ destination: NotchDropDestination) -> Bool {
        canAcceptFiles && (destination == .tray || airDropService == nil)
    }
    @discardableResult func acceptDrop(_ urls: [URL], to destination: NotchDropDestination) -> Bool {
        defer { fileDragActive = false; activeDropDestination = nil }
        guard canAccept(destination) else { return false }
        if destination == .tray { return acceptFiles(urls) }
        let valid = NotchFileIntake.existingURLs(urls)
        guard !valid.isEmpty else { airDropMessage = "Choose existing files or folders."; return false }
        setExpanded(true); showingFiles = true
        airDropFiles = NotchFileIntake.existingURLs(airDropFiles + valid)
        airDropReview = true
        airDropMessage = "Review your files, then choose a device."
        return true
    }
    @discardableResult func startAirDrop() -> Bool {
        guard canAccept(.airDrop) else { return false }
        let valid = NotchFileIntake.existingURLs(airDropFiles)
        guard !valid.isEmpty else { airDropMessage = "Add files before choosing a device."; return false }
        airDropFiles = valid
        if let airDropAction { return airDropAction(valid) }
        guard let service = makeAirDropService(), service.canPerform(withItems: valid) else {
            airDropMessage = "AirDrop is unavailable for these files."; return false
        }
        airDropService = service; service.delegate = self
        airDropMessage = "Choose a device in AirDrop"
        service.perform(withItems: valid)
        return true
    }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any], sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? { panel }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        airDropService = nil; airDropMessage = "AirDrop closed. Files kept for reuse."
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        airDropService = nil
        airDropMessage = (error as NSError).code == NSUserCancelledError ? "AirDrop cancelled. Drop to try again." : "AirDrop did not finish. Try again."
    }
    private var choosingFiles = false
    var canAcceptFiles: Bool { model.canAccess(.files) }
    func beginFileDrag() {
        guard canAcceptFiles else { return }
        let destination = defaultDropDestination
        if destination == .tray { airDropReview = false }
        setExpanded(true); showingFiles = true; fileDragActive = true; activeDropDestination = destination
    }
    @discardableResult func acceptFiles(_ urls: [URL]) -> Bool {
        defer { fileDragActive = false; activeDropDestination = nil }
        guard canAcceptFiles else { return false }
        let valid = NotchFileIntake.existingURLs(urls)
        guard !valid.isEmpty else { trayMessage = "Drop existing files or folders from Finder."; return false }
        setExpanded(true); showingFiles = true
        airDropReview = false
        let before = model.toolkit.files.count
        for url in valid { model.toolkit.addFile(url.standardizedFileURL) }
        let added = model.toolkit.files.count - before
        trayMessage = added == 0 ? "These files are already in your tray." : "Added \(added) file shortcut\(added == 1 ? "" : "s")."
        return true
    }
    func addFiles(to destination: NotchDropDestination = .tray) {
        guard canAccept(destination) else { return }
        choosingFiles = true
        if let urls = chooseFiles(destination == .tray ? "Choose files to keep in the tray." : "Choose files to share with AirDrop.") { _ = acceptDrop(urls, to: destination) }
        choosingFiles = false
    }
    static func runOpenPanel(message: String) -> [URL]? {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.allowsMultipleSelection = true; picker.message = message
        return picker.runModal() == .OK ? picker.urls : nil
    }
    private(set) var panel: DockPanel!
    private let model: DockModel
    private var hover = NotchHoverState()
    @Published private(set) var geometry: NotchGeometry?
    init(model: DockModel, airDropAction: (([URL]) -> Bool)? = nil) {
        self.model = model
        self.airDropAction = airDropAction
        super.init()
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "DockGrove Notch"
        panel.isFloatingPanel = true; panel.level = .statusBar; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
        let host = NotchDropHostingView(rootView: NotchShelfView(model: model, controller: self))
        host.controller = self; panel.contentView = host
    }
    func setExpanded(_ value: Bool, fromHover: Bool = false) {
        if !fromHover { hover.manualChange(expanded: value) }
        selectedWidget = nil; expanded = value
        if let geometry { panel.setFrame(geometry.panelFrame(expanded: value, preferredWidth: model.notchWidth), display: true) }
    }
    func hide() {
        hover = NotchHoverState(); fileDragActive = false; activeDropDestination = nil
        selectedWidget = nil
        if expanded { expanded = false }
        panel.orderOut(nil); panel.ignoresMouseEvents = true
    }
    func update(suppressed: Bool) {
        guard model.notchEnabled, model.visible, model.canUseFeatures, !suppressed,
              let display = compatibleDisplay(), let geometry = NotchGeometry(display: display),
              !Self.fullscreen(on: display) else { hide(); geometry = nil; return }
        if let selectedWidget, !model.canAccess(selectedWidget) { self.selectedWidget = nil }
        if geometry != self.geometry { setExpanded(false); self.geometry = geometry }
        let mouse = mouseLocation()
        if let expand = hover.update(now: clock(),
                                     trigger: geometry.panelFrame(expanded: false).contains(mouse),
                                     inside: panel.frame.contains(mouse), expanded: expanded,
                                     interacting: selectedWidget != nil || fileDragActive || choosingFiles || airDropService != nil) {
            setExpanded(expand, fromHover: true)
        }
        let frame = geometry.panelFrame(expanded: expanded, preferredWidth: model.notchWidth)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.ignoresMouseEvents = false
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    static func fullscreen(on screen: NSScreen,
                           frontmost: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                           primaryTop: CGFloat? = NSScreen.screens.first?.frame.maxY,
                           windows: [[String: Any]]? = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) -> Bool {
        guard let pid = frontmost, pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let top = primaryTop ?? 0
        let frame = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        return (windows ?? []).contains { window in
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
    @State private var query = ""
    private var widgets: [ToolKind] {
        model.notchWidgets.filter { $0 != .files && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if controller.expanded {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        if controller.showingFiles {
                            Label("File tray", systemImage: "tray").font(.caption)
                            Spacer()
                        } else {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find a widget", text: $query).textFieldStyle(.plain).font(.caption)
                        }
                    }.padding(.leading, 16).frame(maxWidth: .infinity)
                    Color.clear.frame(width: controller.geometry?.housing.width ?? 185).allowsHitTesting(false).accessibilityHidden(true)
                    HStack {
                        Spacer()
                        tab("Home", files: false)
                        tab("Files", files: true)
                        Button { controller.setExpanded(false) } label: { Image(systemName: "chevron.up").padding(8) }.accessibilityLabel("Collapse notch")
                    }.padding(.trailing, 8).frame(maxWidth: .infinity)
                }.frame(height: controller.geometry?.housing.height ?? 32)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            if controller.showingFiles {
                                NotchTrayView(model: model, kit: model.toolkit, controller: controller).id("tray")
                            } else {
                                if query.isEmpty {
                                    NotchHomeView(model: model, kit: model.toolkit, controller: controller).id("essentials")
                                    divider
                                }
                                ForEach(widgets) { kind in widget(kind).id(kind.rawValue) }
                                if widgets.isEmpty { Text("No matching widgets").font(.caption).foregroundStyle(.secondary).frame(width: 200) }
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 8)
                    }.frame(height: 112)
                        .onChange(of: controller.showingFiles) { _, files in
                            proxy.scrollTo(files ? "tray" : (query.isEmpty ? "essentials" : (widgets.first?.rawValue ?? "essentials")), anchor: .leading)
                        }
                        .onChange(of: controller.airDropReview) { _, _ in proxy.scrollTo("tray", anchor: .leading) }
                        .onChange(of: controller.selectedWidget) { _, kind in
                            if let kind { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(kind.rawValue, anchor: .center) } }
                        }
                        .onChange(of: query) { _, value in
                            proxy.scrollTo(value.isEmpty ? "essentials" : (widgets.first?.rawValue ?? "essentials"), anchor: .leading)
                        }
                }
            } else {
                Button { controller.setExpanded(true) } label: { Color.black.contentShape(Rectangle()) }.accessibilityLabel("Expand DockGrove notch")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white).background(.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: controller.expanded ? 20 : 10, bottomTrailingRadius: controller.expanded ? 20 : 10))
            .overlay {
                if controller.fileDragActive { RoundedRectangle(cornerRadius: 18).stroke(.green.opacity(0.6), lineWidth: 2).padding(2).allowsHitTesting(false) }
            }
            .buttonStyle(.plain).preferredColorScheme(.dark)
    }
    private func tab(_ title: String, files: Bool) -> some View {
        Button {
            controller.selectedWidget = nil
            controller.showingFiles = files
        } label: {
            Text(title).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(controller.showingFiles == files ? .white.opacity(0.14) : .clear, in: Capsule())
        }.accessibilityLabel(title + " notch tab")
            .accessibilityAddTraits(controller.showingFiles == files ? .isSelected : [])
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 58).accessibilityHidden(true) }
    @ViewBuilder private func widget(_ kind: ToolKind) -> some View {
        if controller.selectedWidget == kind {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    Image(systemName: kind.icon)
                    Button { controller.selectedWidget = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Close " + kind.title + " controls")
                }.frame(width: 24)
                ScrollView(.vertical) {
                    ToolTile(kind: kind, model: model, kit: model.toolkit).contents
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }.frame(width: 460, height: 76)
            }.padding(8).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                guard model.canAccess(kind) else { return }
                if kind == .search { model.toolkit.scanApplications() }
                controller.selectedWidget = kind
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: kind.icon).font(.title3)
                    Text(kind.title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                }.frame(width: 160, height: 84).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel("Open " + kind.title + " from notch")
        }
    }
}

struct NotchSettingsView: View {
    @ObservedObject var model: DockModel
    private let displayLookup: () -> String?
    private let screenChanges: AnyPublisher<Notification, Never>
    @State private var displayName: String?
    init(model: DockModel,
         displayLookup: @escaping () -> String? = { NotchGeometry.compatibleDisplay?.localizedName },
         screenChanges: AnyPublisher<Notification, Never> = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).eraseToAnyPublisher()) {
        self.model = model; self.displayLookup = displayLookup; self.screenChanges = screenChanges
        _displayName = State(initialValue: displayLookup())
    }
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
            StudioNumberControl(title: "Notch width", value: $model.notchWidth, range: 600...1600, step: 20, unit: "pt")
            HStack(spacing: 12) {
                Button("Compact") { model.notchWidth = 640 }
                Button("Balanced") { model.notchWidth = 760 }
                Button("Wide") { model.notchWidth = 1000 }
                Spacer()
                Text("Fits your display · height stays fixed").font(.caption).foregroundStyle(.secondary)
            }
            Text("The resting notch matches your system notch exactly. Hover or click to open a slim horizontal strip. Scroll sideways through Home controls and widgets. The second Files tab holds your tray; dragging files onto the notch opens it automatically. Hides in full screen, on lock, and during sleep.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.primary.opacity(0.07)))
            .onReceive(screenChanges) { _ in displayName = displayLookup() }
    }
}
