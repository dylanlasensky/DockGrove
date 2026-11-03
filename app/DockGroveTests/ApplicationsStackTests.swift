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

        // Each choice is a checkmark, persisted as stackSort / stackDisplay / stackView.
        XCTAssertEqual(harness.menuItem(["Sort by", "Name"], at: point)?.state, .on)
        harness.choose(["Sort by", "Date Modified"], inMenuAt: point)
        XCTAssertEqual(model.stackSort, .dateModified)
        XCTAssertEqual(model.defaults.string(forKey: "stackSort"), "Date Modified")
        XCTAssertEqual(harness.menuItem(["Sort by", "Date Modified"], at: point)?.state, .on)
        XCTAssertEqual(harness.menuItem(["Sort by", "Name"], at: point)?.state, .off)
        harness.choose(["View content as", "Grid"], inMenuAt: point)
        XCTAssertEqual(model.stackView, .grid)
        XCTAssertEqual(model.defaults.string(forKey: "stackView"), "Grid")
        XCTAssertEqual(harness.menuItem(["Display as", "Folder"], at: point)?.state, .on)
        harness.choose(["Display as", "Stack"], inMenuAt: point)
        XCTAssertEqual(model.stackDisplay, .stack)
        XCTAssertEqual(model.defaults.string(forKey: "stackDisplay"), "Stack")
        harness.spin(0.1)
        XCTAssertEqual(model.stackPreview(count: 3).count, 3, "Stack piles up the first apps")
        XCTAssertEqual(model.stackPreview(count: 3), model.stackPreview(count: 3), "cached")
        let reloaded = DockModel(defaults: model.defaults)
        XCTAssertEqual(reloaded.stackSort, .dateModified); XCTAssertEqual(reloaded.stackView, .grid); XCTAssertEqual(reloaded.stackDisplay, .stack)
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
        XCTAssertEqual(StackContentStyle.allCases.map(\.id), ["Fan", "Grid", "List", "Automatic"])
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
        XCTAssertTrue(first?.canBecomeKey ?? false, "the borderless launcher must take keyboard input")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first)
        XCTAssertNil(launcher.panel, "losing key status dismisses the launcher")
        launcher.toggle(model: model)
        let second = launcher.panel
        XCTAssertNotNil(second)
        second?.cancelOperation(nil)
        XCTAssertNil(launcher.panel, "Esc dismisses the launcher")
        let deadline = Date().addingTimeInterval(5) // the fade-out completion orders the panel out
        while second?.contentView != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
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

        // Backdrop clicks and Esc call `close` directly (onTapGesture/onExitCommand); the window's
        // Esc path is covered by testLauncherWindowOpensClosesOnResignAndEscape. Synthesized
        // clicks on the backdrop are not delivered reliably on every runner, so only send them.
        harness.click(CGPoint(x: 12, y: 12))
    }

    func testPlusAndReplaceOpenTheLauncherInTheirModes() {
        let model = model(apps: 2)
        let launcher = AppsLauncher.shared
        model.systemError = "stale"
        model.addApps()
        let first = launcher.panel
        XCTAssertNotNil(first, "+ opens the Applications launcher")
        XCTAssertNil(model.systemError)
        let sample = model.toolkit.appIndex.search("Sample 00")[0]
        model.showAppPicker(replacing: sample) // reopening while open swaps in a fresh panel
        XCTAssertNotNil(launcher.panel)
        XCTAssertFalse(launcher.panel === first)
        model.showAppLauncher(query: "Sample")
        XCTAssertFalse(launcher.pager.searchIsEmpty, "a widget query pre-fills the search")
        launcher.close()
        XCTAssertEqual(AppsLauncher.Mode.launch.title, nil)
        XCTAssertEqual(AppsLauncher.Mode.replace(sample).title, "Replace " + sample.name)
    }

    func testAddModePinsOnceAndCloses() {
        let model = model(apps: 3)
        let pager = AppsPager()
        var closed = 0
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, pager: pager, mode: .add) { closed += 1 }, size: CGSize(width: 1400, height: 900))
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
        // Return adds the top match; a vanished bundle reports the error inline and stays open.
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
        model.systemError = "Problem" // renders the inline error under the search field
        var closed = 0
        let harness = DockHarness(AppsLauncherView(model: model, kit: model.toolkit, pager: AppsPager(), mode: .replace(old)) { closed += 1 }, size: CGSize(width: 1400, height: 900))
        defer { harness.close() }
        harness.spin(0.4)
        XCTAssertTrue(harness.has("Replace " + old.name), "\(harness.labels())")
        harness.press("Sample 00") // already in the Dock: rejected, launcher stays open
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
