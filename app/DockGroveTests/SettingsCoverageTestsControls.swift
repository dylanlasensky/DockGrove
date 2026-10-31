import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

/// Drives the Studio's reusable controls and the Dock preview directly, outside the settings window.
@MainActor final class SettingsCoverageTestsControls: XCTestCase {
    private final class Box { var value: Double; var begins = 0; init(_ value: Double) { self.value = value } }
    private struct ChoiceHost: View {
        @State var selection: String
        let options: [StudioChoice]
        var body: some View { StudioChoiceControl(title: "Pick", selection: $selection, options: options) }
    }

    private func tempApp(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsCoverage." + UUID().uuidString)
        let app = folder.appendingPathComponent(name + ".app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return app
    }
    private func widget(_ kind: ToolKind) -> DockStudioItem { DockStudioItem(kind: .widget, value: kind.rawValue) }
    /// Controls other than text fields, which also carry key-view proxies.
    private func buttons(_ harness: SettingsHarness) -> (CGRect) -> Bool {
        { frame in !harness.textFields().contains { $0.convert($0.bounds, to: nil).intersects(frame) } }
    }

    func testNumberControlStepsDragsAndBounds() {
        XCTAssertEqual(StudioNumberControl.bounded(.nan, range: 0...1, step: 0.1), 0)
        XCTAssertEqual(StudioNumberControl.bounded(5, range: 0...1, step: 0.1), 1)
        XCTAssertEqual(StudioNumberControl.bounded(0.42, range: 0...1, step: 0.1), 0.4, accuracy: 0.0001)
        let box = Box(0.5)
        let plain = Box(10)
        let view = VStack {
            StudioNumberControl(title: "Width", value: Binding(get: { box.value }, set: { box.value = $0 }), range: 0...1, step: 0.1, scale: 100, unit: "%", onBegin: { box.begins += 1 })
            StudioNumberControl(title: "Size", value: Binding(get: { plain.value }, set: { plain.value = $0 }), range: 0...20, step: 2, unit: "pt")
        }.padding()
        let harness = SettingsHarness(view, width: 420, height: 200)
        defer { harness.close() }
        let controls = harness.controls()
        XCTAssertEqual(controls.count, 4)
        harness.click(controls[0])
        XCTAssertEqual(box.value, 0.4, accuracy: 0.0001)
        harness.click(controls[1])
        XCTAssertEqual(box.value, 0.5, accuracy: 0.0001)
        XCTAssertEqual(box.begins, 2)
        harness.click(controls[2]); harness.click(controls[3])
        XCTAssertEqual(plain.value, 10)
        let badge = CGPoint(x: (controls[0].maxX + controls[1].minX) / 2, y: controls[0].midY)
        harness.drag(from: badge, to: CGPoint(x: badge.x + 40, y: badge.y), steps: 6)
        XCTAssertEqual(box.value, 1, accuracy: 0.0001)
        XCTAssertEqual(box.begins, 3)
    }

    func testChoiceControlExpandsSearchesSelectsAndCollapses() {
        let many = (0..<8).map { StudioChoice(value: "v\($0)", title: "Choice \($0)") }
        XCTAssertEqual(many[0].icon, "circle.grid.2x2")
        XCTAssertEqual(many[0].id, "v0")
        let harness = SettingsHarness(ChoiceHost(selection: "unknown", options: many).padding(), width: 640, height: 500)
        defer { harness.close() }
        harness.click(harness.controls()[0])
        XCTAssertEqual(harness.textFields().count, 1)
        harness.type("zzz", into: harness.textFields()[0])
        harness.type("Choice", into: harness.textFields()[0])
        harness.type("", into: harness.textFields()[0])
        harness.clickAll(from: 1, filter: buttons(harness)) // every option, then Collapse
        harness.settle(0.4)
        XCTAssertTrue(harness.textFields().isEmpty)
        harness.click(harness.controls()[0])
        harness.settle(0.4)
        harness.click(harness.controls()[0])
        harness.settle(0.4)
        XCTAssertTrue(harness.textFields().isEmpty)

        let few = [StudioChoice(value: "a", title: "Alpha", icon: "star"), StudioChoice(value: "b", title: "Beta")]
        let small = SettingsHarness(ChoiceHost(selection: "a", options: few).padding(), width: 640, height: 300)
        defer { small.close() }
        small.click(small.controls()[0])
        small.clickAll(from: 1, filter: buttons(small))
    }

    func testToolbarSizePresetsResetAndFit() {
        let model = makeSettingsModel(self)
        let harness = SettingsHarness(StudioToolbarSize(model: model).padding(), width: 760, height: 600)
        defer { harness.close() }
        harness.clickAll()
        XCTAssertFalse(model.studioHistory.isEmpty)
        XCTAssertEqual(model.widthFraction, 1)
    }

    func testAppearanceEveryControl() {
        let model = makeSettingsModel(self)
        model.isAdditionalDock = true
        let harness = SettingsHarness(StudioAppearance(model: model).padding(), width: 900, height: 3200)
        defer { harness.close() }
        let wells = { harness.views(NSColorWell.self).map { $0.convert($0.bounds, to: nil) } }
        // Color wells open the shared color panel; set them directly instead.
        harness.clickAll { frame in !wells().contains { $0.intersects(frame) } }
        XCTAssertTrue(["Automatic", "Glass", "Graphite", "Pearl"].contains(model.theme))
        // Filtering color groups shifts later controls, so click the toggles (16 pt rows) again.
        let rich = model.toolkit.richWidgets
        harness.clickAll { $0.height <= 16 }
        XCTAssertNotEqual(model.toolkit.richWidgets, rich)
        harness.select(2, in: harness.segments().last!)
        XCTAssertEqual(model.toolkit.edge, "Floating")
        harness.select(0, in: harness.segments().last!)
        XCTAssertEqual(model.toolkit.edge, "Bottom")
    }

    func testWidgetShapesSelectAWidgetAndShape() {
        let model = makeSettingsModel(self)
        let harness = SettingsHarness(StudioWidgetShapes(model: model).padding(), width: 900, height: 900)
        defer { harness.close() }
        harness.click(harness.controls()[0])
        harness.settle(0.3)
        harness.type("Weather", into: harness.textFields()[0])
        harness.settle(0.4) // let the filtered list re-layout before reading control frames
        harness.click(harness.controls().filter(buttons(harness))[1]) // the only match, Weather
        harness.settle(0.3)
        harness.click(harness.controls()[0]) // collapse
        harness.settle(0.4)
        harness.clickAll(from: 1)
        XCTAssertNotEqual(model.toolkit.shape(for: .weather), .rounded)
    }

    func testColorPacksGroupsColorsAndPacks() {
        let model = makeSettingsModel(self)
        model.accent = "not-a-pack-color"
        let harness = SettingsHarness(StudioColorPacks(model: model).padding(), width: 900, height: 1600)
        defer { harness.close() }
        let wells = { harness.views(NSColorWell.self).map { $0.convert($0.bounds, to: nil) } }
        harness.clickAll { frame in !wells().contains { $0.intersects(frame) } }
        XCTAssertTrue(AccentPalette.packs.contains { $0.colors.contains(model.accent) })
        if let well = harness.views(NSColorWell.self).first {
            well.color = .systemRed
            if let action = well.action { NSApp.sendAction(action, to: well.target, from: well) }
            harness.settle()
        }
    }

    func testBehaviorTogglesAndAccountSettings() {
        var log: [String] = []
        let model = makeSettingsModel(self)
        model.isAdditionalDock = true
        model.systemError = "Activate DockGrove first."
        model.visibilityAction = { log.append("visibility") }
        model.settingsAction = { log.append("settings") }
        model.changeDockAction = { log.append("dock:\($0)") }
        let full = SettingsHarness(StudioBehavior(model: model).environment(\.studioAccess, .fixed(tier: .full)).padding(), width: 900, height: 2400)
        // Only DockGrove's own toggles (top panel) and Account settings (last panel); the
        // workspace and snapping controls belong to other screens.
        for index in 0..<3 { full.click(full.controls()[index]) }
        XCTAssertTrue(model.showClock)
        XCTAssertTrue(model.showUsageCard)
        XCTAssertEqual(log, ["visibility"])
        full.click(full.controls().last!)
        XCTAssertTrue(model.codexConnectionSelected)
        XCTAssertEqual(log.last, "settings")
        full.close()

        model.isAdditionalDock = false
        let main = SettingsHarness(StudioBehavior(model: model).environment(\.studioAccess, .fixed(tier: .free)).padding(), width: 900, height: 2400)
        defer { main.close() }
        // Without AI access the usage toggle is disabled and has no proxy: clock, Dock, Show.
        main.click(main.controls()[1])
        XCTAssertEqual(log.last, "dock:true")
    }

    func testEntryPreviewsForEveryEntry() throws {
        let model = makeSettingsModel(self)
        let app = try tempApp("Alpha")
        let kinds = ToolKind.allCases
        let entries: [DockEntry] = [.app(DockApp(url: app)), .add, .usage, .clock] + kinds.map { .tool($0) }
        model.setWidgetShape(.circle, for: .weather)
        let grid = { VStack(spacing: 2) { ForEach(entries.indices, id: \.self) { StudioEntryPreview(entry: entries[$0], model: model) } } }
        let rich = SettingsHarness(grid(), width: 400, height: 1200)
        rich.close()
        model.toolkit.richWidgets = false
        let simple = SettingsHarness(grid(), width: 400, height: 1200)
        simple.close()
        XCTAssertEqual(entries.count, kinds.count + 4)
    }

    func testDockPreviewPagesUndoMenusAndDrops() throws {
        let model = makeSettingsModel(self)
        let app = try tempApp("Alpha")
        model.fitToolbarToContent = false
        model.widthFraction = 0.35
        for kind in [ToolKind.focus, .notes, .weather, .calculator, .tasks, .clipboard] { XCTAssertTrue(model.placeStudioItem(widget(kind))) }
        XCTAssertTrue(model.placeStudioItem(DockStudioItem(kind: .app, value: app.standardizedFileURL.path)))
        XCTAssertTrue(model.placeStudioItem(DockStudioItem(kind: .clock, value: "clock")))
        let harness = SettingsHarness(DockStudioPreview(model: model).padding(), width: 700, height: 400)
        defer { harness.close() }
        // A disabled chevron has no proxy: Previous appears once past the first page.
        let chevron = { (height: CGFloat) in harness.controls().first { abs($0.height - height) < 1 } }
        guard let next = chevron(40) else { return XCTFail("\(harness.controls())") }
        harness.click(next)
        guard let previous = chevron(64) else { return XCTFail("\(harness.controls())") }
        harness.click(previous)

        // Context menu on the first tile (a widget, so it offers shapes).
        let before = model.studioEntries.count
        harness.performAllMenuItems(at: CGPoint(x: previous.maxX + 30, y: previous.midY))
        XCTAssertLessThan(model.studioEntries.count, before, "The last menu item removes the tile")

        for _ in 0..<8 { if let next = chevron(40) { harness.click(next) } }
        if let previous = chevron(64) { harness.click(previous) }
        for _ in 0..<8 { if let next = chevron(40) { harness.click(next) } }
        // Fewer tiles: fewer pages, so the current page is clamped.
        model.toolkit.enabled = ["focus"]; model.apps = []; model.showClock = false
        harness.settle(0.1)
        model.studioHistory = []
        model.rememberStudioLayout()
        model.toolkit.enabled = []
        harness.settle()
        let undo = harness.controls().max { $0.maxY < $1.maxY }!
        harness.click(undo)
        XCTAssertTrue(model.studioHistory.isEmpty)
        XCTAssertEqual(model.toolkit.enabled, ["focus"])
        XCTAssertTrue(model.placeStudioItem(widget(.notes)))
        XCTAssertTrue(model.placeStudioItem(widget(.weather)))

        let tile = StudioDraggableTile(entry: .tool(.notes), nextID: "weather", model: model)
        XCTAssertFalse(tile.drop([], at: 0))
        XCTAssertTrue(tile.drop([widget(.focus)], at: 0))
        XCTAssertEqual(model.studioEntries.map(\.id).firstIndex(of: "focus"), model.studioEntries.map(\.id).firstIndex(of: "notes").map { $0 - 1 })
        XCTAssertTrue(tile.drop([widget(.focus)], at: 1000))
    }
}
