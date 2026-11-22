import AppKit
import ApplicationServices
import SwiftUI

struct ManagedWindow: Identifiable {
    let id: String
    let owner: NSRunningApplication
    let element: AXUIElement
    let title: String
    var isMinimized: Bool = false
}
enum WindowPlacement: String, CaseIterable, Identifiable {
    case left = "Left half", right = "Right half", top = "Top half", bottom = "Bottom half", maximize = "Maximize", center = "Center"
    case topLeft = "Top left", topRight = "Top right", bottomLeft = "Bottom left", bottomRight = "Bottom right"
    var id: String { rawValue }
    func frame(in usable: CGRect, current: CGRect) -> CGRect {
        var rect = usable
        switch self {
        case .left: rect.size.width /= 2
        case .right: rect.size.width /= 2; rect.origin.x += rect.width
        case .top: rect.size.height /= 2
        case .bottom: rect.size.height /= 2; rect.origin.y += rect.height
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            rect.size.width /= 2; rect.size.height /= 2
            if self == .topRight || self == .bottomRight { rect.origin.x += rect.width }
            if self == .bottomLeft || self == .bottomRight { rect.origin.y += rect.height }
        case .center:
            rect.size = CGSize(width: min(current.width, usable.width), height: min(current.height, usable.height))
            rect.origin = CGPoint(x: usable.midX - rect.width / 2, y: usable.midY - rect.height / 2)
        case .maximize: break
        }
        return rect
    }
}
/// Accessibility and window-server calls behind closures so window logic can run against fakes.
/// `copy` returns nil when the attribute could not be read.
struct AccessibilityClient {
    var isTrusted: () -> Bool = AXIsProcessTrusted
    var promptForTrust: () -> Void = { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    var application: (pid_t) -> AXUIElement = AXUIElementCreateApplication
    var systemWide: () -> AXUIElement = AXUIElementCreateSystemWide
    var setTimeout: (AXUIElement, Float) -> Void = { _ = AXUIElementSetMessagingTimeout($0, $1) }
    var copy: (AXUIElement, String) -> CFTypeRef? = { element, attribute in
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    var set: (AXUIElement, String, CFTypeRef) -> AXError = { AXUIElementSetAttributeValue($0, $1 as CFString, $2) }
    var perform: (AXUIElement, String) -> AXError = { AXUIElementPerformAction($0, $1 as CFString) }
    var element: (AXUIElement, CGPoint) -> AXUIElement? = { root, point in
        var hit: AXUIElement?
        return AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) == .success ? hit : nil
    }
    var pid: (AXUIElement) -> pid_t = { var pid: pid_t = 0; AXUIElementGetPid($0, &pid); return pid }
    var runningApplications: () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }
    var runningApplication: (pid_t) -> NSRunningApplication? = { NSRunningApplication(processIdentifier: $0) }
    var activate: (NSRunningApplication) -> Void = { $0.unhide(); $0.activate(options: []) }
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    static var current = AccessibilityClient()
}
@MainActor final class WindowManager: ObservableObject {
    @Published var windows: [ManagedWindow] = []
    @Published var status = "Allow Accessibility to list, move and resize app windows."
    @Published var loading = false
    @Published private(set) var acting = false
    private var discovery: Task<WindowDiscovery, Never>?
    private var discoveryGeneration = 0
    private var appRefreshTimes: [pid_t: TimeInterval] = [:]
    private var discoveryCursor: WindowDiscoveryCursor?
    private var cycleWindowIDs: [pid_t: Set<String>] = [:]
    private var cycleUnavailablePIDs: Set<pid_t> = []
    var overviewWindow: NSWindow?
    @Published var selectedID = ""
    @Published var displayIndex = 0
    private var undo: [String: CGRect] = [:]
    var usableFrameProvider: ((NSScreen)->CGRect)?
    var trusted: Bool { AccessibilityClient.current.isTrusted() }
    var selected: ManagedWindow? { windows.first { $0.id == selectedID } }
    func requestAccess() {
        AccessibilityClient.current.promptForTrust()
        status = "Enable DockGrove in Privacy & Security > Accessibility (Device Control and Data Access on newer macOS), then Refresh."
    }
    func refresh() { refresh(appPID: nil) }
    func refreshIfNeeded(for app: NSRunningApplication) {
        let now = AccessibilityClient.current.uptime()
        guard now - (appRefreshTimes[app.processIdentifier] ?? -.infinity) >= 3 else { return }
        guard !loading, !acting else { return }
        appRefreshTimes[app.processIdentifier] = now
        refresh(appPID: app.processIdentifier)
    }
    func cancelDiscovery() {
        discoveryGeneration += 1
        if discovery != nil { discovery?.cancel(); discovery = nil; loading = false }
    }
    private func refresh(appPID: pid_t?) {
        guard trusted else {
            cancelDiscovery(); discoveryCursor = nil; cycleWindowIDs = [:]; windows = []
            status = "Accessibility access is required. Use Allow Accessibility, then Refresh."
            return
        }
        guard !loading, !acting else { return }
        loading = true
        discoveryGeneration += 1
        let generation = discoveryGeneration, ax = AccessibilityClient.current
        // A full scan resumes where its previous slice stopped. Restarting at the first
        // app on every timer tick permanently starved later apps on busy desktops.
        let cursor = appPID == nil ? discoveryCursor : nil
        if appPID == nil && cursor == nil { cycleWindowIDs = [:]; cycleUnavailablePIDs = [] }
        let worker = Task.detached(priority: .userInitiated) { Self.discover(using: ax, appPID: appPID, startingAt: cursor) }
        discovery = worker
        Task {
            let result = await worker.value
            guard generation == discoveryGeneration else { return }
            discovery = nil; loading = false
            guard trusted else { windows = []; discoveryCursor = nil; status = "Accessibility permission was removed."; return }
            if appPID == nil {
                discoveryCursor = result.cursor
                cycleUnavailablePIDs.formUnion(result.unavailablePIDs)
                for window in result.windows { cycleWindowIDs[window.owner.processIdentifier, default: []].insert(window.id) }
                // Only discard a cached app's windows after that app has been scanned in
                // full. A timed-out or unreadable app must not erase its known windows.
                windows.removeAll { window in
                    let pid = window.owner.processIdentifier
                    return window.owner.isTerminated || !result.livePIDs.contains(pid) || (result.completedPIDs.contains(pid) && !(cycleWindowIDs[pid] ?? []).contains(window.id))
                }
            } else if let appPID, result.completedPIDs.contains(appPID) {
                windows.removeAll { $0.owner.processIdentifier == appPID }
            }
            let updated = Set(result.windows.map(\.id))
            windows.removeAll { updated.contains($0.id) }
            windows += result.windows.filter { !$0.owner.isTerminated }
            windows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if !windows.contains(where: { $0.id == selectedID }) { selectedID = windows.first?.id ?? "" }
            let incomplete = result.partial || (appPID == nil ? !cycleUnavailablePIDs.isEmpty : !result.unavailablePIDs.isEmpty)
            status = result.cursor != nil
                ? "Some apps took too long to respond. Continuing through the remaining windows…"
                : incomplete ? "Some apps did not expose their windows. Cached windows may be outdated; Refresh to try again."
                : windows.isEmpty ? "No accessible windows. Open an app window, then Refresh."
                : "Choose a window to bring it forward. Right-click for window actions."
            // Continue without requiring the user to refresh repeatedly. Every slice is
            // off the main actor and can be cancelled when the overview is dismissed.
            if appPID == nil && result.cursor != nil { refresh(appPID: nil) }
        }
    }
    struct WindowDiscoveryCursor: Equatable {
        let appPID: pid_t
        let windowOffset: Int
    }
    struct WindowDiscovery {
        var windows: [ManagedWindow]
        var partial: Bool
        var cursor: WindowDiscoveryCursor? = nil
        var completedPIDs: Set<pid_t> = []
        var unavailablePIDs: Set<pid_t> = []
        var livePIDs: Set<pid_t>
    }
    nonisolated static func discover(using ax: AccessibilityClient, appPID: pid_t? = nil, startingAt cursor: WindowDiscoveryCursor? = nil) -> WindowDiscovery {
        // Cooperative budget: an in-flight AX call can finish after this deadline.
        let deadline = ax.uptime() + 3
        let apps = ax.runningApplications().filter {
            $0.activationPolicy != .prohibited && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && (appPID == nil || $0.processIdentifier == appPID)
        }
        var result = WindowDiscovery(windows: [], partial: false, livePIDs: Set(apps.map(\.processIdentifier)))
        let start = cursor.flatMap { cursor in apps.firstIndex { $0.processIdentifier == cursor.appPID } } ?? 0
        func expired() -> Bool { Task.isCancelled || ax.uptime() >= deadline }
        func paused(at pid: pid_t, window: Int) -> WindowDiscovery {
            result.partial = true; result.cursor = WindowDiscoveryCursor(appPID: pid, windowOffset: window)
            return result
        }
        for app in apps.dropFirst(start) {
            let pid = app.processIdentifier
            let offset = cursor?.appPID == pid ? cursor!.windowOffset : 0
            guard !expired() else { return paused(at: pid, window: offset) }
            let element = ax.application(pid)
            ax.setTimeout(element, 0.25)
            guard let list = ax.copy(element, kAXWindowsAttribute) as? [AXUIElement] else {
                if app.activationPolicy == .regular { result.unavailablePIDs.insert(pid); result.partial = true }
                continue
            }
            for (index, window) in list.enumerated().dropFirst(min(offset, list.count)) {
                // Timeouts are cooperative. If an app exceeded the whole slice while
                // returning AXWindows, finish one resumed window before yielding again.
                // Otherwise that app could return the identical cursor forever.
                let resumingWindow = cursor?.appPID == pid && cursor?.windowOffset == index
                func canReadWindow() -> Bool { !expired() || (resumingWindow && !Task.isCancelled) }
                guard canReadWindow() else { return paused(at: pid, window: index) }
                ax.setTimeout(window, 0.25)
                let subrole = ax.copy(window, kAXSubroleAttribute) as? String
                // A few Electron and custom toolkit windows omit AXSubrole entirely.
                // Accept actual AXWindow elements, but still exclude floating palettes.
                if ![kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole ?? "") {
                    guard subrole != kAXFloatingWindowSubrole && subrole != "AXSystemFloatingWindow",
                          ax.copy(window, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
                }
                guard canReadWindow() else { return paused(at: pid, window: index) }
                let name = (ax.copy(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard canReadWindow() else { return paused(at: pid, window: index) }
                result.windows.append(ManagedWindow(id: "\(pid):\(CFHash(window))", owner: app, element: window, title: windowTitle(app: app.localizedName, window: name, fallback: "Untitled window"), isMinimized: (ax.copy(window, kAXMinimizedAttribute) as? Bool) == true))
            }
            result.completedPIDs.insert(pid)
        }
        return result
    }
    nonisolated static func windowTitle(app: String?, window: String?, fallback: String) -> String {
        (app ?? "App") + " · " + (window ?? fallback)
    }
    /// Top of the primary display, the origin flip between AppKit and Accessibility coordinates.
    static func globalTop(_ screens: [NSScreen] = NSScreen.screens) -> CGFloat { screens.first?.frame.maxY ?? 0 }
    nonisolated static func bounds(_ window: AXUIElement) -> CGRect? {
        let ax = AccessibilityClient.current
        guard let p = ax.copy(window, kAXPositionAttribute), let s = ax.copy(window, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func usableFrame(screen: NSScreen, dockHeight: CGFloat) -> CGRect {
        let globalTop = globalTop()
        var usable = screen.visibleFrame
        // visibleFrame already reserves Apple's Dock in companion mode.
        usable.origin.y += dockHeight; usable.size.height = max(100, usable.height - dockHeight)
        return CGRect(x: usable.minX, y: globalTop - usable.maxY, width: usable.width, height: usable.height)
    }
    func place(_ placement: WindowPlacement, dockHeight: CGFloat = 0) {
        guard !loading, !acting else { return }
        guard trusted, let selected, !NSScreen.screens.isEmpty else { status = "Window unavailable. Refresh the window list."; return }
        let screen = NSScreen.screens[min(max(0, displayIndex), NSScreen.screens.count - 1)]
        let usable = usableFrameProvider?(screen) ?? Self.usableFrame(screen: screen, dockHeight: dockHeight)
        let ax = AccessibilityClient.current
        loading = true; status = "Checking window…"
        Task {
            let preflight = await Task.detached(priority: .userInitiated) {
                ax.setTimeout(selected.element, 0.5)
                return (Self.bounds(selected.element), (ax.copy(selected.element, "AXFullScreen") as? Bool) == true)
            }.value
            loading = false
            guard trusted else { status = "Accessibility permission was removed."; return }
            guard let current = preflight.0 else { status = "Window unavailable. Refresh the window list."; return }
            guard !preflight.1 else { status = "Leave native full screen before arranging this window."; return }
            undo[selected.id] = current // Preserve recovery even after a partially accepted resize.
            arrange(placement.frame(in: usable, current: current), selected: selected)
        }
    }
    func snap(_ window: ManagedWindow, target: CGRect, original: CGRect) {
        guard trusted, !loading, !acting else { return }
        if !windows.contains(where: { $0.id == window.id }) { windows.append(window) }
        selectedID=window.id; undo[window.id]=original; arrange(target,selected:window)
    }
    private func arrange(_ frame: CGRect, selected: ManagedWindow, undoing: Bool = false) {
        guard !loading, !acting else { return }
        loading = true; status = "Arranging window…"
        AccessibilityClient.current.activate(selected.owner)
        let element = selected.element, id = selected.id, pid = selected.owner.processIdentifier
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                WindowFrameWriter.apply(frame, window: element, pid: pid)
            }.value
            loading = false
            switch result {
            case .arranged:
                status = undoing ? "Previous layout restored." : "Window arranged. Undo is available."
                if undoing { undo.removeValue(forKey: id) }
            case .constrained(let actual):
                status = "This app limits its window to \(Int(actual.width)) × \(Int(actual.height)). Try a larger layout; Undo is available."
            case .unavailable:
                status = "The app refused this layout. Refresh its window or check Accessibility access. Undo is available."
            }
        }
    }
    func undoPlacement() {
        guard !loading, !acting, let selected, let frame = undo[selected.id] else { status = "No previous layout for this window."; return }
        arrange(frame, selected: selected, undoing: true)
    }
    @discardableResult func focus() async -> Bool {
        guard trusted else { status = "Allow Accessibility to select and restore windows."; return false }
        guard !acting, !loading || discovery != nil else { return false }
        guard let selected else { status = "Select a window first."; return false }
        cancelDiscovery(); acting = true; status = "Restoring window…"
        defer { acting = false }
        let ax = AccessibilityClient.current
        let restored = await Task.detached(priority: .userInitiated) {
            ax.setTimeout(selected.element, 0.5)
            let wasMinimized = (ax.copy(selected.element, kAXMinimizedAttribute) as? Bool) ?? selected.isMinimized
            return (wasMinimized, ax.set(selected.element, kAXMinimizedAttribute, kCFBooleanFalse))
        }.value
        guard trusted else { windows = []; status = "Accessibility permission was removed."; return false }
        ax.activate(selected.owner)
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            let raised = ax.perform(selected.element, kAXRaiseAction)
            if restored.0 {
                guard restored.1 == .success else { return nil }
                // AX acknowledgements can arrive before an app actually restores its
                // window. Confirm the state, with a short bounded settling period.
                for attempt in 0..<4 {
                    if (ax.copy(selected.element, kAXMinimizedAttribute) as? Bool) == false {
                        return raised == .success ? "Window brought forward." : "Window restored."
                    }
                    if attempt < 3 { ax.pause(0.05) }
                }
                return nil
            }
            if raised == .success && (restored.1 == .success || restored.1 == .attributeUnsupported) { return "Window brought forward." }
            return nil
        }.value
        guard trusted else { windows = []; status = "Accessibility permission was removed."; return false }
        status = result ?? "This app could not restore or focus the window. Refresh and check Accessibility access."
        if result != nil, let index = windows.firstIndex(where: { $0.id == selected.id }) { windows[index].isMinimized = false }
        return result != nil
    }
    func minimize() async {
        guard trusted else { status = "Allow Accessibility to minimize windows."; return }
        guard !acting, !loading || discovery != nil, let selected else { return }
        cancelDiscovery(); acting = true; status = "Minimizing window…"
        defer { acting = false }
        let ax = AccessibilityClient.current
        let minimized = await Task.detached(priority: .userInitiated) {
            ax.setTimeout(selected.element, 0.5)
            return ax.set(selected.element, kAXMinimizedAttribute, kCFBooleanTrue) == .success && (ax.copy(selected.element, kAXMinimizedAttribute) as? Bool) == true
        }.value
        guard trusted else { windows = []; status = "Accessibility permission was removed."; return }
        status = minimized ? "Window minimized." : "This window cannot be minimized."
        if minimized, let index = windows.firstIndex(where: { $0.id == selected.id }) { windows[index].isMinimized = true }
    }

}
struct WindowManagerView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var model: DockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(manager.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !manager.trusted { Button("Allow Accessibility", action: manager.requestAccess) }
            Button(manager.loading ? "Finding windows…" : "Refresh windows", action: manager.refresh).disabled(manager.loading)
            Picker("Window", selection: $manager.selectedID) { Text("Select a window").tag(""); ForEach(manager.windows) { Text($0.title).tag($0.id) } }
            Picker("Move to display", selection: $manager.displayIndex) { ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { i, screen in Text(screen.localizedName).tag(i) } }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(WindowPlacement.allCases) { placement in Button(placement.rawValue) { manager.place(placement, dockHeight: model.replacingDock && !model.toolkit.autoHide && manager.displayIndex == min(max(0, model.toolkit.screenIndex), max(0, NSScreen.screens.count - 1)) ? model.dockHeight : 0) }.frame(maxWidth: .infinity) }
            }.disabled(manager.selected == nil || manager.loading || manager.acting)
            HStack { Button("Focus") { Task { await manager.focus() } }; Button("Minimize") { Task { await manager.minimize() } }; Button("Undo layout", action: manager.undoPlacement) }.disabled(manager.selected == nil || manager.loading || manager.acting)
        }.onAppear { if manager.trusted { manager.refresh() } }
    }
}

/// AX writes are acknowledged before many apps have completed layout. Wait off the main
/// thread, then retry size-position-size for apps that clamp moves to their old size.
enum WindowFrameWriter {
    enum Result { case arranged, constrained(CGRect), unavailable }
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 4 && abs(a.minY - b.minY) <= 4 && abs(a.width - b.width) <= 4 && abs(a.height - b.height) <= 4
    }
    static func settle(target: CGRect, write: () -> Bool, read: () -> CGRect?, pause: () -> Void) -> Result {
        var accepted = false
        for _ in 0..<3 {
            accepted = write() || accepted
            for _ in 0..<6 {
                pause()
                if let actual = read(), matches(actual, target) { return .arranged }
            }
        }
        if accepted, let actual = read() { return .constrained(actual) }
        return .unavailable
    }
    static func apply(_ frame: CGRect, window: AXUIElement, pid: pid_t) -> Result {
        let ax = AccessibilityClient.current
        let app = ax.application(pid)
        ax.setTimeout(window, 1)
        ax.setTimeout(app, 1)
        // Electron and some accessibility clients change resize behavior while enhanced
        // UI is enabled. Restore the exact value, and only touch it when it was enabled.
        let enhancedKey = "AXEnhancedUserInterface"
        let restoreEnhanced = (ax.copy(app, enhancedKey) as? Bool) == true
        if restoreEnhanced { _ = ax.set(app, enhancedKey, kCFBooleanFalse) }
        defer { if restoreEnhanced { _ = ax.set(app, enhancedKey, kCFBooleanTrue) } }
        _ = ax.set(window, kAXMinimizedAttribute, kCFBooleanFalse)
        _ = ax.perform(window, kAXRaiseAction)
        return settle(target: frame, write: {
            var point = frame.origin, size = frame.size
            guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { return false }
            let firstSize = ax.set(window, kAXSizeAttribute, s)
            let move = ax.set(window, kAXPositionAttribute, p)
            let secondSize = ax.set(window, kAXSizeAttribute, s)
            return move == .success && (firstSize == .success || secondSize == .success)
        }, read: { WindowManager.bounds(window) }, pause: { ax.pause(0.08) })
    }
}
