import AppKit
import SwiftUI
@testable import DockGrove

@MainActor func runNotchTests(output: URL?) throws {
    let base = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
    let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    precondition(NotchGeometry(screen: base, topInset: 0, left: nil, right: nil) == nil)
    precondition(NotchGeometry(screen: base, topInset: 32, left: nil, right: right) == nil)
    precondition(NotchGeometry(screen: base, topInset: .nan, left: left, right: right) == nil)
    precondition(NotchGeometry(screen: base, topInset: 32, left: right, right: left) == nil)
    for offset in [CGPoint.zero, CGPoint(x: -1512, y: 120), CGPoint(x: 300, y: -982)] {
        let screen = base.offsetBy(dx: offset.x, dy: offset.y)
        let geometry = NotchGeometry(screen: screen, topInset: 32, left: left.offsetBy(dx: offset.x, dy: offset.y), right: right.offsetBy(dx: offset.x, dy: offset.y))!
        precondition(geometry.housing.width == 185)
        for expanded in [false, true] {
            let frame = geometry.panelFrame(expanded: expanded)
            precondition(screen.contains(frame))
            precondition(abs(frame.midX - geometry.housing.midX) < 0.01)
            precondition(frame.maxY == screen.maxY, "The shelf must anchor in the notch row")
            if expanded {
                precondition(frame.width > geometry.housing.width + 90)
                precondition(frame.height == geometry.housing.height + 112, "The strip must stay short regardless of content")
            }
            else { precondition(frame == geometry.housing, "Resting notch must exactly match the system camera housing") }
            if !expanded { precondition(frame.minY == geometry.housing.minY, "Collapsed mode must stay entirely in the notch row") }
        }
    }
    let sizing = NotchGeometry(screen: base, topInset: 32, left: left, right: right)!
    for width in [Double.nan, -Double.infinity, 0, 600, 980, 1600, 10000] {
        let expanded = sizing.panelFrame(expanded: true, preferredWidth: width)
        precondition(expanded.width >= 600 && expanded.width <= base.width - 32)
        precondition(expanded.height == 144)
        precondition(abs(NotchFileLayout.halfWidth(expanded.width) * 2 + 42 - expanded.width) < 0.01)
        precondition(sizing.panelFrame(expanded: false, preferredWidth: width) == sizing.housing)
    }
    let suite = "DockGroveNotchTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set([], forKey: "apps"); defaults.set(false, forKey: "showRunning")
    defaults.set(["search", "focus", "tasks"], forKey: "widgets")
    let model = DockModel(defaults: defaults)
    precondition(model.notchWidth == 760)
    model.notchWidth = 980
    precondition(DockModel(defaults: defaults).notchWidth == 980)
    model.notchWidth = .nan
    precondition(model.notchWidth == 760)
    precondition(!model.notchEnabled)
    model.notchEnabled = true
    precondition(DockModel(defaults: defaults).notchEnabled)
    precondition(model.notchOpensOnHover && model.notchClosesOnExit)
    model.notchOpensOnHover = false; model.notchClosesOnExit = false
    let reloaded = DockModel(defaults: defaults)
    precondition(!reloaded.notchOpensOnHover && !reloaded.notchClosesOnExit)
    model.notchOpensOnHover = true; model.notchClosesOnExit = true
    precondition(model.notchWidgets.contains(.search) && model.notchWidgets.contains(.focus))
    precondition(!model.notchWidgets.contains(.spacer) && !model.notchWidgets.contains(.separator))
    precondition(model.notchWidgets.allSatisfy { model.canAccess($0) })
    precondition(model.notchWidgets.count == ToolKind.allCases.filter { $0 != .spacer && $0 != .separator && model.canAccess($0) }.count)
    var hover = NotchHoverState()
    precondition(hover.update(now: 0, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    precondition(hover.update(now: 0.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    precondition(hover.update(now: 0.5, trigger: false, inside: false, expanded: true, interacting: false) == nil)
    precondition(hover.update(now: 0.7, trigger: false, inside: false, expanded: true, interacting: true) == nil)
    precondition(hover.update(now: 1.5, trigger: false, inside: false, expanded: true, interacting: false) == false)
    hover.manualChange(expanded: true)
    precondition(hover.update(now: 10, trigger: false, inside: false, expanded: true, interacting: false) == nil)
    hover.manualChange(expanded: false)
    precondition(hover.update(now: 11, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    precondition(hover.update(now: 12, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    _ = hover.update(now: 13, trigger: false, inside: false, expanded: false, interacting: false)
    _ = hover.update(now: 14, trigger: true, inside: true, expanded: false, interacting: false)
    precondition(hover.update(now: 14.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    var clickOnly = NotchHoverState()
    precondition(clickOnly.update(now: 0, trigger: true, inside: true, expanded: false, interacting: false, opensOnEnter: false) == nil)
    precondition(clickOnly.update(now: 1, trigger: true, inside: true, expanded: false, interacting: false, opensOnEnter: false) == nil, "Hover must not open the notch when opening on hover is off")
    precondition(clickOnly.update(now: 1.1, trigger: true, inside: true, expanded: false, interacting: false) == nil, "Turning hover back on restarts the dwell")
    precondition(clickOnly.update(now: 1.3, trigger: true, inside: true, expanded: false, interacting: false) == true)
    var staysOpen = NotchHoverState()
    _ = staysOpen.update(now: 0, trigger: true, inside: true, expanded: false, interacting: false)
    precondition(staysOpen.update(now: 0.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    precondition(staysOpen.update(now: 5, trigger: false, inside: false, expanded: true, interacting: false, closesOnExit: false) == nil, "Leaving must not close the notch when closing on exit is off")
    precondition(staysOpen.hoverOwned, "A hover-opened notch stays owned by the pointer while close-on-exit is off")
    precondition(staysOpen.update(now: 5.1, trigger: false, inside: false, expanded: true, interacting: false) == nil, "Turning close-on-exit back on starts a fresh grace period")
    precondition(staysOpen.update(now: 5.9, trigger: false, inside: false, expanded: true, interacting: false) == false, "…then closes the hover-opened notch")
    precondition(!staysOpen.hoverOwned)
    var midDwell = NotchHoverState()
    precondition(midDwell.update(now: 0, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    precondition(midDwell.update(now: 0.1, trigger: true, inside: true, expanded: false, interacting: false, opensOnEnter: false) == nil)
    precondition(midDwell.update(now: 5, trigger: true, inside: true, expanded: false, interacting: false) == nil, "Re-enabling hover mid-dwell must restart the dwell, not open at once")
    precondition(midDwell.update(now: 5.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    var hoverOffWhileOpen = NotchHoverState()
    _ = hoverOffWhileOpen.update(now: 0, trigger: true, inside: true, expanded: false, interacting: false)
    precondition(hoverOffWhileOpen.update(now: 0.2, trigger: true, inside: true, expanded: false, interacting: false) == true)
    precondition(hoverOffWhileOpen.update(now: 2, trigger: false, inside: false, expanded: true, interacting: false, opensOnEnter: false) == false, "Turning hover off does not pin an already hover-opened notch")
    var clickedOpen = NotchHoverState()
    clickedOpen.manualChange(expanded: true)
    precondition(!clickedOpen.hoverOwned)
    precondition(clickedOpen.update(now: 100, trigger: false, inside: false, expanded: true, interacting: false) == nil, "A clicked-open notch never closes by leaving")
    clickedOpen.manualChange(expanded: false)
    precondition(clickedOpen.update(now: 101, trigger: true, inside: true, expanded: false, interacting: false) == nil)
    precondition(clickedOpen.update(now: 103, trigger: true, inside: true, expanded: false, interacting: false) == nil, "Closing with the pointer on the notch disarms hover until it leaves")
    var dragStays = NotchHoverState()
    dragStays.beginDrag(now: 0, alreadyExpanded: false)
    precondition(dragStays.update(now: 0.5, trigger: false, inside: true, expanded: true, interacting: false, closesOnExit: false) == nil)
    precondition(dragStays.update(now: 1, trigger: false, inside: false, expanded: true, interacting: false, closesOnExit: false) == nil)
    precondition(dragStays.update(now: 1.3, trigger: false, inside: false, expanded: true, interacting: false, closesOnExit: false) == false, "A drag-opened tray closes after the pointer leaves even with close-on-exit off")
    var dragHover = NotchHoverState()
    dragHover.beginDrag(now: 0, alreadyExpanded: false)
    precondition(dragHover.update(now: 1, trigger: false, inside: false, expanded: true, interacting: false) == false)
    dragHover.manualChange(expanded: true)
    dragHover.beginDrag(now: 2, alreadyExpanded: true)
    precondition(dragHover.update(now: 4, trigger: false, inside: false, expanded: true, interacting: false) == nil)
    var airDropCalls: [[URL]] = []
    let controller = NotchController(model: model, airDropAction: { airDropCalls.append($0); return true })
    controller.installDismissMonitors = { _, _ in [] }
    precondition(!controller.showingFiles)
    controller.beginFileDrag()
    precondition(controller.showingFiles == model.canAccess(.files))
    controller.showingFiles = false
    controller.fileDragActive = false
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let fixture = temporary.appendingPathComponent("Example.txt")
    try Data("Notch tray test".utf8).write(to: fixture)
    let missing = temporary.appendingPathComponent("missing.txt")
    let remote = URL(string: "https://example.com/file.txt")!
    precondition(NotchFileIntake.existingURLs([fixture, fixture, missing, remote, temporary]).count == 2)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([fixture as NSURL, temporary as NSURL])
    precondition(NotchFileIntake.urls(from: pasteboard).map(\.standardizedFileURL) == [fixture.standardizedFileURL, temporary.standardizedFileURL])
    precondition(!controller.acceptFiles([missing, remote]))
    precondition(!controller.acceptDrop([missing, remote], to: .airDrop))
    precondition(airDropCalls.isEmpty)
    let dropTarget = NotchDropTargetView()
    dropTarget.controller = controller; dropTarget.destination = .airDrop
    let sent = dropTarget.accept(pasteboard)
    precondition(sent == model.canAccess(.files))
    precondition(model.toolkit.files.isEmpty, "AirDrop must never add files to the tray")
    precondition(airDropCalls.isEmpty, "Dropping files must wait for review before invoking AirDrop")
    if sent {
        controller.setExpanded(false)
        controller.beginFileDrag()
        precondition(!controller.airDropReview, "Dragging onto a resting notch should reveal both drop zones")
        controller.acceptDrop([fixture], to: .airDrop)
        precondition(controller.airDropReview && controller.airDropFiles.count == 2)
        precondition(controller.acceptDrop([fixture], to: .airDrop) && controller.airDropFiles.count == 2)
        controller.removeAirDropFile(temporary.standardizedFileURL)
        precondition(controller.airDropFiles.count == 1)
        precondition(controller.startAirDrop())
        precondition(airDropCalls.count == 1 && airDropCalls[0] == [fixture.standardizedFileURL])
        let completionService = NSSharingService(title: "Test", image: NSImage(), alternateImage: nil, handler: {})
        controller.sharingService(completionService, didShareItems: [fixture])
        precondition(controller.airDropFiles == [fixture.standardizedFileURL], "Returning from AirDrop must preserve the review selection even when macOS reports success after cancellation")
        controller.clearAirDropFiles()
        precondition(controller.airDropFiles.isEmpty && !controller.startAirDrop())
    }
    dropTarget.destination = .tray
    let kept = dropTarget.accept(pasteboard)
    precondition(kept == model.canAccess(.files))
    precondition(airDropCalls.count == (sent ? 1 : 0), "Tray drops must not launch AirDrop")
    model.toolkit.files.removeAll()
    if model.canAccess(.files) {
        precondition(controller.acceptFiles([fixture, fixture, temporary]))
        precondition(model.toolkit.files.count == 2 && controller.showingFiles)
        precondition(controller.acceptFiles([fixture]) && model.toolkit.files.count == 2)
        precondition(DockModel(defaults: defaults).toolkit.files == model.toolkit.files)
        model.toolkit.files.removeAll()
        precondition(FileManager.default.fileExists(atPath: fixture.path), "Removing a tray shortcut must leave the original untouched")
    } else { precondition(!controller.acceptFiles([fixture]) && model.toolkit.files.isEmpty) }
    runNotchOpenCloseTests(model: model, fixture: fixture)

    controller.setExpanded(true); controller.selectedWidget = .focus
    controller.update(suppressed: true)
    precondition(!controller.panel.isVisible && !controller.expanded && controller.selectedWidget == nil)
    model.notchEnabled = false; controller.setExpanded(true)
    controller.update(suppressed: false)
    precondition(!controller.panel.isVisible && !controller.expanded)
    if let output {
        controller.trayMessage = nil
        controller.airDropMessage = "Drop files to share nearby"
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let geometry = NotchGeometry(screen: base, topInset: 32, left: left, right: right)!
        for (name, expanded, detail) in [("collapsed", false, false), ("strip", true, false), ("files", true, false), ("airdrop-review", true, false), ("focus", true, true)] {
            controller.setExpanded(expanded)
            controller.showingFiles = name == "files" || name == "airdrop-review"
            controller.airDropReview = name == "airdrop-review"
            if controller.airDropReview { controller.airDropFiles = [fixture] }
            if detail { controller.selectedWidget = .focus }
            let view = controller.panel.contentView!
            controller.panel.setFrame(geometry.panelFrame(expanded: expanded, preferredWidth: model.notchWidth), display: true)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if name == "airdrop-review" && model.canAccess(.files) {
                func hasTrayTarget(_ node: NSView) -> Bool {
                    if let target = node as? NotchDropTargetView, target.destination == .tray { return true }
                    return node.subviews.contains(where: hasTrayTarget)
                }
                precondition(hasTrayTarget(view), "The File Tray drop target must remain present during AirDrop review")
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("notch-" + name + ".png"))
        }
    }
    controller.hide()
    print("PASS: notch compatibility, invalid/missing geometry, negative display origins, camera-safe frames, preference persistence, disabled/suppressed cleanup, hover dwell/leave/click behavior, hover-open and close-on-exit options, click-to-open/close, Esc and click-outside dismissal, drag-opened tray closing, option changes while open, complete access-gated widget catalog, fixed-height horizontal layout, saved width and automatic Files tab selection, distinct tray/AirDrop native drop routing, custom review queue/dedup/removal/explicit handoff, file intake/deduplication/persistence/original preservation and workspace renders")
}

/// Drives a controller through every way the notch opens and closes, with the pointer, clock,
/// display and Esc/click-outside monitors injected so no real event monitor or screen is touched.
@MainActor private func runNotchOpenCloseTests(model: DockModel, fixture: URL) {
    model.notchEnabled = true
    let controller = NotchController(model: model)
    var installs = 0, removals = 0
    var monitor: ((NotchDismissEvent) -> Bool)?
    controller.installDismissMonitors = { window, handler in
        precondition(window === controller.panel)
        installs += 1; monitor = handler; return ["local", "global"]
    }
    controller.removeDismissMonitor = { _ in removals += 1 }
    controller.compatibleDisplay = { DockFakeNotchScreen() }
    controller.chooseFiles = { _ in nil }
    var now: TimeInterval = 1000
    controller.clock = { now }
    let away = CGPoint(x: -1, y: -1)
    var mouse = away
    controller.mouseLocation = { mouse }
    func tick(_ seconds: TimeInterval = 0) { now += seconds; controller.update(suppressed: false, windows: []) }
    func send(_ event: NotchDismissEvent) -> Bool { monitor?(event) ?? false }
    defer { controller.hide(); model.notchOpensOnHover = true; model.notchClosesOnExit = true; model.toolkit.files.removeAll() }

    tick()
    guard let geometry = controller.geometry else { preconditionFailure("The fake notch display must be compatible") }
    let onNotch = CGPoint(x: geometry.housing.midX, y: geometry.housing.midY)
    precondition(controller.panel.isVisible && !controller.expanded && installs == 0, "Monitors are installed only while the notch is open")
    precondition(!controller.panel.ignoresMouseEvents && controller.panel.styleMask.contains(.nonactivatingPanel), "The resting notch must take clicks without activating DockGrove")
    precondition((controller.panel.contentView as? NotchDropHostingView)?.acceptsFirstMouse(for: nil) == true, "The first click on the non-key notch panel must reach its button")

    // Opening on hover off: dwelling never opens; clicking the resting notch does.
    model.notchOpensOnHover = false
    mouse = onNotch; tick(); tick(1); tick(1)
    precondition(!controller.expanded, "Hover must not open the notch when opening on hover is off")
    controller.toggleFromClick()
    precondition(controller.expanded && installs == 1)
    tick(); mouse = away; tick(5); tick(5)
    precondition(controller.expanded, "A clicked-open notch stays open when the pointer leaves")
    precondition(!send(.pointerDown(insidePanel: true)) && controller.expanded, "Clicks on the notch's own controls never dismiss it")
    mouse = CGPoint(x: controller.panel.frame.midX, y: controller.panel.frame.midY)
    precondition(!send(.pointerDown(insidePanel: false)) && controller.expanded, "A click over the open panel is not outside it")
    mouse = away
    precondition(send(.pointerDown(insidePanel: false)) && !controller.expanded && removals == 2, "Clicking outside closes the notch and removes its monitors")
    precondition(!send(.escape) && !send(.pointerDown(insidePanel: false)), "A closed notch ignores dismiss events")
    controller.toggleFromClick(); controller.toggleFromClick()
    precondition(!controller.expanded && installs == 2 && removals == 4, "Clicking the notch again closes it")
    controller.toggleFromClick()
    precondition(send(.escape) && !controller.expanded, "Esc closes the notch")

    // Re-enabling hover: a close made with the pointer on the notch must not reopen it at once.
    model.notchOpensOnHover = true
    mouse = onNotch; controller.toggleFromClick(); tick(); controller.toggleFromClick(); tick(1); tick(1)
    precondition(!controller.expanded, "Closing by click with the pointer on the notch disarms hover until the pointer leaves")
    mouse = away; tick(); mouse = onNotch; tick()
    precondition(!controller.expanded, "Hover dwells before opening")
    tick(0.2)
    precondition(controller.expanded, "Leaving and returning re-arms hover")

    // Closing on exit off: a hover-opened notch stays until a click outside or Esc.
    model.notchClosesOnExit = false
    mouse = away; tick(5); tick(5)
    precondition(controller.expanded, "Leaving must not close the notch when closing on exit is off")
    precondition(send(.pointerDown(insidePanel: false)) && !controller.expanded, "Clicking outside closes a hover-opened notch")
    tick(); mouse = onNotch; tick(); tick(0.2)
    precondition(controller.expanded)
    precondition(send(.escape) && !controller.expanded, "Esc closes a hover-opened notch")
    tick(1); tick(1)
    precondition(!controller.expanded, "Esc with the pointer on the notch must not let hover reopen it")

    // Switching close-on-exit back on while open gives a fresh grace period, then closes.
    mouse = away; tick(); mouse = onNotch; tick(); tick(0.2)
    precondition(controller.expanded)
    mouse = away; tick(10)
    model.notchClosesOnExit = true; tick(0.1)
    precondition(controller.expanded, "Re-enabling close-on-exit must not snap the notch shut")
    tick(0.7)
    precondition(!controller.expanded)

    // Switching hover off while hover-opened: the notch still closes on exit and stays closed.
    mouse = onNotch; tick(); tick(0.2)
    precondition(controller.expanded)
    model.notchOpensOnHover = false
    mouse = away; tick(0.1); tick(0.8)
    precondition(!controller.expanded)
    mouse = onNotch; tick(); tick(1)
    precondition(!controller.expanded)

    // Re-enabling hover mid-dwell restarts the dwell.
    model.notchOpensOnHover = true
    mouse = away; tick(); mouse = onNotch; tick(); tick(0.1)
    model.notchOpensOnHover = false; tick(1)
    model.notchOpensOnHover = true; tick(0.01)
    precondition(!controller.expanded, "Re-enabling hover must restart the dwell")
    tick(0.2)
    precondition(controller.expanded)
    controller.setExpanded(false); mouse = away; tick()

    // A drag-opened tray closes after a drop once the pointer leaves, even with close-on-exit off.
    model.notchClosesOnExit = false
    if model.canAccess(.files) {
        mouse = onNotch; controller.beginFileDrag()
        precondition(controller.expanded && controller.showingFiles && controller.fileDragActive)
        mouse = away
        precondition(!send(.pointerDown(insidePanel: false)) && !send(.escape) && controller.expanded, "Nothing dismisses the notch mid-drag")
        mouse = onNotch
        precondition(controller.acceptFiles([fixture]) && controller.expanded && !controller.fileDragActive)
        tick(); mouse = away; tick(0.1)
        precondition(controller.expanded, "The tray stays briefly so the drop result is visible")
        tick(0.8)
        precondition(!controller.expanded, "A drag-opened tray must not stay stuck open after a drop")
        mouse = onNotch; controller.beginFileDrag(); controller.fileDragActive = false
        mouse = away; tick(); tick(0.8)
        precondition(!controller.expanded, "A drag that leaves without dropping closes the tray")
        controller.toggleFromClick(); controller.beginFileDrag()
        precondition(controller.acceptFiles([fixture]))
        tick(); tick(5)
        precondition(controller.expanded, "Dropping onto a clicked-open notch keeps it open")
        precondition(send(.escape) && !controller.expanded)
    }

    // A file picker sits outside the notch, so its clicks and Esc must not close it.
    controller.toggleFromClick()
    var pickerSawClose = false
    controller.chooseFiles = { _ in pickerSawClose = send(.pointerDown(insidePanel: false)) || send(.escape); return nil }
    controller.addFiles()
    precondition(!pickerSawClose && controller.expanded, "Clicks in the file picker must not dismiss the notch")

    // The display going away (screen change, full screen, lock) closes the notch and removes the monitors.
    controller.compatibleDisplay = { nil }
    tick()
    precondition(!controller.expanded && !controller.panel.isVisible && removals == installs * 2, "Hiding must remove every monitor it installed")
}
