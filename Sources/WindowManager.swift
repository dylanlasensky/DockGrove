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
@MainActor final class WindowManager: ObservableObject {
    @Published var windows: [ManagedWindow] = []
    @Published var status = "Allow Accessibility to list, move and resize app windows."
    @Published var loading = false
    @Published var selectedID = ""
    @Published var displayIndex = 0
    private var undo: [String: CGRect] = [:]
    var trusted: Bool { AXIsProcessTrusted() }
    var selected: ManagedWindow? { windows.first { $0.id == selectedID } }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        status = "Enable WaveDock in Privacy & Security > Accessibility (Device Control and Data Access on newer macOS), then Refresh."
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
        var found: [ManagedWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 2)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success, let list = value as? [AXUIElement] else { continue }
            for window in list {
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &role)
                guard [kAXStandardWindowSubrole, kAXDialogSubrole].contains(role as? String ?? "") else { continue }
                var title: CFTypeRef?; AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                let name = (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window"
                found.append(ManagedWindow(id: "\(app.processIdentifier):\(CFHash(window))", owner: app, element: window, title: "\(app.localizedName ?? "App") · \(name)"))
            }
        }
        return found.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    static func bounds(_ window: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func usableFrame(screen: NSScreen, dockHeight: CGFloat) -> CGRect {
        let globalTop = NSScreen.screens.first?.frame.maxY ?? 0
        var usable = screen.visibleFrame
        // visibleFrame already reserves Apple's Dock in companion mode.
        usable.origin.y += dockHeight; usable.size.height = max(100, usable.height - dockHeight)
        return CGRect(x: usable.minX, y: globalTop - usable.maxY, width: usable.width, height: usable.height)
    }
    func place(_ placement: WindowPlacement, dockHeight: CGFloat = 0) {
        guard trusted, let selected, !NSScreen.screens.isEmpty, let current = Self.bounds(selected.element) else { status = "Window unavailable. Refresh the window list."; return }
        var full: CFTypeRef?
        AXUIElementCopyAttributeValue(selected.element, "AXFullScreen" as CFString, &full)
        guard (full as? Bool) != true else { status = "Leave native full screen before arranging this window."; return }
        let screen = NSScreen.screens[min(max(0, displayIndex), NSScreen.screens.count - 1)]
        let target = placement.frame(in: Self.usableFrame(screen: screen, dockHeight: dockHeight), current: current)
        undo[selected.id] = current // Preserve recovery even if the app accepts only part of the resize.
        if setFrame(target, window: selected.element) { selected.owner.activate(options: []); AXUIElementPerformAction(selected.element, kAXRaiseAction as CFString) }
    }
    @discardableResult private func setFrame(_ frame: CGRect, window: AXUIElement) -> Bool {
        var point = frame.origin, size = frame.size
        guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { return false }
        _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        guard moved == .success, sized == .success else { status = "This window refused part of the move or resize. Use Undo to restore the previous layout."; return false }
        if let actual = Self.bounds(window), abs(actual.width - frame.width) > 4 || abs(actual.height - frame.height) > 4 || abs(actual.minX - frame.minX) > 4 || abs(actual.minY - frame.minY) > 4 { status = "The app constrained the requested size or position. Undo is available." }
        else { status = "Window arranged. Use Undo to restore its previous size." }
        return true
    }
    func undoPlacement() { guard let selected, let frame = undo[selected.id] else { status = "No previous layout for this window."; return }; if setFrame(frame, window: selected.element) { undo.removeValue(forKey: selected.id) } }
    func focus() { guard let selected else { return }; _ = AXUIElementSetAttributeValue(selected.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse); selected.owner.activate(options: []); AXUIElementPerformAction(selected.element, kAXRaiseAction as CFString) }
    func minimize() { guard let selected else { return }; if AXUIElementSetAttributeValue(selected.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) != .success { status = "This window cannot be minimized." } }
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
                ForEach(WindowPlacement.allCases) { placement in Button(placement.rawValue) { manager.place(placement, dockHeight: model.replacingDock && !model.toolkit.autoHide && manager.displayIndex == model.toolkit.screenIndex ? model.iconSize + 56 : 0) }.frame(maxWidth: .infinity) }
            }.disabled(manager.selected == nil)
            HStack { Button("Focus", action: manager.focus); Button("Minimize", action: manager.minimize); Button("Undo layout", action: manager.undoPlacement) }.disabled(manager.selected == nil)
        }.onAppear { if manager.trusted { manager.refresh() } }
    }
}
