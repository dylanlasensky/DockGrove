import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

@MainActor final class SettingsCoverageTests: XCTestCase {
    private lazy var store = SettingsFakePurchaseStore()
    private var log: [String] = []

    private func settings(_ model: DockModel, _ section: StudioSection, access: StudioAccess = .fixed(tier: .full), height: CGFloat = 3000) -> SettingsHarness {
        model.closeSettingsAction = { [unowned self] in self.log.append("close") }
        model.manageDocksAction = { [unowned self] in self.log.append("manage") }
        model.changeDockAction = { [unowned self] in self.log.append("dock:\($0)") }
        model.visibilityAction = { [unowned self] in self.log.append("visibility") }
        model.settingsAction = { [unowned self] in self.log.append("settings") }
        let view = SettingsView(model: model, section: section, purchases: store, terminate: { [unowned self] _ in self.log.append("quit") })
            .environment(\.studioAccess, access)
        return SettingsHarness(view, width: 1080, height: height)
    }
    private func tempApp(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsCoverage." + UUID().uuidString)
        let app = folder.appendingPathComponent(name + ".app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return app
    }

    func testSectionMetadata() {
        XCTAssertEqual(StudioSection.allCases.map(\.icon).count, 5)
        XCTAssertEqual(Set(StudioSection.allCases.map(\.subtitle)).count, 5)
    }

    func testSidebarActionsAndSectionSwitching() {
        let model = makeSettingsModel(self)
        let harness = settings(model, .connections, height: 1000)
        defer { harness.close() }
        // Link-style buttons have no key-view proxy; sweep the bottom of the sidebar.
        harness.scan(x: 60, from: 20, to: 200, step: 4)
        XCTAssertTrue(log.contains("manage") && log.contains("dock:false") && log.contains("quit"), "\(log)")
        let done = harness.controls().filter { $0.minX > 900 }.first!
        harness.click(done)
        XCTAssertEqual(log.last, "close")
        for frame in harness.controls().filter({ $0.maxX < 200 }).prefix(5) { harness.click(frame) }
        model.codexConnectionSelected = true
        harness.settle()
        model.connectionSettingsKind = .calendar
        harness.settle()
    }

    func testLockedAndUnlicensedFallbacks() {
        let model = makeSettingsModel(self)
        model.isAdditionalDock = true
        for section in StudioSection.allCases {
            let harness = settings(model, section, access: .fixed(features: false, tier: .free, purchases: false), height: 900)
            harness.close()
        }
        let harness = settings(model, .library, access: .fixed(tier: .free, purchases: true), height: 900)
        store.tier = .plus
        harness.settle()
        harness.close()
    }

    /// The six category chips: the only row of six short controls.
    private func chips(_ harness: SettingsHarness) -> [CGRect] {
        let short = harness.controls().filter { $0.minX > 200 && $0.height < 40 }
        let rows = Dictionary(grouping: short) { Int($0.maxY) }
        return rows.values.first { $0.count == 6 }?.sorted { $0.minX < $1.minX } ?? []
    }

    func testLibraryWidgetsSearchCategoriesAndCards() {
        let model = makeSettingsModel(self)
        let harness = settings(model, .library)
        defer { harness.close() }
        let row = chips(harness)
        XCTAssertEqual(row.count, 6)
        for chip in row.reversed() { harness.click(chip) } // ends on All
        harness.type("zzzz-nothing", into: harness.textFields()[0])
        XCTAssertNil(harness.source("focus"))
        harness.type("focus", into: harness.textFields()[0])
        harness.source("focus")?.clicked?()
        XCTAssertTrue(model.toolkit.enabled.contains("focus"), "\(model.toolkit.enabled)")
        harness.settle()
        harness.source("focus")?.clicked?()
        XCTAssertFalse(model.toolkit.enabled.contains("focus"))
        harness.type("", into: harness.textFields()[0])
        model.setWidgetShape(.circle, for: .focus)
        harness.settle()
    }

    func testLockedWidgetCardOpensPurchases() {
        let model = makeSettingsModel(self)
        let harness = settings(model, .library, access: .fixed(tier: .free))
        defer { harness.close() }
        harness.type("Weather", into: harness.textFields()[0])
        XCTAssertNil(harness.source("weather"), "Locked cards cannot be dragged")
        let card = harness.controls().filter { $0.minX > 200 && $0.height > 80 }.min { $0.maxY < $1.maxY }!
        harness.click(CGPoint(x: card.midX, y: card.minY + 18))
        harness.settle(0.1)
        XCTAssertEqual(store.calls.first, "load", "A locked card opens Purchases")
    }

    func testLibraryAppsTogglePinning() throws {
        let model = makeSettingsModel(self)
        let first = try tempApp("Alpha"), second = try tempApp("Beta")
        model.toolkit.applicationRoots = [first.deletingLastPathComponent().path]
        model.toolkit.applications = [DockApp(url: first), DockApp(url: second)]
        let harness = settings(model, .library)
        defer { harness.close() }
        harness.select(1, in: harness.segments()[0])
        harness.settle()
        let sources = harness.views(NativeStudioDragSource.SourceView.self)
        XCTAssertEqual(sources.count, 2)
        sources[0].clicked?()
        XCTAssertEqual(model.apps.map(\.id), [first.standardizedFileURL.path])
        harness.settle()
        harness.views(NativeStudioDragSource.SourceView.self)[0].clicked?()
        XCTAssertTrue(model.apps.isEmpty)
        harness.type("Beta", into: harness.textFields()[0])
        harness.type("nothing-matches", into: harness.textFields()[0])
        // Refresh scans only the temporary application root.
        let refresh = harness.controls().filter { $0.minX > 200 && $0.width < 40 }.first { $0.maxY > 2000 }
        if let refresh { harness.click(refresh) }
        harness.settle(0.3)
        harness.select(0, in: harness.segments()[0])
    }

    func testAppearanceControls() {
        let model = makeSettingsModel(self)
        model.isAdditionalDock = true
        model.accent = "not-a-pack-color"
        let harness = settings(model, .appearance, height: 3400)
        defer { harness.close() }
        let content = { (rect: CGRect) in rect.minX > 200 }
        harness.clickAll { content($0) && $0.maxY < 2900 }
        harness.type("Studio Dock", into: harness.textFields().first { $0.placeholderString == "Dock name" }!)
        XCTAssertEqual(model.dockName, "Studio Dock")
        let edge = harness.segments().last!
        harness.select(2, in: edge)
        XCTAssertEqual(model.toolkit.edge, "Floating")
        harness.settle()
        if let well = harness.views(NSColorWell.self).first {
            well.color = .systemRed
            if let action = well.action { NSApp.sendAction(action, to: well.target, from: well) }
            harness.settle()
        }
        harness.clickAll { content($0) && $0.maxY < 2900 }
    }

    func testAppearanceWithNotchRenders() {
        let model = makeSettingsModel(self)
        let harness = settings(model, .appearance, height: 3400)
        harness.close()
    }

    func testBehaviorRendersInSettings() {
        let model = makeSettingsModel(self)
        model.isAdditionalDock = true
        model.systemError = "Activate DockGrove first."
        let harness = settings(model, .behavior, height: 3000)
        defer { harness.close() }
        // Behavior's controls are driven directly in SettingsCoverageTestsControls; here it renders
        // inside the settings window.
        XCTAssertFalse(harness.controls().isEmpty)
    }
}
