import XCTest
import SwiftUI
@testable import DockGrove

/// Covers the Applications stack tile and its full-screen launcher without touching the real
/// desktop: apps come from a temporary folder, launching and Finder effects are recorded, and
/// the launcher panel is never brought on screen.
@MainActor final class ApplicationsStackTests: XCTestCase {
    private var suites: [String] = []
    private var folders: [URL] = []
    private var effects: [DockSystemEffect] = []
    private var launched: [URL] = []
    private let originalHandler = DockSystemEffect.handler
    private let originalPresent = AppsLauncher.shared.present

    override func setUp() {
        super.setUp()
        DockSystemEffect.handler = { [unowned self] in self.effects.append($0) }
        AppsLauncher.shared.present = { _ in }
    }

    override func tearDown() {
        AppsLauncher.shared.close()
        DockSystemEffect.handler = originalHandler
        AppsLauncher.shared.present = originalPresent
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        folders.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    /// A model whose catalog is `count` fake bundles plus Finder, scanned and ready.
    private func model(apps count: Int) -> DockModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppsStack-" + UUID().uuidString)
        folders.append(folder)
        for index in 0..<count {
            let contents = folder.appendingPathComponent(String(format: "Sample %02d.app/Contents", index))
            try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "test.sample.\(index)", "CFBundleName": String(format: "Sample %02d", index)]
            try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        let suite = "ApplicationsStackTests." + UUID().uuidString
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set([], forKey: "apps"); defaults.set(false, forKey: "showRunning")
        let model = DockModel(defaults: defaults)
        model.openApplication = { [unowned self] in self.launched.append($0) }
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

    func testTileTogglesLauncherAndOffersFolderActions() {
        let model = model(apps: 3)
        let harness = DockHarness(ApplicationsStackTile(model: model), size: CGSize(width: 90, height: 90))
        defer { harness.close() }
        let point = CGPoint(x: 45, y: 50)
        harness.hover(point, entering: true)
        harness.hover(CGPoint(x: 300, y: 300), entering: false)
        harness.press("Applications")
        XCTAssertNotNil(AppsLauncher.shared.panel, "pressing the tile opens the launcher")
        harness.press("Applications")
        XCTAssertNil(AppsLauncher.shared.panel, "pressing it again closes the launcher")
        XCTAssertEqual(harness.menuTitles(at: point), ["Open Applications Folder", "Refresh Applications"])
        harness.choose("Open Applications Folder", inMenuAt: point)
        if case .open(let url)? = effects.last { XCTAssertEqual(url.path, "/Applications") } else { XCTFail("folder should open through effects") }
        let before = model.toolkit.appIndex.count
        let extra = URL(fileURLWithPath: model.toolkit.applicationRoots[0]).appendingPathComponent("Added Later.app/Contents")
        try? FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        harness.choose("Refresh Applications", inMenuAt: point)
        let deadline = Date().addingTimeInterval(10)
        while model.toolkit.appIndex.count == before, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(model.toolkit.appIndex.count, before + 1, "refresh rescans and finds the new app")
    }

    func testLauncherWindowOpensClosesOnResignAndEscape() {
        let model = model(apps: 2)
        let launcher = AppsLauncher.shared
        launcher.close() // closing when nothing is open is a no-op
        launcher.show(model: model)
        let first = launcher.panel
        XCTAssertNotNil(first)
        XCTAssertTrue(first?.canBecomeKey ?? false, "the borderless launcher must take keyboard input")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first)
        XCTAssertNil(launcher.panel, "losing key status dismisses the launcher")
        launcher.toggle(model: model)
        let second = launcher.panel
        XCTAssertNotNil(second)
        second?.cancelOperation(nil)
        XCTAssertNil(launcher.panel, "Esc dismisses the launcher")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4)) // fade-out completion orders the panel out
        XCTAssertFalse(second?.isVisible ?? true)
        XCTAssertNil(second?.contentView)
    }

    func testLauncherPagesSearchesAndLaunches() {
        let model = model(apps: 40) // 41 with Finder: two 7x5 pages
        let pager = AppsPager()
        var closed = 0
        let view = AppsLauncherView(model: model, kit: model.toolkit, pager: pager) { closed += 1 }
        let harness = DockHarness(view, size: CGSize(width: 1400, height: 900))
        defer { harness.close() }
        harness.spin(0.4)
        XCTAssertEqual(pager.count, 2)
        XCTAssertTrue(harness.has("Page 2 of 2"), "\(harness.labels())")
        harness.press("Page 2 of 2")
        XCTAssertEqual(pager.page, 1)
        pager.go(9); XCTAssertEqual(pager.page, 1, "paging clamps to the last page")
        view.finishDrag(predicted: 300); XCTAssertEqual(pager.page, 0)
        view.finishDrag(predicted: -300); XCTAssertEqual(pager.page, 1)
        view.finishDrag(predicted: 20); XCTAssertEqual(pager.page, 1, "short drags stay on the page")
        harness.drag(from: CGPoint(x: 700, y: 30), to: CGPoint(x: 200, y: 30))
        harness.drag(from: CGPoint(x: 200, y: 30), to: CGPoint(x: 900, y: 30))
        harness.spin(0.4)

        // Search filters, resets to the first page and launches the top match on Return.
        harness.enter("Sample 07")
        harness.spin(0.3)
        XCTAssertEqual(pager.page, 0)
        XCTAssertEqual(pager.count, 1)
        XCTAssertTrue(harness.has("Clear search"))
        let field = harness.textFields()[0]
        if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
        harness.spin()
        XCTAssertEqual(launched.last?.lastPathComponent, "Sample 07.app")
        XCTAssertEqual(closed, 1)
        harness.press("Clear search")
        harness.enter("zzzz-no-such-app")
        harness.spin(0.3)
        XCTAssertTrue(model.toolkit.appIndex.search("zzzz-no-such-app").isEmpty)
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

        // The search tracks whether arrow keys may page.
        harness.enter("Sample")
        harness.spin(0.2)
        XCTAssertFalse(pager.searchIsEmpty)
        harness.enter("")
        harness.spin(0.2)
        XCTAssertTrue(pager.searchIsEmpty)

        // A click on empty space or Esc dismisses.
        let before = closed
        harness.click(CGPoint(x: 12, y: 12))
        XCTAssertEqual(closed, before + 1, "clicking the backdrop dismisses")
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: harness.window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        harness.window.makeFirstResponder(harness.host)
        harness.window.sendEvent(escape)
        harness.spin()
        XCTAssertGreaterThanOrEqual(closed, before + 1)
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
        let pager = AppsPager()
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, pager: pager) {}, size: CGSize(width: 1000, height: 700))
        defer { harness.close() }
        harness.enter("nothing matches this")
        harness.spin(0.3)
        XCTAssertEqual(pager.count, 1)
    }

    private func scroll(dx: Int32, dy: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return NSEvent(cgEvent: event)!
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: code)!
    }

    func testArrowKeysPageOnlyWhileSearchIsEmpty() {
        let launcher = AppsLauncher.shared
        launcher.show(model: model(apps: 40))
        let pager = launcher.pager
        pager.count = 2
        launcher.panel?.keyDown(with: key(124))
        XCTAssertEqual(pager.page, 1)
        launcher.panel?.keyDown(with: key(123))
        XCTAssertEqual(pager.page, 0)
        launcher.panel?.keyDown(with: key(0)) // other keys pass through to AppKit
        XCTAssertEqual(pager.page, 0)
        pager.searchIsEmpty = false
        XCTAssertFalse(pager.handleKey(key(124)), "arrows edit the search text while it has text")
        pager.searchIsEmpty = true
    }

    func testPagerTurnsOncePerTrackpadGestureAndPerWheelNotch() {
        let pager = AppsPager()
        pager.count = 3
        // Trackpad: one swipe left turns forward once, however far it travels.
        pager.scroll(scroll(dx: 0, dy: 0, precise: true, phase: 1)) // began
        pager.scroll(scroll(dx: -40, dy: 0, precise: true, phase: 2))
        XCTAssertEqual(pager.page, 0, "below the threshold")
        pager.scroll(scroll(dx: -40, dy: 0, precise: true, phase: 2))
        XCTAssertEqual(pager.page, 1)
        pager.scroll(scroll(dx: -200, dy: 0, precise: true, phase: 2))
        XCTAssertEqual(pager.page, 1, "one turn per gesture")
        pager.scroll(scroll(dx: -200, dy: 0, precise: true, momentum: 2))
        XCTAssertEqual(pager.page, 1, "momentum never turns")
        pager.scroll(scroll(dx: 0, dy: 0, precise: true, phase: 1))
        pager.scroll(scroll(dx: 90, dy: 0, precise: true, phase: 2))
        XCTAssertEqual(pager.page, 0, "swiping right goes back")
        // Mouse wheel: each vertical notch turns a page.
        pager.scroll(scroll(dx: 0, dy: -3, precise: false))
        XCTAssertEqual(pager.page, 1)
        pager.scroll(scroll(dx: 0, dy: -3, precise: false))
        XCTAssertEqual(pager.page, 2)
        pager.scroll(scroll(dx: 0, dy: 3, precise: false))
        XCTAssertEqual(pager.page, 1)
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
}
