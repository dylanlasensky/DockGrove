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

/// Decides when the pointer opens or closes the notch. Only a notch the pointer (or a file drag)
/// opened closes by itself; one the user clicked open stays until a click, Esc or an outside click.
struct NotchHoverState {
    private var started: TimeInterval?
    private var lastInside: TimeInterval = 0
    private var openedByHover = false
    private var openedByDrag = false
    private var armed = true
    /// True while the open notch belongs to the pointer and may close when it leaves.
    var hoverOwned: Bool { openedByHover }
    mutating func beginDrag(now: TimeInterval, alreadyExpanded: Bool) {
        if !alreadyExpanded { openedByHover = true; openedByDrag = true; lastInside = now; started = nil }
    }
    /// A click, Esc or code opened or closed the notch: the pointer no longer owns it, and after a
    /// close the pointer must leave the notch before hovering can open it again.
    mutating func manualChange(expanded: Bool) {
        started = nil; openedByHover = false; openedByDrag = false; armed = expanded
    }
    /// A file drag always closes when it leaves, even with close-on-exit off, so dragging across the
    /// top of the screen (or finishing a drop) never strands an open tray.
    mutating func update(now: TimeInterval, trigger: Bool, inside: Bool, expanded: Bool, interacting: Bool, opensOnEnter: Bool = true, closesOnExit: Bool = true) -> Bool? {
        if !trigger { armed = true; started = nil }
        if expanded {
            // While leaving cannot close the notch, keep the grace timer fresh so re-enabling the
            // option starts a full grace period instead of snapping shut.
            if inside || interacting || !(closesOnExit || openedByDrag) { lastInside = now }
            else if openedByHover && now - lastInside >= 0.7 {
                openedByHover = false; openedByDrag = false; started = nil; return false
            }
        } else if opensOnEnter && trigger && armed {
            let begin = started ?? now
            started = begin
            if now - begin >= 0.18 {
                started = nil; lastInside = now; openedByHover = true; return true
            }
        } else { started = nil }
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

/// Something that should close an open notch: a mouse-down (in the notch panel or anywhere else)
/// or the Esc key.
enum NotchDismissEvent: Equatable { case pointerDown(insidePanel: Bool), escape }

@MainActor final class NotchController: NSObject, ObservableObject, NSSharingServiceDelegate {
    @Published var expanded = false { didSet { if expanded != oldValue { syncDismissMonitors() } } }
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
    /// Installs the Esc and click-outside monitors while the notch is open; tests inject fakes.
    var installDismissMonitors: (NSWindow?, @escaping (NotchDismissEvent) -> Bool) -> [Any] = NotchController.installEventMonitors
    var removeDismissMonitor: (Any) -> Void = { NSEvent.removeMonitor($0) }
    private var dismissMonitors: [Any] = []
    private func syncDismissMonitors() {
        if expanded, dismissMonitors.isEmpty {
            dismissMonitors = installDismissMonitors(panel) { [weak self] event in self.map { $0.dismiss(event) } == true }
        } else if !expanded {
            dismissMonitors.forEach(removeDismissMonitor); dismissMonitors = []
        }
    }
    /// Local monitors see clicks and keys in DockGrove's own windows; global ones see clicks in other
    /// apps (and Esc there, when the app is trusted for accessibility). Esc typed in another
    /// DockGrove window is left to that window.
    static func installEventMonitors(panel: NSWindow?, handler: @escaping (NotchDismissEvent) -> Bool) -> [Any] {
        weak var panel = panel
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let monitors: [Any?] = [
            NSEvent.addLocalMonitorForEvents(matching: mouse) { event in
                MainActor.assumeIsolated { _ = handler(.pointerDown(insidePanel: event.window != nil && event.window === panel)) }
                return event
            },
            NSEvent.addGlobalMonitorForEvents(matching: mouse) { _ in
                MainActor.assumeIsolated { _ = handler(.pointerDown(insidePanel: false)) }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.window === panel else { return event }
                return MainActor.assumeIsolated { handler(.escape) } ? nil : event
            },
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return }
                MainActor.assumeIsolated { _ = handler(.escape) }
            },
        ]
        return monitors.compactMap { $0 }
    }
    /// Closes the open notch for Esc or a click outside it, whichever options are set. Clicks
    /// inside the panel belong to its controls, and nothing closes while a file picker, AirDrop or
    /// a file drag is in progress, since their own windows sit outside the notch.
    @discardableResult func dismiss(_ event: NotchDismissEvent) -> Bool {
        guard expanded, !choosingFiles, !airDropBusy, !fileDragActive else { return false }
        if case .pointerDown(let insidePanel) = event, insidePanel || panel.frame.contains(mouseLocation()) { return false }
        setExpanded(false)
        return true
    }
    /// Clicking the resting notch opens it; clicking the notch housing of the open strip closes it.
    /// This is the only way to open the notch when opening on hover is off.
    func toggleFromClick() { setExpanded(!expanded) }
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
        hover.beginDrag(now: clock(), alreadyExpanded: expanded)
        setExpanded(true, fromHover: true); showingFiles = true; fileDragActive = true; activeDropDestination = destination
    }
    @discardableResult func acceptFiles(_ urls: [URL]) -> Bool {
        defer { fileDragActive = false; activeDropDestination = nil }
        guard canAcceptFiles else { return false }
        let valid = NotchFileIntake.existingURLs(urls)
        guard !valid.isEmpty else { trayMessage = "Drop existing files or folders from Finder."; return false }
        // A drag-opened tray stays owned by the pointer, so it still closes once the pointer leaves.
        if !expanded { setExpanded(true) }
        showingFiles = true
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
        guard panel.isVisible || expanded || fileDragActive || activeDropDestination != nil || selectedWidget != nil else { return }
        hover = NotchHoverState(); fileDragActive = false; activeDropDestination = nil
        selectedWidget = nil
        if expanded { expanded = false }
        panel.orderOut(nil); panel.ignoresMouseEvents = true
    }
    func update(suppressed: Bool, windows: [[String: Any]]? = nil) {
        guard model.notchEnabled, model.visible, model.canUseFeatures, !suppressed,
              let display = compatibleDisplay(), let geometry = NotchGeometry(display: display),
              !Self.fullscreen(on: display, windows: windows ?? CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) else { hide(); geometry = nil; return }
        if let selectedWidget, !model.canAccess(selectedWidget) { self.selectedWidget = nil }
        if geometry != self.geometry { setExpanded(false); self.geometry = geometry }
        let mouse = mouseLocation()
        if let expand = hover.update(now: clock(),
                                     trigger: geometry.panelFrame(expanded: false).contains(mouse),
                                     inside: panel.frame.contains(mouse), expanded: expanded,
                                     interacting: selectedWidget != nil || fileDragActive || choosingFiles || airDropService != nil,
                                     opensOnEnter: model.notchOpensOnHover, closesOnExit: model.notchClosesOnExit) {
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

/// Packs items left to right into slides no wider than the expanded notch, so the shelf pages
/// with pills instead of scrolling. An item wider than a slide gets a slide of its own.
enum NotchPaging {
    static func pages(_ widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [Range<Int>] {
        var pages: [Range<Int>] = [], start = 0, used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if index > start, used + spacing + width > available {
                pages.append(start..<index); start = index; used = width
            } else { used += (index > start ? spacing : 0) + width }
        }
        if start < widths.count { pages.append(start..<widths.count) }
        return pages.isEmpty ? [0..<0] : pages
    }
}

/// Full widget controls keep their natural text and hit-target sizes. The compact
/// notch stays a launcher; longer controls scroll in a regular, resizable window.
struct NotchWidgetControls: View {
    let kind: ToolKind
    @ObservedObject var model: DockModel
    @StateObject private var interaction = TileInteraction()
    var body: some View {
        ScrollView {
            ToolTileContents(kind: kind, model: model, kit: model.toolkit, interaction: interaction)
                .environment(\.connectionSettingsAction, { model.openConnectionSettings(kind) })
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }.preferredColorScheme(model.scheme)
    }
}

extension DockModel {
    func showNotchWidgetControls(_ kind: ToolKind) {
        guard canAccess(kind) else { settingsAction?(); return }
        appPickerWindow?.close()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = kind.title
        let content = NSHostingView(rootView: NotchWidgetControls(kind: kind, model: self))
        // AppKit owns the window limits; scrolling content must not replace them.
        content.sizingOptions = []
        window.contentView = content
        window.contentMinSize = CGSize(width: 360, height: 240)
        appPickerWindow = window
        window.center()
        DockSystemEffect.handler(.present(window))
    }
}

/// Counts the tray's files and clears them; it observes the toolkit so the count stays live.
struct NotchTrayHeader: View {
    @ObservedObject var kit: Toolkit
    let controller: NotchController
    var body: some View {
        let count = kit.files.count, title = "File tray" + (count == 0 ? "" : " · \(count) file\(count == 1 ? "" : "s")")
        Label(title, systemImage: "tray").font(.caption)
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
            .contextMenu { if count > 0 { Button("Clear tray", action: clear) } }
            .accessibilityAction(named: Text("Clear tray"), clear)
    }
    private func clear() { kit.files.removeAll(); controller.trayMessage = "Original files are unchanged." }
}

struct NotchShelfView: View {
    enum Item: Hashable { case home, widget(ToolKind), noMatches, tray(NotchTrayItem) }
    @ObservedObject var model: DockModel
    @ObservedObject var controller: NotchController
    @State private var query = ""
    @State private var page = 0
    @State private var forward = true
    private var search: String { AppSearchIndex.fold(query) }
    private var widgets: [ToolKind] {
        model.notchWidgets.filter { $0 != .files && (search.isEmpty || AppSearchIndex.fold($0.title).contains(search)) }
    }
    private var items: [Item] {
        if controller.showingFiles { return NotchTrayItem.items(model: model, kit: model.toolkit).map(Item.tray) }
        let found = widgets.map(Item.widget)
        return (search.isEmpty ? [.home] : []) + (found.isEmpty ? [.noMatches] : found)
    }
    private var spacing: CGFloat { controller.showingFiles ? 10 : 14 }
    private func width(_ item: Item) -> CGFloat {
        switch item {
        case .home: 540  // music card or focus placeholder (320) + spacing + focus timer (208)
        case .widget(let kind): controller.selectedWidget == kind ? 512 : 160
        case .noMatches: 200
        case .tray(let tray): tray.width(controller.expandedWidth)
        }
    }
    private var pages: [Range<Int>] { NotchPaging.pages(items.map(width), available: controller.expandedWidth - 32, spacing: spacing) }
    var body: some View {
        let items = items, pages = pages, current = min(page, pages.count - 1)
        VStack(spacing: 0) {
            if controller.expanded {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        if controller.showingFiles {
                            NotchTrayHeader(kit: model.toolkit, controller: controller)
                            Spacer()
                        } else {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find a widget", text: $query).textFieldStyle(.plain).font(.caption)
                        }
                    }.padding(.leading, 16).frame(maxWidth: .infinity)
                    // Clicking the camera housing again closes the strip, mirroring the click that opened it.
                    Button { controller.toggleFromClick() } label: { Color.clear.contentShape(Rectangle()) }
                        .frame(width: controller.geometry?.housing.width ?? 185).accessibilityLabel("Close notch")
                    HStack {
                        Spacer()
                        tab("Home", files: false)
                        tab("Files", files: true)
                        Button { controller.setExpanded(false) } label: { Image(systemName: "chevron.up").padding(8) }.accessibilityLabel("Collapse notch")
                    }.padding(.trailing, 8).frame(maxWidth: .infinity)
                }.frame(height: controller.geometry?.housing.height ?? 32)
                VStack(spacing: 6) {
                    HStack(spacing: spacing) {
                        ForEach(items[pages[current]], id: \.self) { item($0) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).frame(height: 84)
                        .id(current).transition(.push(from: forward ? .trailing : .leading))
                    pills(count: pages.count, current: current)
                }.padding(.top, 6).frame(height: 112, alignment: .top).clipped()
                    .onChange(of: controller.showingFiles) { _, _ in show(0) }
                    .onChange(of: controller.airDropReview) { _, _ in show(0) }
                    .onChange(of: query) { _, _ in show(0) }
                    .onChange(of: controller.selectedWidget) { _, kind in
                        if let kind, let index = items.firstIndex(of: .widget(kind)), let slide = pages.firstIndex(where: { $0.contains(index) }) { show(slide) }
                    }
            } else {
                Button { controller.toggleFromClick() } label: { Color.black.contentShape(Rectangle()) }.accessibilityLabel("Expand DockGrove notch")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white).background(.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: controller.expanded ? 20 : 10, bottomTrailingRadius: controller.expanded ? 20 : 10))
            .overlay {
                if controller.fileDragActive { RoundedRectangle(cornerRadius: 18).stroke(.green.opacity(0.6), lineWidth: 2).padding(2).allowsHitTesting(false) }
            }
            .buttonStyle(.plain).preferredColorScheme(.dark)
    }
    private func show(_ slide: Int) {
        forward = slide >= page
        withAnimation(.snappy(duration: 0.28)) { page = slide }
    }
    /// Slide pills: the current slide is a wide pill, the others are dots; each one jumps to its slide.
    private func pills(count: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button { show(index) } label: {
                    Capsule().fill(.white.opacity(index == current ? 0.9 : 0.3))
                        .frame(width: index == current ? 18 : 6, height: 6).padding(.vertical, 4).padding(.horizontal, 1).contentShape(Rectangle())
                }.accessibilityLabel("Notch slide \(index + 1) of \(count)")
                    .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }.frame(height: 14).opacity(count > 1 ? 1 : 0).accessibilityHidden(count < 2)
    }
    @ViewBuilder private func item(_ item: Item) -> some View {
        switch item {
        case .home: NotchHomeView(model: model, kit: model.toolkit, controller: controller)
        case .widget(let kind): widget(kind)
        case .noMatches: Text("No matching widgets").font(.caption).foregroundStyle(.secondary).frame(width: 200)
        case .tray(let tray): NotchTrayView(model: model, kit: model.toolkit, controller: controller, item: tray)
        }
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
    @ViewBuilder private func widget(_ kind: ToolKind) -> some View {
        if controller.selectedWidget == kind {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    Image(systemName: kind.icon)
                    Button { controller.selectedWidget = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Close " + kind.title + " controls")
                }.frame(width: 24)
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.title).font(.headline)
                    Button("Open controls") { model.showNotchWidgetControls(kind) }
                        .accessibilityLabel("Open full " + kind.title + " controls")
                }.frame(width: 460, height: 68, alignment: .leading)
            }.padding(8).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                guard model.canAccess(kind) else { return }
                if kind == .search { model.showAppLauncher(query: model.toolkit.query); return }
                controller.selectedWidget = kind
                model.showNotchWidgetControls(kind)
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
    static func openCaption(onHover: Bool) -> String {
        onHover ? "Opens after a brief pause under the pointer. You can also click the notch." : "Click the notch to open it."
    }
    static func closeCaption(onExit: Bool) -> String {
        onExit ? "Closes shortly after the pointer moves away, unless you clicked it open. Click outside or press Esc to close it sooner."
               : "Click outside or press Esc to close. Clicking the notch again closes it too; a tray opened by dragging files still closes when you move away."
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
                    Toggle("Enable notch access", isOn: $model.notchEnabled).toggleStyle(.switch).disabled(displayName == nil && !model.notchEnabled)
                    Text(displayName.map { "Open your Dock widgets from the notch on " + $0 + "." } ?? "Connect a display with a built-in camera notch to use this feature.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.notchEnabled && displayName != nil { Button("Open notch") { model.openNotchAction?() } }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open when the pointer reaches the notch", isOn: $model.notchOpensOnHover)
                Text(Self.openCaption(onHover: model.notchOpensOnHover))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Close when the pointer leaves", isOn: $model.notchClosesOnExit)
                Text(Self.closeCaption(onExit: model.notchClosesOnExit))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.toggleStyle(.switch).disabled(!model.notchEnabled)
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
