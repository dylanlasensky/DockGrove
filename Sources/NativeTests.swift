import AppKit
import SwiftUI

/// Opt-in native rendering checks. Uses isolated preferences and never changes Apple's Dock.
@MainActor func runNativeTests(_ delegate: AppDelegate, output: URL) {
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        delegate.settings.orderOut(nil)
        let edit = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Edit" })?.submenu
        precondition(edit?.items.contains(where: { $0.action == Selector(("selectAll:")) && $0.keyEquivalent == "a" }) == true)
        precondition(edit?.items.contains(where: { $0.action == Selector(("paste:")) && $0.keyEquivalent == "v" }) == true)
        let model = delegate.model!
        model.widthFraction=1; model.alignment=0.5; model.theme="Glass"; model.toolkit.edge="Bottom"
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
        // Populated AI states must fit too; long Gemini lists scroll inside the popover.
        for provider in [LocalAIProvider.claude, .gemini] {
            let widget = LocalAIWidget(provider)
            widget.report = LocalAIReport(provider: provider.rawValue, observed: Date().addingTimeInterval(-3600),
                windows: provider == .claude ? ["5-hour window", "Weekly window", "Gateway spend limit"].map { LocalAIWindow(name: $0, used: 24, resets: Date().addingTimeInterval(3600)) } : [],
                models: provider == .gemini ? (0..<20).map { LocalAIModel(name: "gemini-sample-model-\($0)", total: 130, input: 60, output: 30, cached: 40, requests: 2) } : [], sessionCost: provider == .claude ? 0.12 : nil)
            widget.status = "SAMPLE DATA · Last received an hour ago"
            let view = NSHostingView(rootView: LocalAIUsageView(widget: widget, automaticallyRefresh: false).padding(22).frame(width: 350).preferredColorScheme(.dark))
            let size = view.fittingSize
            precondition(size.width <= 351 && size.height < screen.frame.height - 60, "Populated AI view does not fit")
            view.setFrameSize(size); view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output.appendingPathComponent(provider.rawValue + "-populated.png")) } }
        }
        // Inspect every illustrated animal and all six poses on contrasting surfaces.
        for animal in Companion.animals {
            let frames = CompanionArtwork.frames(animal)
            let portrait = NSHostingView(rootView: VStack(spacing:12) {
                Text(animal).font(.title2.bold())
                ForEach(0..<2) { row in
                    HStack { ForEach(0..<3) { col in
                        Image(nsImage:frames[row*3+col]).resizable().scaledToFit().frame(width:160,height:160)
                    } }
                }
            }.padding(18).background(animal == "Black cat" ? Color(white:0.85) : Color(white:0.12)).foregroundStyle(.orange))
            portrait.setFrameSize(portrait.fittingSize); portrait.layoutSubtreeIfNeeded()
            if let bitmap = portrait.bitmapImageRepForCachingDisplay(in:portrait.bounds) {
                portrait.cacheDisplay(in:portrait.bounds,to:bitmap)
                if let data = bitmap.representation(using:.png,properties:[:]) { try data.write(to:output.appendingPathComponent("companion-"+animal+".png")) }
            }
        }
        model.toolkit.enabled = ToolKind.allCases.map(\.rawValue)
        for iconSize in [32.0, 48, 64] {
            model.iconSize = iconSize
            // A fresh host synchronously measures each size; Published updates settle on the next run-loop turn.
            delegate.panel.contentView = NSHostingView(rootView: DockView(model: model))
            delegate.layoutDock()
            if abs(delegate.panel.frame.height - model.dockHeight) >= 1 { print("FAIL: Dock height actual=\(delegate.panel.frame.height) reserved=\(model.dockHeight)"); fflush(stdout); preconditionFailure("Dock height mismatch") }
            precondition(delegate.panel.frame.width <= screen.frame.width - 19)
            precondition(delegate.panel.frame.minX >= screen.frame.minX)
            precondition(delegate.panel.frame.maxX <= screen.frame.maxX)
        }
        // Independent panels retain separate layouts and all obey suppression.
        delegate.workspace.add(); delegate.workspace.add(); delegate.workspace.add(); delegate.workspace.add()
        precondition(delegate.workspace.docks.count == 3)
        for (index,dock) in delegate.workspace.docks.enumerated() {
            dock.model.widthFraction=0.35; dock.model.theme=index == 0 ? "Pearl" : "Graphite"
            dock.model.toolkit.enabled=["pet","spotify","focus"]; dock.model.alignment=Double(index)/2
            dock.panel.contentView=NSHostingView(rootView:DockView(model:dock.model)); delegate.layout(dock.panel,model:dock.model)
            precondition(screen.frame.contains(dock.panel.frame)); precondition(dock.panel.collectionBehavior.contains(.fullScreenNone))
            precondition(dock.model !== model && dock.model.toolkit !== model.toolkit)
        }
        delegate.sessionActive=false; delegate.checkAutoHide(); precondition(delegate.workspace.docks.allSatisfy { !$0.panel.isVisible })
        delegate.sessionActive=true; delegate.screenAwake=false; delegate.checkAutoHide(); precondition(delegate.workspace.docks.allSatisfy { !$0.panel.isVisible })
        delegate.screenAwake=true
        let ids=delegate.workspace.docks.map(\.id)
        for id in ids { delegate.workspace.remove(id); UserDefaults(suiteName:delegate.workspace.prefix+id)?.removePersistentDomain(forName:delegate.workspace.prefix+id) }
        precondition(delegate.workspace.docks.isEmpty)
        print("PASS: four simultaneous dock models, independent themes/content, bounded positioning, session/sleep suppression and removal")
        // Capture the real card components with clearly synthetic display data for visual QA.
        model.accent = "White"; model.toolkit.note = "Ideas for a quieter workspace"; model.toolkit.tasks = [TaskItem(title: "Review the new design"), TaskItem(title: "Take a short break")]
        model.toolkit.monitor.cpu = 34; model.toolkit.monitor.available = true; model.toolkit.monitor.history = [5, 12, 9, 22, 18, 34, 26, 19, 28, 14, 20, 34]
        model.toolkit.weatherText = "26°"; model.toolkit.weatherCity = "Sample forecast"
        model.toolkit.spotify.track = TrackSnapshot(title: "A little room to breathe", artist: "Sample music", playing: false)
        model.toolkit.spotify.connected = true
        let gallery = NSHostingView(rootView: VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) { BrandIcon().frame(width: 48, height: 48); VStack(alignment: .leading) { Text("WaveDock").font(.system(size: 25, weight: .semibold)); Text("Thoughtfully at hand.").foregroundStyle(.secondary) }; Spacer(); Text("DESIGN PREVIEW · SAMPLE DATA").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
            ForEach([[ToolKind.focus, .weather, .spotify], [.system, .tasks, .notes], [.water, .pet, .appGroups]], id: \.self) { row in
                HStack(spacing: 12) { ForEach(row) { kind in RichWidgetCard(kind: kind, model: model, kit: model.toolkit, open: {}).frame(width: 236, height: 80) } }
            }
        }.padding(26).background(Color(white: 0.075)).foregroundStyle(.white).preferredColorScheme(.dark))
        let galleryWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 784, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        galleryWindow.isReleasedWhenClosed = false; galleryWindow.contentView = gallery; galleryWindow.orderFront(nil)
        gallery.setFrameSize(gallery.fittingSize); gallery.layoutSubtreeIfNeeded()
        if let bitmap = gallery.bitmapImageRepForCachingDisplay(in: gallery.bounds) { gallery.cacheDisplay(in: gallery.bounds, to: bitmap); if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output.appendingPathComponent("design-preview.png")) } }
        galleryWindow.orderOut(nil); model.toolkit.monitor.stop(); model.toolkit.spotify.disconnect()
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
