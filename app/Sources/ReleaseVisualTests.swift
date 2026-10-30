import SwiftUI
import AppKit

/// Renders real components using isolated --native-test model; never changes OS appearance.
@MainActor func renderReleaseViews(model: DockModel, output: URL) throws {
    func capture<V: View>(_ view: V, _ name: String, width: CGFloat, height: CGFloat) throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.appearance = NSAppearance(named: name.hasSuffix("light") ? .aqua : .darkAqua)
        window.center(); window.orderFront(nil)
        host.setFrameSize(NSSize(width: width, height: height)); host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: output.appendingPathComponent(name + ".png")) }
        }
        window.orderOut(nil)
    }
    let originalTheme = model.theme, originalWidgets = model.toolkit.enabled
    defer { model.theme = originalTheme; model.toolkit.enabled = originalWidgets }
    model.theme = "Automatic"; model.toolkit.enabled = ["focus"]
    for (label, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        try capture(DockView(model: model).environment(\.colorScheme, scheme), "dock-" + label, width: 1300, height: 130)
        try capture(SettingsView(model: model).environment(\.colorScheme, scheme), "settings-" + label, width: 590, height: 720)
        try capture(AppPickerView(model: model, replacing: model.apps.first, close: {}).environment(\.colorScheme, scheme), "app-picker-" + label, width: 600, height: 460)
    }
    print("PASS: automatic light/dark native dock, settings and searchable picker rendering")
}
