import AppKit
import SwiftUI
@testable import DockGrove

@MainActor func runDockStudioTests() throws {
    let name = "DockGroveStudioTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
    defaults.set([], forKey: "apps"); defaults.set([], forKey: "widgets")
    defaults.set(false, forKey: "showRunning"); defaults.set(false, forKey: "showClock")
    defaults.set(false, forKey: "showUsageCard")
    let model = DockModel(defaults: defaults)
    let focus = DockStudioItem(kind: .widget, value: "focus")
    let tasks = DockStudioItem(kind: .widget, value: "tasks")
    precondition(model.placeStudioItem(focus))
    precondition(model.placeStudioItem(tasks, before: focus.id))
    precondition(model.studioEntries.map(\.id) == ["tasks", "focus"])
    precondition(model.placeStudioItem(tasks))
    precondition(model.studioEntries.map(\.id) == ["focus", "tasks"])
    precondition(model.toolkit.enabled.count == 2, "Dragging an existing tile must not duplicate it")
    model.undoStudioLayout()
    precondition(model.studioEntries.map(\.id) == ["tasks", "focus"])
    let appURL = folder.appendingPathComponent("Example.app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    let app = DockStudioItem(kind: .app, value: appURL.path)
    precondition(model.placeStudioItem(app, before: "focus"))
    precondition(model.studioEntries.map(\.id) == ["tasks", app.id, "focus"])
    let restored = DockModel(defaults: defaults)
    precondition(restored.studioEntries.map(\.id) == model.studioEntries.map(\.id))
    precondition(model.removeStudioItem(tasks))
    precondition(model.studioEntries.map(\.id) == [app.id, "focus"])
    model.undoStudioLayout()
    precondition(model.studioEntries.map(\.id) == ["tasks", app.id, "focus"])
    let original = model.studioEntries.map(\.id), history = model.studioHistory.count
    for invalid in [DockStudioItem(kind: .widget, value: "unknown"), DockStudioItem(kind: .app, value: "/no/such/app.app"), DockStudioItem(kind: .app, value: "relative.app"), DockStudioItem(kind: .app, value: folder.path)] {
        precondition(!model.placeStudioItem(invalid))
        precondition(model.studioEntries.map(\.id) == original && model.studioHistory.count == history)
    }
    precondition(!model.placeStudioItem(focus, before: "missing-target"))
    precondition(!model.placeStudioItem(focus, before: focus.id))
    if !model.canAccess(.weather) {
        precondition(!model.placeStudioItem(DockStudioItem(kind: .widget, value: "weather")), "A forged drag must not unlock a paid widget")
        precondition(!model.placeStudioItem(DockStudioItem(kind: .usage)))
    }
    let encoded = try JSONEncoder().encode(app)
    let decoded = try JSONDecoder().decode(DockStudioItem.self, from: encoded)
    precondition(decoded == app)
    precondition(model.removeStudioItem(app))
    precondition(model.apps.isEmpty)
    model.undoStudioLayout()
    precondition(model.apps.count == 1)
    try runWidgetShapeTests()
    try runToolbarSizeTests()
    try runNotchTests(output: nil)
    print("PASS: studio insertion/reordering, duplicate prevention, remove/undo, persistence, invalid targets/paths, purchase enforcement and drag payload round-trip")
}

@MainActor func renderDockStudio(to output: URL) throws {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let name = "DockGroveStudioRender." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app"], forKey: "apps")
    defaults.set(["focus", "tasks", "search"], forKey: "widgets")
    defaults.set(["focus": "circle", "tasks": "square", "search": "pill"], forKey: "widgetShapes")
    defaults.set(false, forKey: "showRunning"); defaults.set(false, forKey: "showUsageCard")
    let model = DockModel(defaults: defaults)
    let store = SettingsFakePurchaseStore() // never loads from StoreKit
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        for section in [StudioSection.library, .appearance, .purchases] {
            let host = NSHostingView(rootView: SettingsView(model: model, section: section, purchases: store, terminate: { _ in }).environment(\.colorScheme, scheme))
            let size = NSSize(width: 1080, height: 780)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            window.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
            host.setFrameSize(size); window.orderFront(nil); host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: output.appendingPathComponent("studio-\(section.rawValue.lowercased())-\(name).png"))
            window.orderOut(nil)
        }
    }
    for (name, height, fraction) in [("compact", 88.0, 0.4), ("balanced", 104.0, 0.7), ("spacious", 180.0, 1.0)] {
        model.toolbarHeight = height; model.widthFraction = fraction; model.fitToolbarToContent = false
        let host = NSHostingView(rootView: DockView(model: model))
        let size = host.fittingSize
        precondition(abs(size.height - model.dockHeight) < 1, "Toolbar panel height must match reserved height")
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.setFrameSize(size); window.orderFront(nil); host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("toolbar-" + name + ".png"))
        window.orderOut(nil)
    }
    print("PASS: studio light/dark and three toolbar sizes rendered; native panel and reserved heights match")
}

@MainActor private func runWidgetShapeTests() throws {
    let suite = "DockGroveShapeTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set([], forKey: "apps")
    defaults.set(false, forKey: "showRunning")
    defaults.set(false, forKey: "showClock")
    defaults.set(false, forKey: "showUsageCard")
    let model = DockModel(defaults: defaults)
    precondition(model.toolkit.shape(for: .focus) == .rounded)
    model.setWidgetShape(.circle, for: .focus)
    precondition(DockModel(defaults: defaults).toolkit.shape(for: .focus) == .circle)
    model.undoStudioLayout()
    precondition(model.toolkit.shape(for: .focus) == .rounded)
    model.setWidgetShape(.circle, for: .focus)
    model.setWidgetShape(.square, for: .tasks)
    model.setWidgetShape(.pill, for: .search)
    let shapes = model.toolkit.widgetShapes
    for size in [32.0, 48, 64] {
        let height = max(64, size + 20)
        precondition(DockEntry.tool(.focus).width(iconSize: size, shapes: shapes) == height)
        precondition(DockEntry.tool(.tasks).width(iconSize: size, shapes: shapes) == height)
        precondition(DockEntry.tool(.search).width(iconSize: size, shapes: shapes) > height)
        let widths = model.studioEntries.map { $0.width(iconSize: size, shapes: shapes) }
        let pages = DockPageLayout.pages(widths: widths, available: 260)
        precondition(pages.flatMap { $0 } == Array(widths.indices))
        for page in pages { precondition(page.reduce(0) { $0 + widths[$1] } + Double(max(0, page.count - 1)) * 10 <= 260) }
    }
    model.toolkit.profileName = "Mixed shapes"
    model.saveProfile()
    let data = try JSONEncoder().encode(model.toolkit.profiles[0])
    let profile = try JSONDecoder().decode(DockProfile.self, from: data)
    model.toolkit.widgetShapes = [:]
    model.applyProfile(profile)
    precondition(model.toolkit.widgetShapes == shapes)
    let item = model.studioItem(.tool(.focus))!
    let decoded = try JSONDecoder().decode(DockStudioItem.self, from: JSONEncoder().encode(item))
    precondition(decoded.shape == "circle")
    model.toolkit.widgetShapes = [:]
    precondition(model.placeStudioItem(decoded))
    precondition(model.toolkit.shape(for: .focus) == .circle)
    model.undoStudioLayout()
    precondition(model.toolkit.widgetShapes.isEmpty)
    var invalid = decoded; invalid.shape = "triangle-from-unknown-version"
    let history = model.studioHistory.count
    precondition(!model.placeStudioItem(invalid) && model.studioHistory.count == history)
    var oldProfile = profile; oldProfile.widgetShapes = nil
    model.applyProfile(oldProfile)
    precondition(model.toolkit.widgetShapes.isEmpty)
    var imported = profile; imported.widgetShapes = ["focus": "circle", "tasks": "unknown", "unknown": "pill"]
    model.applyProfile(imported)
    precondition(model.toolkit.widgetShapes == ["focus": "circle"])
    print("PASS: mixed widget shapes, sizing/paging, saved preferences, profile round-trip, legacy profiles, drag styling, undo and invalid-style rejection")
}


@MainActor private func runToolbarSizeTests() throws {
    let suite = "DockGroveSizeTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set([], forKey: "apps"); defaults.set(false, forKey: "showRunning")
    let model = DockModel(defaults: defaults)
    precondition(model.barHeight == 92 && model.fitToolbarToContent)
    model.rememberStudioLayout()
    model.toolbarHeight = 160; model.widthFraction = 0.6; model.fitToolbarToContent = false
    let restored = DockModel(defaults: defaults)
    precondition(restored.barHeight == 160 && restored.widthFraction == 0.6 && !restored.fitToolbarToContent)
    model.toolkit.profileName = "Tall toolbar"; model.saveProfile()
    let profile = try JSONDecoder().decode(DockProfile.self, from: JSONEncoder().encode(model.toolkit.profiles.last!))
    model.undoStudioLayout()
    precondition(model.barHeight == 92 && model.widthFraction == 1 && model.fitToolbarToContent)
    model.applyProfile(profile)
    precondition(model.barHeight == 160 && !model.fitToolbarToContent)
    for height in [88.0, 104, 140, 180] {
        for icon in [32.0, 48, 64] {
            model.toolbarHeight = height; model.iconSize = icon
            precondition(model.tileHeight >= icon + 20 && model.dockHeight == model.barHeight + 20)
            let shapes = ["focus": "circle", "tasks": "square", "search": "pill"]
            let entries: [DockEntry] = [.tool(.focus), .tool(.tasks), .tool(.search), .clock]
            let widths = entries.map { $0.width(iconSize: icon, shapes: shapes, tileHeight: model.tileHeight) }
            precondition(widths[0] == model.tileHeight && widths[1] == model.tileHeight)
            for screen in [640.0, 1024, 1440, 2560] {
                for fraction in [0.35, 0.65, 1] {
                    model.widthFraction = fraction
                    for fit in [true, false] {
                        model.fitToolbarToContent = fit
                        let width = model.toolbarWidth(screenWidth: screen, widths: widths)
                        precondition(width <= screen - 44 && width >= widths.max()! + DockPageLayout.chrome)
                        let pages = DockPageLayout.pages(widths: widths, available: width - DockPageLayout.chrome)
                        precondition(pages.flatMap { $0 } == Array(widths.indices))
                        for page in pages { precondition(page.reduce(0) { $0 + widths[$1] } + Double(max(0, page.count - 1)) * DockPageLayout.gap <= width - DockPageLayout.chrome + 0.001) }
                    }
                }
            }
        }
    }
    model.iconSize = 48; model.widthFraction = 1
    model.fitToolbarToContent = true
    let fitted = model.toolbarWidth(screenWidth: 1440, widths: [68])
    model.fitToolbarToContent = false
    precondition(model.toolbarWidth(screenWidth: 1440, widths: [68]) > fitted)
    var legacy = profile; legacy.toolbarHeight = nil; legacy.fitToolbarToContent = nil
    model.applyProfile(legacy)
    precondition(model.barHeight == 92 && model.fitToolbarToContent)
    var invalid = profile; invalid.toolbarHeight = 500
    model.applyProfile(invalid); precondition(model.barHeight == 180)
    defaults.set(-40, forKey: "toolbarHeight")
    precondition(DockModel(defaults: defaults).toolbarHeight == 88)
    print("PASS: toolbar dimensions, 288 mixed-shape paging configurations, fit/fixed width, persistence, profile migration, bounds and undo")
}
