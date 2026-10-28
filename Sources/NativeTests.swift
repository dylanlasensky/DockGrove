import AppKit
import SwiftUI

/// Opt-in native rendering checks. Uses isolated preferences and never changes Apple's Dock.
@MainActor func runNativeTests(_ delegate: AppDelegate, output: URL) {
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        delegate.settings.orderOut(nil)
        let model = delegate.model!
        model.toolkit.showRunning = false
        model.toolkit.autoHide = false
        model.toolkit.hideOnOverlap = false
        model.toolkit.enabled = ["search", "focus", "tasks"]
        model.replacingDock = true // Geometry only; no system preference write in test mode.
        delegate.layoutDock()
        precondition(delegate.panel.collectionBehavior.contains(.fullScreenNone))
        precondition(!delegate.panel.collectionBehavior.contains(.fullScreenAuxiliary))
        let screen = NSScreen.screens[max(0, min(NSScreen.screens.count - 1, model.toolkit.screenIndex))]
        precondition(abs(delegate.panel.frame.minY - screen.frame.minY) < 1)
        precondition(delegate.panel.frame.width <= screen.frame.width)
        for kind in ToolKind.allCases where kind != .spacer && kind != .separator {
            let view = NSHostingView(rootView: VStack(alignment: .leading, spacing: 15) {
                Label(kind.title, systemImage: kind.icon).font(.title3.bold())
                ToolTile(kind: kind, model: model, kit: model.toolkit).contents
            }.padding(22).frame(width: 350).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view
            window.center(); window.orderFront(nil)
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            precondition(size.width.isFinite && size.height.isFinite && size.width > 0 && size.width <= 351 && size.height > 0 && size.height < screen.frame.height - 60, "Invalid layout: \(kind)")
            view.setFrameSize(size); window.setContentSize(size); view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output.appendingPathComponent(kind.rawValue + ".png")) }
            }
            window.orderOut(nil)
        }
        model.toolkit.enabled = ToolKind.allCases.map(\.rawValue)
        for iconSize in [32.0, 48, 64] {
            model.iconSize = iconSize
            delegate.layoutDock()
            precondition(delegate.panel.frame.width <= screen.frame.width - 19)
            precondition(delegate.panel.frame.minX >= screen.frame.minX)
            precondition(delegate.panel.frame.maxX <= screen.frame.maxX)
        }
        // Actual window states, not only the pure policy.
        delegate.sessionActive = false; delegate.checkAutoHide(); precondition(!delegate.panel.isVisible)
        delegate.sessionActive = true; delegate.screenAwake = false; delegate.checkAutoHide(); precondition(!delegate.panel.isVisible)
        delegate.screenAwake = true; model.visible = false; delegate.checkAutoHide(); precondition(!delegate.panel.isVisible)
        model.visible = true
        print("PASS: \(ToolKind.allCases.count - 2) widget views rendered, bottom replacement geometry, fullscreen collection policy, session/sleep/manual hiding")
        fflush(stdout)
        // Give timers a chance to run before checking the ordinary desktop presentation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            delegate.checkAutoHide()
            print("Native dock visible on current desktop: \(delegate.panel.isVisible)")
            print("PASS: native rendering and window-state checks completed")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    } catch { fatalError("Native test failure: \(error)") }
}
