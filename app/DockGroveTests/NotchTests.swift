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
    var airDropCalls: [[URL]] = []
    let controller = NotchController(model: model, airDropAction: { airDropCalls.append($0); return true })
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
    print("PASS: notch compatibility, invalid/missing geometry, negative display origins, camera-safe frames, preference persistence, disabled/suppressed cleanup, hover dwell/leave/click behavior, complete access-gated widget catalog, fixed-height horizontal layout, saved width and automatic Files tab selection, distinct tray/AirDrop native drop routing, custom review queue/dedup/removal/explicit handoff, file intake/deduplication/persistence/original preservation and workspace renders")
}
