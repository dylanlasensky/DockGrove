import AppKit
import ApplicationServices
import SwiftUI

struct ManagedWindow: Identifiable {
    let id: String
    let owner: NSRunningApplication
    let element: AXUIElement
    let title: String
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
    var activate: (NSRunningApplication) -> Void = { $0.activate(options: []) }
    var pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    static var current = AccessibilityClient()
}
@MainActor final class WindowManager: ObservableObject {
    @Published var windows: [ManagedWindow] = []
    @Published var status = "Allow Accessibility to list, move and resize app windows."
    @Published var loading = false
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
    func refresh() {
        guard trusted else { windows = []; status = "Accessibility access is required. Use Allow Accessibility, then Refresh."; return }
        guard !loading else { return }; loading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { Self.discover() }.value
            guard trusted else { windows = []; loading = false; status = "Accessibility permission was removed."; return }
            windows = found
            if !found.contains(where: { $0.id == selectedID }) { selectedID = found.first?.id ?? "" }
            loading = false
            status = found.isEmpty ? "No accessible windows. Open an app window, then Refresh." : "Choose a window and a layout. Some apps enforce a minimum size."
        }
    }
    nonisolated private static func discover() -> [ManagedWindow] {
        let ax = AccessibilityClient.current
        var found: [ManagedWindow] = []
        for app in ax.runningApplications() where app.activationPolicy != .prohibited && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let element = ax.application(app.processIdentifier)
            ax.setTimeout(element, 2)
            guard let list = ax.copy(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in list {
                let role = ax.copy(window, kAXSubroleAttribute)
                guard [kAXStandardWindowSubrole, kAXDialogSubrole].contains(role as? String ?? "") else { continue }
                let name = (ax.copy(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                found.append(ManagedWindow(id: "\(app.processIdentifier):\(CFHash(window))", owner: app, element: window, title: windowTitle(app: app.localizedName, window: name, fallback: "Untitled window")))
            }
        }
        return found.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
        guard !loading, trusted, let selected, !NSScreen.screens.isEmpty, let current = Self.bounds(selected.element) else { status = "Window unavailable. Refresh the window list."; return }
        let full = AccessibilityClient.current.copy(selected.element, "AXFullScreen")
        guard (full as? Bool) != true else { status = "Leave native full screen before arranging this window."; return }
        let screen = NSScreen.screens[min(max(0, displayIndex), NSScreen.screens.count - 1)]
        let target = placement.frame(in: usableFrameProvider?(screen) ?? Self.usableFrame(screen: screen, dockHeight: dockHeight), current: current)
        undo[selected.id] = current // Preserve recovery even if the app accepts only part of the resize.
        arrange(target, selected: selected)
    }
    func snap(_ window: ManagedWindow, target: CGRect, original: CGRect) {
        guard trusted, !loading else { return }
        if !windows.contains(where: { $0.id == window.id }) { windows.append(window) }
        selectedID=window.id; undo[window.id]=original; arrange(target,selected:window)
    }
    private func arrange(_ frame: CGRect, selected: ManagedWindow, undoing: Bool = false) {
        guard !loading else { return }
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
        guard !loading, let selected, let frame = undo[selected.id] else { status = "No previous layout for this window."; return }
        arrange(frame, selected: selected, undoing: true)
    }
    func focus() {
        guard trusted else { status = "Allow Accessibility to select and restore windows."; return }
        guard let selected else { status = "Select a window first."; return }
        let ax = AccessibilityClient.current
        let restored = ax.set(selected.element, kAXMinimizedAttribute, kCFBooleanFalse)
        ax.activate(selected.owner)
        let raised = ax.perform(selected.element, kAXRaiseAction)
        status = raised == .success && (restored == .success || restored == .attributeUnsupported)
            ? "Window brought forward."
            : "This app could not restore or focus the window. Refresh and check Accessibility access."
    }
    func minimize() { guard let selected else { return }; if AccessibilityClient.current.set(selected.element, kAXMinimizedAttribute, kCFBooleanTrue) != .success { status = "This window cannot be minimized." } }
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
            }.disabled(manager.selected == nil || manager.loading)
            HStack { Button("Focus", action: manager.focus); Button("Minimize", action: manager.minimize); Button("Undo layout", action: manager.undoPlacement) }.disabled(manager.selected == nil || manager.loading)
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
