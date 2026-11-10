import XCTest
import SwiftUI
@testable import DockGrove

/// Covers the Applications stack tile, its Dock-anchored stack popover and the floating app chooser
/// (used by + and Replace app…) without touching the real desktop: apps come from a temporary
/// folder, launching and Finder effects are recorded, and no panel is ever brought on screen.
@MainActor final class ApplicationsStackTests: XCTestCase {
    private var suites: [String] = []
    private var folders: [URL] = []
    private var effects: [DockSystemEffect] = []
    private var launched: [URL] = []
    private let originalHandler = DockSystemEffect.handler
    private let originalPresent = AppsLauncher.shared.present
    private let originalStackPresent = AppsStackPopover.shared.present
    private let originalPresentOptions = AppsLauncher.shared.presentOptions

    override func setUp() {
        super.setUp()
        DockSystemEffect.handler = { [unowned self] in self.effects.append($0) }
        AppsLauncher.shared.present = { _ in }
        AppsStackPopover.shared.present = { _ in }
    }

    override func tearDown() {
        AppsLauncher.shared.close()
        AppsStackPopover.shared.close()
        AppsStackPopover.shared.dismissalGrace = 0.35
        DockSystemEffect.handler = originalHandler
        AppsLauncher.shared.present = originalPresent
        AppsLauncher.shared.presentOptions = originalPresentOptions
        AppsStackPopover.shared.present = originalStackPresent
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        folders.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    /// A model whose catalog is `count` fake bundles plus Finder, scanned and ready.
    /// Sample 00-09 declare the Utilities category and 10-19 Games; the rest declare none.
    private func model(apps count: Int) -> DockModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppsStack-" + UUID().uuidString)
        folders.append(folder)
        for index in 0..<count {
            let contents = folder.appendingPathComponent(String(format: "Sample %02d.app/Contents", index))
            try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var plist: [String: Any] = ["CFBundleIdentifier": "test.sample.\(index)", "CFBundleName": String(format: "Sample %02d", index)]
            if index < 10 { plist["LSApplicationCategoryType"] = "public.app-category.utilities" }
            else if index < 20 { plist["LSApplicationCategoryType"] = "public.app-category.games" }
            try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        let suite = "ApplicationsStackTests." + UUID().uuidString
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set([], forKey: "apps"); defaults.set(false, forKey: "showRunning")
        let model = DockModel(defaults: defaults)
        model.openApplication = { [unowned self] url, completion in self.launched.append(url); completion(nil) }
        model.fetchUsage = { _ in throw UsageError.service }
        model.toolkit.applicationRoots = [folder.path]
        model.toolkit.scanApplications(force: true)
        let deadline = Date().addingTimeInterval(10)
        while model.toolkit.appIndex.records.filter({ $0.path.hasPrefix(folder.path) }).count < count || model.toolkit.scanningApps, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(model.toolkit.scanningApps, "scan should finish")
        return model
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: code)!
    }

    func testTileTogglesStackPopoverAndOffersFolderActions() {
        let model = model(apps: 3)
        let harness = DockHarness(ApplicationsStackTile(model: model), size: CGSize(width: 90, height: 90))
        defer { harness.close() }
        let point = CGPoint(x: 45, y: 50)
        harness.hover(point, entering: true)
        harness.hover(CGPoint(x: 300, y: 300), entering: false)
        harness.press("Applications")
        XCTAssertNotNil(AppsStackPopover.shared.panel, "pressing the tile opens the stack popover")
        XCTAssertNil(AppsLauncher.shared.panel, "the stack never takes over the screen")
        XCTAssertLessThan(AppsStackPopover.shared.panel?.frame.width ?? .infinity, 900, "the stack is a popover, not a full-screen panel")
        harness.press("Applications")
        XCTAssertNil(AppsStackPopover.shared.panel, "pressing it again closes the stack")
        let open = "Open \u{201C}Applications\u{201D}"
        XCTAssertEqual(harness.menuTitles(at: point), ["Sort by", "Display as", "View content as", "", "Options", "", open, "", "Refresh Applications"])
        func submenu(_ title: String) -> [String] {
            let menu = harness.menuItem([title], at: point)?.submenu
            menu?.update()
            return menu?.items.map(\.title) ?? []
        }
        XCTAssertEqual(submenu("Sort by"), ["Name", "Date Added", "Date Modified", "Date Created", "Kind"])
        XCTAssertEqual(submenu("Display as"), ["Folder", "Stack"])
        XCTAssertEqual(submenu("View content as"), ["Fan", "Grid", "List", "Automatic"])
        XCTAssertEqual(submenu("Options"), ["Remove from Dock", "Show in Finder"])

        // Each choice is a checkmark, persisted as stackSort / stackDisplay / applicationsStackStyle.
        XCTAssertEqual(harness.menuItem(["Sort by", "Name"], at: point)?.state, .on)
        harness.choose(["Sort by", "Date Modified"], inMenuAt: point)
        XCTAssertEqual(model.stackSort, .dateModified)
        XCTAssertEqual(model.defaults.string(forKey: "stackSort"), "Date Modified")
        XCTAssertEqual(harness.menuItem(["Sort by", "Date Modified"], at: point)?.state, .on)
        XCTAssertEqual(harness.menuItem(["Sort by", "Name"], at: point)?.state, .off)
        harness.choose(["View content as", "Grid"], inMenuAt: point)
        XCTAssertEqual(model.applicationsStackStyle, .grid)
        XCTAssertEqual(model.defaults.string(forKey: DockModel.applicationsStackStyleKey), "grid")
        XCTAssertEqual(harness.menuItem(["View content as", "Grid"], at: point)?.state, .on)
        XCTAssertEqual(harness.menuItem(["Display as", "Folder"], at: point)?.state, .on)
        harness.choose(["Display as", "Stack"], inMenuAt: point)
        XCTAssertEqual(model.stackDisplay, .stack)
        XCTAssertEqual(model.defaults.string(forKey: "stackDisplay"), "Stack")
        harness.spin(0.1)
        XCTAssertEqual(model.stackPreview(count: 3).count, 3, "Stack piles up the first apps")
        XCTAssertEqual(model.stackPreview(count: 3), model.stackPreview(count: 3), "cached")
        let reloaded = DockModel(defaults: model.defaults)
        XCTAssertEqual(reloaded.stackSort, .dateModified); XCTAssertEqual(reloaded.applicationsStackStyle, .grid); XCTAssertEqual(reloaded.stackDisplay, .stack)
        harness.choose(["Display as", "Folder"], inMenuAt: point)
        harness.choose(["Sort by", "Name"], inMenuAt: point)
        harness.choose(["View content as", "Automatic"], inMenuAt: point)

        harness.choose(["Options", "Show in Finder"], inMenuAt: point)
        if case .reveal(let urls)? = effects.last { XCTAssertEqual(urls.map(\.path), ["/Applications"]) } else { XCTFail("Finder reveal should go through effects") }
        harness.choose(open, inMenuAt: point)
        if case .open(let url)? = effects.last { XCTAssertEqual(url.path, "/Applications") } else { XCTFail("folder should open through effects") }
        let before = model.toolkit.appIndex.count
        let extra = URL(fileURLWithPath: model.toolkit.applicationRoots[0]).appendingPathComponent("Added Later.app/Contents")
        try? FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        harness.choose("Refresh Applications", inMenuAt: point)
        let deadline = Date().addingTimeInterval(10)
        while model.toolkit.appIndex.count == before, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(model.toolkit.appIndex.count, before + 1, "refresh rescans and finds the new app")
        harness.choose(["Options", "Remove from Dock"], inMenuAt: point)
        XCTAssertFalse(model.showApplicationsStack)
    }

    func testStackSortOrders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StackSort-" + UUID().uuidString)
        folders.append(folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func make(_ name: String, modified: TimeInterval, created: TimeInterval) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data().write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified), .creationDate: Date(timeIntervalSince1970: created)], ofItemAtPath: url.path)
            return url
        }
        // Creation dates stay at or before modification dates, as the file system requires.
        let b = try make("b.txt", modified: 300, created: 10), a = try make("a.png", modified: 100, created: 50), c = try make("c.txt", modified: 200, created: 150)
        let d = try make("d.txt", modified: 200, created: 150)
        let urls = [c, a, d, b].map { URL(fileURLWithPath: $0.path) }
        func names(_ order: StackSortOrder) -> [String] { order.sorted(urls).map(\.lastPathComponent) }
        XCTAssertEqual(names(.name), ["a.png", "b.txt", "c.txt", "d.txt"])
        XCTAssertEqual(names(.dateModified), ["b.txt", "c.txt", "d.txt", "a.png"], "newest first, names break ties")
        XCTAssertEqual(names(.dateCreated), ["c.txt", "d.txt", "a.png", "b.txt"])
        XCTAssertEqual(names(.dateAdded).count, 4)
        let kinds = names(.kind)
        XCTAssertTrue(kinds.first == "a.png" || kinds.last == "a.png", "kinds group together: \(kinds)")
        XCTAssertEqual(kinds.filter { $0.hasSuffix(".txt") }, ["b.txt", "c.txt", "d.txt"], "names break ties within a kind")
        XCTAssertEqual(StackSortOrder.allCases.map(\.id), StackSortOrder.allCases.map(\.title))
        XCTAssertEqual(StackDisplayStyle.allCases.map(\.id), ["Folder", "Stack"])
        XCTAssertEqual(StackViewStyle.allCases.map(\.title), ["Fan", "Grid", "List", "Automatic"])
        let missing = folder.appendingPathComponent("missing")
        for order in StackSortOrder.allCases {
            XCTAssertEqual(Set(order.sorted([missing, a])), [missing, a], "unreadable items still sort: \(order)")
        }
        XCTAssertEqual(StackSortOrder.dateModified.sorted([missing, a]), [a, missing], "unreadable dates sort last")
    }

    func testLauncherWindowOpensClosesOnResignAndEscape() {
        let model = model(apps: 2)
        let launcher = AppsLauncher.shared
        launcher.close() // closing when nothing is open is a no-op
        launcher.show(model: model)
        let first = launcher.panel
        XCTAssertNotNil(first)
        XCTAssertTrue(first?.canBecomeKey ?? false, "the borderless chooser must take keyboard input")
        XCTAssertFalse(first?.hasShadow ?? true, "no shadow is cut from the still-empty window")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first)
        XCTAssertNil(launcher.panel, "losing key status dismisses the chooser")
        launcher.toggle(model: model)
        let second = launcher.panel
        XCTAssertNotNil(second)
        second?.cancelOperation(nil)
        XCTAssertNil(launcher.panel, "Esc dismisses the chooser")
        let deadline = Date().addingTimeInterval(5) // the fade-out completion orders the panel out
        while second?.contentView != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertFalse(second?.isVisible ?? true)
        XCTAssertNil(second?.contentView)
    }

    func testWindowShadowWaitsForTheEntranceToFinish() {
        let launcher = AppsLauncher.shared
        launcher.show(model: model(apps: 2))
        let panel = launcher.panel
        XCTAssertEqual(panel?.hasShadow, false)
        let deadline = Date().addingTimeInterval(5)
        while panel?.hasShadow == false, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(panel?.hasShadow, true, "the shadow is computed once both glass pieces are drawn")
    }

    func testOnlyTheGlassPiecesTakeClicks() {
        let size = AppsLauncher.panelSize, barBottom = AppsLauncher.barSize.height
        for point in [CGPoint(x: size.width / 2, y: barBottom / 2), CGPoint(x: 170, y: barBottom / 2), CGPoint(x: 660, y: barBottom / 2),
                      CGPoint(x: size.width / 2, y: 300), CGPoint(x: 1, y: 300), CGPoint(x: size.width / 2, y: size.height - 1)] {
            XCTAssertTrue(AppsLauncher.hits(point, in: size), "\(point) is on the glass")
        }
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: size.width - 1, y: 40), CGPoint(x: 80, y: 40), // beside the capsule
                      CGPoint(x: 164, y: 2), // the capsule's own corner
                      CGPoint(x: size.width / 2, y: barBottom + 5), // the gap
                      CGPoint(x: 2, y: barBottom + AppsLauncher.barGap + 2), CGPoint(x: size.width - 2, y: size.height - 2)] { // panel corners
            XCTAssertFalse(AppsLauncher.hits(point, in: size), "\(point) is transparent")
        }
    }

    func testClicksBesideTheGlassDismissLikeClickingOutside() {
        let launcher = AppsLauncher.shared, model = model(apps: 2)
        func click(_ type: NSEvent.EventType, x: CGFloat, topY: CGFloat, on panel: NSPanel) {
            panel.sendEvent(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: panel.frame.height - topY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        launcher.show(model: model)
        guard let panel = launcher.panel else { return XCTFail("no panel") }
        click(.leftMouseUp, x: 2, topY: 2, on: panel)
        XCTAssertNotNil(launcher.panel, "only a press dismisses")
        click(.rightMouseDown, x: AppsLauncher.pieces(in: panel.frame.size).bar.minX + 10, topY: 40, on: panel)
        XCTAssertNotNil(launcher.panel, "a click on the capsule stays open")
        click(.leftMouseDown, x: panel.frame.width / 2, topY: AppsLauncher.barSize.height + 5, on: panel)
        XCTAssertNil(launcher.panel, "a click in the gap closes")

        launcher.show(model: model)
        guard let reopened = launcher.panel else { return XCTFail("no panel") }
        click(.rightMouseDown, x: 2, topY: 2, on: reopened)
        XCTAssertNil(launcher.panel, "as does a right click in a corner")
    }

    func testReduceMotionKeepsTheFadeAndDropsTheScale() {
        XCTAssertEqual(AppsLauncherView.entranceScale(shown: false, reduceMotion: false), 0.96)
        XCTAssertEqual(AppsLauncherView.entranceScale(shown: true, reduceMotion: false), 1)
        XCTAssertEqual(AppsLauncherView.entranceScale(shown: false, reduceMotion: true), 1)
        XCTAssertEqual(AppsLauncherView.entrance(reduceMotion: true), .easeOut(duration: 0.16))
        XCTAssertNotEqual(AppsLauncherView.entrance(reduceMotion: false), .easeOut(duration: 0.16))

        let model = model(apps: 1)
        var entered = 0
        let view = AppsLauncherView(model: model, kit: model.toolkit, state: AppsChooserState(), close: {}, entered: { entered += 1 })
            .transformEnvironment(\.self) { $0._accessibilityReduceMotion = true }
        let harness = DockHarness(view, size: AppsLauncher.panelSize)
        defer { harness.close() }
        harness.spin(0.5)
        XCTAssertEqual(entered, 1, "the shortened entrance still finishes, so the shadow still appears")
    }

    /// Reduce Transparency and Increase Contrast, offscreen: opaque plates, a full border and a clear gap.
    /// DockPlate takes its non-glass path here, so this says nothing about real Liquid Glass.
    func testPlatesStayOpaqueAndOutlinedForAccessibilitySettings() throws {
        let model = model(apps: 0)
        let size = AppsLauncher.panelSize, results = AppsLauncher.pieces(in: size).results
        let view = AppsLauncherView(model: model, kit: model.toolkit, state: AppsChooserState()) {}
            .transformEnvironment(\.self) { $0._accessibilityReduceTransparency = true; $0._colorSchemeContrast = .increased }
        let harness = DockHarness(view, size: size)
        defer { harness.close() }
        harness.spin(0.6)
        let bitmap = try XCTUnwrap(harness.host.bitmapImageRepForCachingDisplay(in: harness.host.bounds))
        harness.host.cacheDisplay(in: harness.host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor { bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))!.usingColorSpace(.sRGB)! }
        XCTAssertEqual(color(size.width / 2, 40).alphaComponent, 1, accuracy: 0.01, "the capsule is opaque")
        XCTAssertEqual(color(100, results.midY).alphaComponent, 1, accuracy: 0.01, "and so is the panel")
        XCTAssertEqual(color(size.width / 2, 85).alphaComponent, 0, accuracy: 0.01, "the gap stays clear")
        XCTAssertEqual(color(1, 1).alphaComponent, 0, accuracy: 0.01, "and so do the corners")
        let fill = color(100, results.midY), edge = color(0.75, results.midY)
        XCTAssertGreaterThan(abs(fill.redComponent - edge.redComponent), 0.4, "the raised-contrast border is not cut off at the window edge")
    }

    func testPanelFloatsInTheUpperMiddleAndRemembersLayout() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let frame = AppsLauncher.frame(in: visible)
        XCTAssertEqual(frame.size, AppsLauncher.panelSize, "a fixed, sensible size rather than the whole screen")
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertGreaterThan(frame.midY, visible.midY, "sits above centre, like Spotlight")
        let small = AppsLauncher.frame(in: NSRect(x: 100, y: 50, width: 600, height: 400))
        XCTAssertEqual(small.size, CGSize(width: 552, height: 352), "shrinks to fit small screens")
        XCTAssertEqual(small.maxY, 426)

        let model = model(apps: 1)
        let launcher = AppsLauncher.shared
        launcher.show(model: model)
        XCTAssertLessThan(launcher.panel?.frame.width ?? .infinity, (launcher.panel?.screen ?? NSScreen.main)?.frame.width ?? 0)
        launcher.chooser.layout = .list
        launcher.close()
        XCTAssertEqual(model.defaults.string(forKey: "appsChooserLayout"), "list")
        launcher.chooser.category = .games
        launcher.show(model: model, query: "Sam")
        XCTAssertEqual(launcher.chooser.layout, .list, "the view choice persists between openings")
        XCTAssertEqual(launcher.chooser.query, "Sam")
        XCTAssertNil(launcher.chooser.category, "each opening starts on All")
        launcher.chooser.layout = .icons
    }

    func testSmallScreensKeepBothPiecesUsable() throws {
        XCTAssertEqual(AppsChooserState.columns(fitting: AppsLauncher.panelSize.width), 7)
        XCTAssertEqual(AppsChooserState.columns(fitting: 552), 6)
        XCTAssertEqual(AppsChooserState.columns(fitting: 452), 5)
        XCTAssertEqual(AppsChooserState.columns(fitting: 60), 1)

        let narrow = AppsLauncher.frame(in: NSRect(x: 0, y: 0, width: 500, height: 360))
        XCTAssertEqual(narrow.size, CGSize(width: 452, height: 312))
        let squeezed = AppsLauncher.pieces(in: narrow.size)
        XCTAssertEqual(squeezed.bar, CGRect(x: 0, y: 0, width: 452, height: 80), "the capsule narrows to the window")
        XCTAssertEqual(squeezed.results.height, 221)

        // The real view at a short, narrow size matches the geometry that decides which clicks dismiss.
        let size = AppsLauncher.frame(in: NSRect(x: 0, y: 0, width: 600, height: 400)).size
        let pieces = AppsLauncher.pieces(in: size)
        XCTAssertEqual(pieces.bar, CGRect(x: 17, y: 0, width: 518, height: 80))
        let model = model(apps: 8)
        let state = AppsChooserState()
        state.columns = AppsChooserState.columns(fitting: size.width)
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, state: state) {}, size: size)
        defer { harness.close() }
        harness.spin(0.5)
        let results = try XCTUnwrap(harness.frame("Applications")), button = try XCTUnwrap(harness.frame("View and category options"))
        XCTAssertEqual(results.width, pieces.results.width, accuracy: 1)
        XCTAssertEqual(results.height, pieces.results.height, accuracy: 1)
        XCTAssertEqual(results.minY, 0, accuracy: 1, "the panel ends at the bottom of the window")
        XCTAssertEqual(button.midY, size.height - pieces.bar.midY, accuracy: 1, "the capsule stays at the top")
        XCTAssertLessThan(button.maxX, pieces.bar.maxX, "with its menu button inside it")

        let first = try XCTUnwrap(harness.frame("Sample 00")), second = try XCTUnwrap(harness.frame("Sample 01")), wrapped = try XCTUnwrap(harness.frame("Sample 05"))
        XCTAssertLessThanOrEqual(first.maxX, second.minX + 1, "cells do not overlap")
        XCTAssertLessThan(wrapped.maxY, first.minY + 1, "the seventh app wraps to a second row of six")
        state.count = 20
        XCTAssertTrue(state.handleKey(key(125)))
        XCTAssertEqual(state.selection, 6, "Down moves by the visible row")
    }

    func testChooserSearchesFiltersAndLaunches() {
        let model = model(apps: 40) // 41 with Finder
        let state = AppsChooserState()
        var closed = 0
        let view = AppsLauncherView(model: model, kit: model.toolkit, state: state) { closed += 1 }
        let harness = DockHarness(view, size: AppsLauncher.panelSize)
        defer { harness.close() }
        harness.spin(0.4)
        XCTAssertEqual(state.count, 41)
        XCTAssertTrue(harness.has("Applications"), "launch mode names the results panel Applications")
        let index = model.toolkit.appIndex
        XCTAssertEqual(state.results(in: index).map { index.name(of: $0) }.prefix(2), ["Finder", "Sample 00"], "an empty search lists apps by name")

        XCTAssertTrue(harness.has("View and category options"), "\(harness.labels())")

        // Search filters at once; the arrow keys move the selection and Return picks it.
        harness.enter("Sample 0")
        harness.spin(0.3)
        XCTAssertEqual(state.count, 10)
        XCTAssertTrue(harness.has("Clear search"))
        XCTAssertTrue(state.handleKey(key(124)))
        XCTAssertEqual(state.selection, 1)
        harness.spin(0.2)
        let field = harness.textFields()[0]
        if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
        harness.spin()
        XCTAssertEqual(launched.last?.lastPathComponent, "Sample 01.app")
        XCTAssertEqual(closed, 1)
        harness.press("Clear search")
        harness.enter("zzzz-no-such-app")
        harness.spin(0.3)
        XCTAssertEqual(state.count, 0)
        XCTAssertEqual(state.selection, 0)
        if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
        XCTAssertEqual(closed, 1, "Return with no match does nothing")
        harness.enter("")
        harness.spin(0.3)

        // Icons: hover, click to launch, and their context menu.
        guard let icon = harness.center("Sample 01") else { return XCTFail("icon missing: \(harness.labels())") }
        harness.hover(icon, entering: true)
        harness.hover(icon, entering: false)
        harness.press("Sample 01")
        XCTAssertEqual(launched.last?.lastPathComponent, "Sample 01.app")
        XCTAssertEqual(harness.menuTitles(at: icon), ["Open", "Keep in Dock", "Show in Finder"])
        harness.choose("Open", inMenuAt: icon)
        XCTAssertEqual(launched.count, 3)
        harness.choose("Keep in Dock", inMenuAt: icon)
        XCTAssertTrue(model.apps.contains { $0.url.lastPathComponent == "Sample 01.app" })
        harness.choose("Show in Finder", inMenuAt: icon)
        if case .reveal(let urls)? = effects.last { XCTAssertEqual(urls.first?.lastPathComponent, "Sample 01.app") } else { XCTFail("reveal should go through effects") }

        // The list shows the same apps one per row and scrolls to keep the selection visible.
        state.layout = .list
        harness.spin(0.2)
        XCTAssertTrue(harness.has("Sample 02"), "\(harness.labels())")
        state.selection = 35
        harness.spin(0.3)
        state.layout = .icons
    }

    /// Presses the labelled "…" button as an assistive client would and returns the menu it pops.
    private func openOptions(_ harness: DockHarness) -> NSMenu? {
        var opened: NSMenu?
        AppsLauncher.shared.presentOptions = { menu, button in
            opened = menu
            XCTAssertNotNil(button.window, "the menu anchors to the on-screen button")
        }
        harness.press("View and category options")
        return opened
    }

    private func choose(_ title: String, from harness: DockHarness) {
        guard let menu = openOptions(harness), let index = menu.items.firstIndex(where: { $0.title == title }) else { return XCTFail("no menu item \(title)") }
        menu.performActionForItem(at: index)
        harness.spin(0.2)
    }

    func testOptionsMenuChangesTheViewAndCategory() {
        let model = model(apps: 25) // Utilities, Games, and uncategorized
        let state = AppsChooserState()
        state.reset(query: "", defaults: model.defaults)
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, state: state) {}, size: AppsLauncher.panelSize)
        defer { harness.close() }
        harness.spin(0.4)

        let menu = openOptions(harness)
        let titles = menu?.items.map(\.title) ?? []
        XCTAssertEqual(Array(titles.prefix(4)), ["View as Icons", "View as List", "", "All Categories"])
        XCTAssertTrue(["Utilities", "Games", "Other"].allSatisfy(titles.contains), "\(titles)")
        XCTAssertFalse(titles.contains("Social"), "only categories that have apps")
        XCTAssertEqual(menu?.items.filter { $0.state == .on }.map(\.title), ["View as Icons", "All Categories"])
        XCTAssertNotNil(menu?.items.first?.image)
        XCTAssertTrue(menu?.items[2].isSeparatorItem ?? false, "view and category choices are separate groups")

        choose("View as List", from: harness)
        XCTAssertEqual(state.layout, .list)
        XCTAssertEqual(model.defaults.string(forKey: "appsChooserLayout"), "list")
        choose("Games", from: harness)
        XCTAssertEqual(state.category, .games)
        XCTAssertEqual(state.count, 10)
        XCTAssertEqual(openOptions(harness)?.items.filter { $0.state == .on }.map(\.title), ["View as List", "Games"])

        state.selection = 3
        choose("All Categories", from: harness)
        XCTAssertNil(state.category)
        XCTAssertEqual(state.selection, 0, "changing the category restarts the selection")
        choose("View as Icons", from: harness)
        XCTAssertEqual(state.layout, .icons)
        XCTAssertEqual(state.optionsMenu(apps: []).items.map(\.title), ["View as Icons", "View as List", "", "All Categories"])
    }

    func testArrowKeysMoveTheSelectionByIconAndRow() {
        let launcher = AppsLauncher.shared
        launcher.show(model: model(apps: 2))
        let state = launcher.chooser
        state.count = 20
        launcher.panel?.keyDown(with: key(124)) // right
        XCTAssertEqual(state.selection, 1)
        launcher.panel?.keyDown(with: key(125)) // down one row of seven
        XCTAssertEqual(state.selection, 1 + state.columns)
        launcher.panel?.keyDown(with: key(126)) // up
        XCTAssertEqual(state.selection, 1)
        launcher.panel?.keyDown(with: key(123)) // left
        XCTAssertEqual(state.selection, 0)
        launcher.panel?.keyDown(with: key(123))
        XCTAssertEqual(state.selection, 0, "the selection stops at the first app")
        state.selection = 18
        state.move(7)
        XCTAssertEqual(state.selection, 19, "and at the last")
        launcher.panel?.keyDown(with: key(0)) // other keys pass through to AppKit
        XCTAssertEqual(state.selection, 19)
        state.layout = .list
        XCTAssertFalse(state.handleKey(key(124)), "left and right stay with the search text in the list")
        XCTAssertTrue(state.handleKey(key(126)))
        XCTAssertEqual(state.selection, 18, "up moves one row in the list")
        state.count = 0
        state.move(1)
        XCTAssertEqual(state.selection, 18, "an empty result list leaves the selection alone")
        state.layout = .icons
    }

    func testCategoriesFollowTheBundleCategoryType() {
        let app = "/Applications/A.app"
        let cases: [(String?, String, AppCategory)] = [
            ("public.app-category.productivity", app, .productivity),
            ("public.app-category.finance", app, .productivity),
            ("public.app-category.photography", app, .creativity),
            ("public.app-category.developer-tools", app, .developer),
            ("public.app-category.utilities", app, .utilities),
            ("public.app-category.social-networking", app, .social),
            ("public.app-category.entertainment", app, .entertainment),
            ("public.app-category.news", app, .reading),
            ("public.app-category.education", app, .education),
            ("public.app-category.games", app, .games),
            ("public.app-category.puzzle-games", app, .games),
            ("public.app-category.healthcare-fitness", app, .health),
            ("public.app-category.travel", app, .other),
            (nil, "/System/Applications/Utilities/Terminal.app", .utilities),
            (nil, app, .other),
        ]
        for (type, path, expected) in cases { XCTAssertEqual(AppCategory(categoryType: type, path: path), expected, type ?? path) }
    }

    func testPlusAndReplaceOpenTheLauncherInTheirModes() {
        let model = model(apps: 2)
        let launcher = AppsLauncher.shared
        model.systemError = "stale"
        model.addApps()
        let first = launcher.panel
        XCTAssertNotNil(first, "+ opens the Applications chooser")
        XCTAssertNil(model.systemError)
        let sample = model.toolkit.appIndex.search("Sample 00")[0]
        model.showAppPicker(replacing: sample) // reopening while open swaps in a fresh panel
        XCTAssertNotNil(launcher.panel)
        XCTAssertFalse(launcher.panel === first)
        XCTAssertEqual(launcher.mode, .replace(sample))
        launcher.closeEditing()
        XCTAssertNil(launcher.panel, "losing the licence closes a replace launcher")
        model.showAppLauncher(query: "Sample")
        XCTAssertFalse(launcher.chooser.searchIsEmpty, "a widget query pre-fills the search")
        launcher.closeEditing()
        XCTAssertNotNil(launcher.panel, "a plain launch launcher stays open without a licence")
        launcher.close()
        XCTAssertEqual(launcher.mode, .launch)
        XCTAssertEqual(AppsLauncher.Mode.launch.title, nil)
        XCTAssertEqual(AppsLauncher.Mode.replace(sample).title, "Replace " + sample.name)
    }

    func testAddModePinsOnceAndCloses() {
        let model = model(apps: 3)
        var closed = 0
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, state: AppsChooserState(), mode: .add) { closed += 1 }, size: AppsLauncher.panelSize)
        defer { harness.close() }
        harness.spin(0.4)
        XCTAssertTrue(harness.has("Add an app to the Dock"), "\(harness.labels())")
        harness.press("Sample 01")
        XCTAssertEqual(model.apps.map(\.url.lastPathComponent), ["Sample 01.app"])
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(launched.isEmpty, "adding never launches")
        harness.spin(0.2)
        harness.press("Sample 01")
        XCTAssertEqual(model.apps.count, 1, "an app already in the Dock is not added again")
        XCTAssertEqual(closed, 1)
        // Return adds the selected (top) match; a vanished bundle reports the error inline and stays open.
        harness.enter("Sample 02")
        harness.spin(0.3)
        let field = harness.textFields()[0]
        if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
        XCTAssertEqual(model.apps.count, 2)
        XCTAssertEqual(closed, 2)
        try? FileManager.default.removeItem(at: model.toolkit.appIndex.search("Sample 00")[0].url)
        harness.enter("Sample 00")
        harness.spin(0.3)
        if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
        harness.spin(0.2)
        XCTAssertEqual(closed, 2)
        XCTAssertEqual(model.systemError, "This application is no longer installed.")
    }

    func testReplaceModeSwapsTheTile() {
        let model = model(apps: 3)
        let index = model.toolkit.appIndex
        let old = index.search("Sample 00")[0], new = index.search("Sample 01")[0]
        model.apps = [old]
        model.systemError = "Problem" // renders the inline error in the header
        var closed = 0
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, state: AppsChooserState(), mode: .replace(old)) { closed += 1 }, size: AppsLauncher.panelSize)
        defer { harness.close() }
        harness.spin(0.4)
        XCTAssertTrue(harness.has("Replace " + old.name), "\(harness.labels())")
        harness.press("Sample 00") // already in the Dock: rejected, chooser stays open
        XCTAssertEqual(closed, 0)
        XCTAssertEqual(model.systemError, "That application is already in the Dock.")
        harness.press("Sample 01")
        XCTAssertEqual(model.apps, [new])
        XCTAssertEqual(closed, 1)
    }

    func testExistingLayoutDoesNotGainApplicationsStack() {
        let model = model(apps: 0)
        model.defaults.set([], forKey: "apps")
        model.defaults.removeObject(forKey: "showApplicationsStack")
        XCTAssertFalse(DockModel(defaults: model.defaults, purchasesEnabled: false).showApplicationsStack)
        model.defaults.removeObject(forKey: "apps")
        XCTAssertTrue(DockModel(defaults: model.defaults, purchasesEnabled: false).showApplicationsStack)
    }

    func testStackLeadsTheDockWhenEnabled() {
        let model = model(apps: 0)
        model.showApplicationsStack = true
        XCTAssertEqual(model.dockEntries.first?.id, DockEntry.applicationsID)
        XCTAssertEqual(model.defaults.object(forKey: "showApplicationsStack") as? Bool, true)
        model.showApplicationsStack = false
        XCTAssertEqual(model.dockEntries.map(\.id), model.orderedEntries.map(\.id))
    }

    func testEmptyCatalogShowsPlaceholder() {
        let model = model(apps: 0)
        model.toolkit.applicationRoots = []
        let state = AppsChooserState()
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, state: state) {}, size: AppsLauncher.panelSize)
        defer { harness.close() }
        harness.enter("nothing matches this")
        harness.spin(0.3)
        XCTAssertEqual(state.count, 0)
        harness.enter("")
        state.category = .games
        harness.spin(0.3)
        XCTAssertEqual(state.count, 0, "a category with no apps is empty without any search")
    }

    func testIndexEdgeCasesAndYAMLParsing() {
        let records = [
            AppSearchIndex.Record(path: "/Apps/One.app", name: "One", bundleIdentifier: "test.one", modified: nil, aliases: [], lookups: ["ed": 2, "editor": 5]),
            AppSearchIndex.Record(path: "/Apps/Two.app", name: "Two", bundleIdentifier: nil, modified: nil, aliases: [], lookups: ["ed": 7]),
        ]
        let index = AppSearchIndex(records)
        XCTAssertEqual(index.search("ed").first?.id, "/Apps/Two.app", "the most-launched learned match ranks first")
        let stranger = DockApp(url: URL(fileURLWithPath: "/Elsewhere/Stranger.app"))
        XCTAssertEqual(index.name(of: stranger), stranger.name, "apps outside the index fall back to their bundle name")
        XCTAssertTrue(index.apps(named: "nothing-by-this-name").isEmpty)

        // Lookups are written most-launched first.
        let yaml = AppIndexYAML.encode(records)
        XCTAssertLessThan(yaml.range(of: "\"editor\": 5")!.lowerBound, yaml.range(of: "\"ed\": 2")!.lowerBound)
        XCTAssertEqual(AppIndexYAML.decode(yaml), records)

        // Hand-edited files: bare and quoted list items, a single bare alias, and unterminated quotes.
        let edited = AppIndexYAML.decode("""
        apps:
          - name: Bare
            path: /Apps/Bare.app
            aliases: [first, "second", third]
          - name: Single
            path: /Apps/Single.app
            aliases: solo
          - name: Empty
            path: /Apps/Empty.app
            aliases:
          - name: "Broken
            path: /Apps/Broken.app
            aliases: ["unterminated]
        """)
        XCTAssertEqual(edited.map(\.aliases), [["first", "second", "third"], ["solo"], [], ["\"unterminated"]])
        XCTAssertEqual(edited.last?.name, "", "an unterminated quoted scalar reads as empty")
    }

    func testIncompleteQuotedIndexFieldsDoNotSwallowFollowingRecords() {
        // A lone opening quote takes the zero-character recovery path. A trailing
        // escape and malformed lookup key must also leave the next app intact.
        let parsed = AppIndexYAML.decode(#"""
        apps:
          - name: "
            path: /Apps/Incomplete.app
            aliases: ["]
            lookups:
              "unfinished: 7
          - name: "Trailing\
            path: /Apps/Trailing.app
          - name: "Valid"
            path: /Apps/Valid.app
            aliases: ["line\nbreak", "quoted\"name", "back\\slash"]
        """#)
        XCTAssertEqual(parsed.map(\.path), ["/Apps/Incomplete.app", "/Apps/Trailing.app", "/Apps/Valid.app"])
        XCTAssertEqual(parsed.map(\.name), ["", "", "Valid"])
        XCTAssertEqual(parsed.first?.aliases, ["\""])
        XCTAssertTrue(parsed.first?.lookups.isEmpty == true)
        XCTAssertEqual(parsed.last?.aliases, ["line\nbreak", "quoted\"name", "back\\slash"])
    }

    // MARK: Stack popover

    private var visible: CGRect { CGRect(x: 0, y: 0, width: 1440, height: 875) }
    private var content: CGSize { CGSize(width: 500, height: 300) }
    private var bottomTile: CGRect { CGRect(x: 700, y: 10, width: 64, height: 64) }

    func testPlacementRisesFromBottomDockAndDropsFromTopDock() {
        let bottom = StackPopoverLayout.place(content: content, anchor: bottomTile, visible: visible, edge: "Bottom")
        XCTAssertTrue(bottom.opensUpward)
        XCTAssertEqual(bottom.frame, CGRect(x: 482, y: 76, width: 500, height: 300 + StackPopoverLayout.arrowHeight))
        XCTAssertEqual(bottom.arrowX, 250, "the arrow points at the tile's centre")

        let topTile = CGRect(x: 700, y: 800, width: 64, height: 64)
        let top = StackPopoverLayout.place(content: content, anchor: topTile, visible: visible, edge: "Top")
        XCTAssertFalse(top.opensUpward)
        XCTAssertEqual(top.frame.maxY, topTile.minY - StackPopoverLayout.gap, "a top Dock's stack hangs below the tile")
        XCTAssertEqual(top.frame.height, 300 + StackPopoverLayout.arrowHeight)
    }

    func testFloatingDockOpensTowardTheRoomierSide() {
        let middle = StackPopoverLayout.place(content: content, anchor: CGRect(x: 700, y: 400, width: 64, height: 64), visible: visible, edge: "Floating")
        XCTAssertTrue(middle.opensUpward, "floating docks prefer opening upward when it fits")
        let high = StackPopoverLayout.place(content: content, anchor: CGRect(x: 700, y: 700, width: 64, height: 64), visible: visible, edge: "Floating")
        XCTAssertFalse(high.opensUpward, "near the top there is more room below")
        XCTAssertEqual(high.frame.maxY, 698)
        let unknown = StackPopoverLayout.place(content: content, anchor: bottomTile, visible: visible, edge: "Left")
        XCTAssertTrue(unknown.opensUpward, "unrecognised edges behave like the bottom Dock")
    }

    func testPlacementClampsToTheScreenAndKeepsTheArrowOnTheTile() {
        let left = StackPopoverLayout.place(content: content, anchor: CGRect(x: 5, y: 10, width: 64, height: 64), visible: visible, edge: "Bottom")
        XCTAssertEqual(left.frame.minX, StackPopoverLayout.margin)
        XCTAssertEqual(left.arrowX, 30, "the arrow stays on the tile, out of the rounded corner")
        let corner = StackPopoverLayout.place(content: content, anchor: CGRect(x: -40, y: 10, width: 64, height: 64), visible: visible, edge: "Bottom")
        XCTAssertEqual(corner.arrowX, StackPopoverLayout.cornerRadius + StackPopoverLayout.arrowWidth / 2, "the arrow never slides into the rounded corner")
        let right = StackPopoverLayout.place(content: content, anchor: CGRect(x: 1400, y: 10, width: 64, height: 64), visible: visible, edge: "Bottom")
        XCTAssertEqual(right.frame.maxX, visible.maxX - StackPopoverLayout.margin)
        XCTAssertEqual(right.arrowX, 500 - StackPopoverLayout.cornerRadius - StackPopoverLayout.arrowWidth / 2)
        let tall = StackPopoverLayout.place(content: CGSize(width: 3000, height: 2000), anchor: bottomTile, visible: visible, edge: "Bottom")
        XCTAssertEqual(tall.frame.maxY, visible.maxY - StackPopoverLayout.margin, "a tall grid shrinks to the screen and scrolls")
        XCTAssertEqual(tall.frame.width, visible.width - StackPopoverLayout.margin * 2)
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let other = StackPopoverLayout.place(content: content, anchor: CGRect(x: 1450, y: -190, width: 64, height: 64), visible: second, edge: "Bottom")
        XCTAssertEqual(other.frame.minX, second.minX + StackPopoverLayout.margin, "clamping uses the tile's own display")
        XCTAssertTrue(second.contains(other.frame))
    }

    func testStylesResolveLikeTheDock() {
        XCTAssertEqual(StackViewStyle.automatic.resolved(itemCount: 5, opensUpward: true), .fan)
        XCTAssertEqual(StackViewStyle.automatic.resolved(itemCount: 200, opensUpward: true), .grid)
        XCTAssertEqual(StackViewStyle.automatic.resolved(itemCount: 5, opensUpward: false), .grid)
        XCTAssertEqual(StackViewStyle.fan.resolved(itemCount: 5, opensUpward: false), .list, "Fan only rises from the Dock")
        XCTAssertEqual(StackViewStyle.list.resolved(itemCount: 5, opensUpward: true), .list)
        XCTAssertEqual(StackViewStyle.allCases.map(\.title), ["Fan", "Grid", "List", "Automatic"])
        XCTAssertEqual(StackPopoverLayout.gridColumns(count: 1), 3)
        XCTAssertEqual(StackPopoverLayout.gridColumns(count: 20), 5)
        XCTAssertEqual(StackPopoverLayout.gridColumns(count: 400), 7)
        let grid = StackPopoverLayout.contentSize(style: .grid, count: 400)
        XCTAssertEqual(grid.height, 5 * StackPopoverLayout.gridCell.height + 32 + StackPopoverLayout.footer, "large grids cap their height and scroll")
        XCTAssertEqual(StackPopoverLayout.contentSize(style: .automatic, count: 400), grid)
        XCTAssertEqual(StackPopoverLayout.contentSize(style: .list, count: 3).width, StackPopoverLayout.listWidth)
        XCTAssertGreaterThan(StackPopoverLayout.contentSize(style: .fan, count: 30).height, StackPopoverLayout.contentSize(style: .fan, count: 3).height)
        let shape = StackCalloutShape(arrowOnBottom: true, arrowX: 100).path(in: CGRect(x: 0, y: 0, width: 200, height: 120))
        XCTAssertTrue(shape.contains(CGPoint(x: 100, y: 116)), "the arrow reaches toward the tile")
        XCTAssertFalse(shape.contains(CGPoint(x: 20, y: 116)))
        XCTAssertTrue(StackCalloutShape(arrowOnBottom: false, arrowX: 100).path(in: CGRect(x: 0, y: 0, width: 200, height: 120)).contains(CGPoint(x: 100, y: 4)))
    }

    func testStackPopoverAnchorsToTheDockEdgeAndPicksItsStyle() {
        let model = model(apps: 3)
        let stack = AppsStackPopover.shared
        stack.show(model: model, anchor: bottomTile, visible: visible)
        XCTAssertEqual(stack.style, .fan, "Automatic fans a small stack above a bottom Dock")
        XCTAssertEqual(stack.panel?.frame, stack.placement?.frame)
        XCTAssertTrue(stack.placement?.opensUpward ?? false)
        XCTAssertTrue(stack.panel?.canBecomeKey ?? false, "the stack takes keyboard input")
        XCTAssertEqual(stack.apps.map(\.name), stack.apps.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        model.toolkit.edge = "Top"
        model.applicationsStackStyle = .fan
        stack.show(model: model, anchor: CGRect(x: 700, y: 800, width: 64, height: 64), visible: visible)
        XCTAssertFalse(stack.placement?.opensUpward ?? true)
        XCTAssertEqual(stack.style, .list, "a top Dock cannot fan, so it lists")
        XCTAssertLessThanOrEqual(stack.panel?.frame.maxY ?? .infinity, 798)

        model.replacingDock = true // replacing the system Dock always lays out at the bottom
        model.applicationsStackStyle = .grid
        stack.show(model: model, anchor: bottomTile, visible: visible)
        XCTAssertTrue(stack.placement?.opensUpward ?? false)
        XCTAssertEqual(stack.style, .grid)
        XCTAssertEqual(stack.navigator.columns, 3)
        model.replacingDock = false
        model.toolkit.edge = "Bottom"
        stack.close()
        XCTAssertNil(stack.panel)
    }

    func testStackClosesOnEscapeClickOutsideAndResign() {
        let model = model(apps: 2)
        let stack = AppsStackPopover.shared
        stack.close() // no-op when closed
        stack.dismiss()
        stack.show(model: model, anchor: bottomTile, visible: visible)
        let first = stack.panel
        first?.cancelOperation(nil)
        XCTAssertNil(stack.panel, "Esc closes the stack")

        stack.show(model: model, anchor: bottomTile, visible: visible)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: stack.panel)
        XCTAssertNil(stack.panel, "losing focus closes the stack")
        stack.toggle(model: model, anchor: bottomTile)
        XCTAssertNil(stack.panel, "the tile click that dismissed the stack does not reopen it")
        stack.dismissalGrace = 0
        stack.toggle(model: model, anchor: bottomTile)
        XCTAssertNotNil(stack.panel)

        // A click in another of DockGrove's windows dismisses it through the local monitor.
        let other = DockHarness(Color.clear, size: CGSize(width: 50, height: 50))
        defer { other.close() }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { // through NSApp so local monitors see it
            NSApp.sendEvent(NSEvent.mouseEvent(with: type, location: CGPoint(x: 10, y: 10), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: other.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        XCTAssertNil(stack.panel, "clicking outside closes the stack")
        let deadline = Date().addingTimeInterval(5)
        while first?.contentView != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertNil(first?.contentView)
    }

    private func typed(_ text: String, code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }

    func testKeyboardNavigatesAndLaunches() {
        let model = model(apps: 4)
        model.applicationsStackStyle = .grid
        let stack = AppsStackPopover.shared
        stack.show(model: model, anchor: bottomTile, visible: visible)
        let nav = stack.navigator, count = stack.apps.count // 4 samples + Finder
        XCTAssertEqual(count, 5)
        XCTAssertNil(nav.selection)
        stack.panel?.keyDown(with: key(124))
        XCTAssertEqual(nav.selection, 0, "the first arrow selects the first item")
        stack.panel?.keyDown(with: key(125))
        XCTAssertEqual(nav.selection, 3, "Down moves a row in the grid")
        stack.panel?.keyDown(with: key(125))
        XCTAssertEqual(nav.selection, count - 1, "movement clamps to the last item")
        stack.panel?.keyDown(with: key(126))
        stack.panel?.keyDown(with: key(123))
        XCTAssertEqual(nav.selection, 0)
        XCTAssertTrue(nav.handleKey(typed("s", code: 1)), "typing jumps to a matching name")
        XCTAssertTrue(nav.names[nav.selection!].lowercased().hasPrefix("s"))
        XCTAssertFalse(nav.handleKey(typed("§", code: 10)))
        XCTAssertFalse(nav.handleKey(typed("q", code: 12)), "no app starts with q")
        nav.selection = nav.names.firstIndex(of: "Sample 02")
        stack.panel?.keyDown(with: key(36))
        XCTAssertEqual(launched.last?.lastPathComponent, "Sample 02.app", "Return launches the selection")
        XCTAssertNil(stack.panel, "launching closes the stack")

        let fan = StackNavigator()
        fan.reset(names: ["A", "B", "C"], columns: -1)
        fan.move(-1); XCTAssertEqual(fan.selection, 2, "the first backwards move starts from the end")
        _ = fan.handleKey(key(126)); XCTAssertEqual(fan.selection, 2, "Up climbs the fan, clamped")
        _ = fan.handleKey(key(125)); XCTAssertEqual(fan.selection, 1)
        XCTAssertTrue(fan.handleKey(key(36)), "Return is consumed")
        StackNavigator().move(1) // empty stacks ignore movement
    }

    func testStackViewsLaunchAndOpenInFinder() {
        let model = model(apps: 3)
        let items = AppsStackPopover.contents(of: model.toolkit)
        let byKind = AppsStackPopover.contents(of: model.toolkit, sort: .kind)
        XCTAssertEqual(Set(byKind.map(\.app.url)), Set(items.map(\.app.url)), "Sort by reorders the stack without dropping apps")
        XCTAssertEqual(byKind.map(\.app.url), StackSortOrder.kind.sorted(items.map(\.app.url)), "the stack follows the Sort by choice")
        for style in [StackViewStyle.grid, .list, .fan] {
            let size = StackPopoverLayout.contentSize(style: style, count: items.count)
            let placement = StackPopoverLayout.place(content: size, anchor: bottomTile, visible: visible, edge: "Bottom")
            var opened: [DockApp] = [], finder = 0
            let navigator = StackNavigator()
            navigator.selection = 1
            let view = AppsStackView(model: model, kit: model.toolkit, navigator: navigator, style: style, placement: placement, items: items,
                                     launch: { opened.append($0) }, openInFinder: { finder += 1 })
            let harness = DockHarness(view, size: placement.frame.size)
            defer { harness.close() }
            harness.spin(0.2)
            XCTAssertTrue(harness.has("Open in Finder"), "\(style): \(harness.labels())")
            harness.press("Sample 01")
            XCTAssertEqual(opened.last?.url.lastPathComponent, "Sample 01.app", "\(style)")
            harness.press("Open in Finder")
            XCTAssertEqual(finder, 1, "\(style)")
            navigator.selection = 2
            harness.spin(0.1)
            guard let icon = harness.center("Sample 00") else { XCTFail("\(style): Sample 00 missing: \(harness.labels())"); continue }
            harness.hover(icon, entering: true)
            harness.hover(icon, entering: false)
            XCTAssertEqual(harness.menuTitles(at: icon), ["Open", "Show in Finder"], "\(style)")
            harness.choose("Show in Finder", inMenuAt: icon)
            if case .reveal(let urls)? = effects.last { XCTAssertEqual(urls.first?.lastPathComponent, "Sample 00.app") } else { XCTFail("reveal should go through effects") }
            harness.choose("Open", inMenuAt: icon)
            XCTAssertEqual(opened.last?.url.lastPathComponent, "Sample 00.app", "\(style)")
        }
        // An empty catalog shows a placeholder and still offers Open in Finder.
        let empty = StackPopoverLayout.place(content: StackPopoverLayout.contentSize(style: .grid, count: 0), anchor: bottomTile, visible: visible, edge: "Bottom")
        let harness = DockHarness(AppsStackView(model: model, kit: model.toolkit, navigator: StackNavigator(), style: .grid, placement: empty, items: [], launch: { _ in }, openInFinder: {}), size: empty.frame.size)
        defer { harness.close() }
        harness.spin(0.2)
        XCTAssertTrue(harness.has("Open in Finder"))
        XCTAssertEqual(harness.labels(), ["Applications stack", "Open in Finder"], "no app buttons in an empty stack")
    }

    func testOpenInFinderAndLaunchFromTheController() {
        let model = model(apps: 1)
        let stack = AppsStackPopover.shared
        stack.show(model: model, anchor: bottomTile, visible: visible)
        stack.openInFinder()
        XCTAssertNil(stack.panel)
        if case .open(let url)? = effects.last { XCTAssertEqual(url.path, "/Applications") } else { XCTFail("Open in Finder goes through effects") }
        stack.show(model: model, anchor: bottomTile, visible: visible)
        stack.navigator.activate(99) // out of range: ignored
        XCTAssertNotNil(stack.panel)
        stack.launch(stack.apps[0])
        XCTAssertNil(stack.panel)
        XCTAssertEqual(launched.count, 1)
    }
}
