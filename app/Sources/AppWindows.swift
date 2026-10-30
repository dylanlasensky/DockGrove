import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppWindowsView: View {
    @ObservedObject var manager: WindowManager
    let app: DockApp
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(app.name) windows").font(.headline)
            Text(manager.status).font(.caption)
            if !manager.trusted { Button("Allow Accessibility", action: manager.requestAccess) }
            Button("Refresh", action: manager.refresh)
            List(manager.windows.filter { $0.owner.bundleURL?.standardizedFileURL.path == app.id }) { window in
                Button(window.title) { manager.selectedID = window.id; manager.focus() }
            }.frame(height: 240)
            Text("Choose a window to restore and bring it forward.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 440).onAppear { manager.refresh() }
    }
}
extension DockModel {
    func showAppWindows(_ app: DockApp) {
        guard canUseFeatures else { settingsAction?(); return }
        appPickerWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "App windows"
        window.contentView = NSHostingView(rootView: AppWindowsView(manager: toolkit.windows, app: app).preferredColorScheme(scheme))
        appPickerWindow = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func acceptFiles(_ providers: [NSItemProvider], for app: DockApp) -> Bool {
        guard canUseFeatures else { return false }
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }
        for provider in supported {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    guard self.canUseFeatures else { return }
                    NSWorkspace.shared.open([url], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        if error != nil { Task { @MainActor in self.systemError = "This app could not open the dropped file." } }
                    }
                }
            }
        }
        return true
    }
}
