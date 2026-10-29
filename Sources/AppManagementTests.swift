import AppKit

@MainActor func runAppManagementTests() throws {
    let suite = "WaveDockApps." + UUID().uuidString
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let apps = try ["Alpha", "Beta", "Gamma"].map { name -> DockApp in
        let url = folder.appendingPathComponent(name + ".app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DockApp(url: url)
    }
    let model = DockModel(defaults: store)
    precondition(model.theme == "Automatic" && model.scheme == nil)
    model.apps = [apps[0], apps[1]]
    model.toolkit.enabled = ["pet"]
    model.entryOrder = ["usage", "app:" + apps[1].id, "pet", "app:" + apps[0].id, "clock"]
    let original = model.entryOrder
    precondition(!model.chooseApp(apps[0], replacing: apps[1]))
    precondition(model.apps == [apps[0], apps[1]] && model.entryOrder == original)
    precondition(model.chooseApp(apps[2], replacing: apps[1]))
    precondition(model.entryOrder[1] == "app:" + apps[2].id && model.entryOrder[2] == "pet")
    let restored = DockModel(defaults: store)
    precondition(restored.apps == [apps[0], apps[2]] && restored.entryOrder == model.entryOrder)
    model.undoAppChange(); precondition(model.apps == [apps[0], apps[1]] && model.entryOrder == original)
    model.remove(apps[1]); precondition(!model.entryOrder.contains("app:" + apps[1].id))
    model.undoAppChange(); precondition(model.entryOrder == original)
    try FileManager.default.removeItem(at: apps[2].url)
    precondition(!model.chooseApp(apps[2], replacing: apps[0]))
    // Exercise a replacement on a later page with widgets interleaved.
    let many = try (0..<20).map { index -> DockApp in
        let url = folder.appendingPathComponent("Installed-\(index).app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DockApp(url: url)
    }
    model.apps = Array(many.prefix(19))
    model.entryOrder = model.apps.map { "app:" + $0.id }
    model.entryOrder.insert("pet", at: 10)
    let entries = model.orderedEntries
    let pages = DockPageLayout.pages(widths: entries.map { $0.width(iconSize: 48) }, available: 420)
    let targetID = "app:" + many[16].id
    precondition(pages.count > 1 && !pages[0].contains(where: { entries[$0].id == targetID }))
    let before = entries.map(\.id)
    precondition(model.chooseApp(many[19], replacing: many[16]))
    precondition(model.orderedEntries.map(\.id) == before.map { $0 == targetID ? "app:" + many[19].id : $0 })
    model.undoAppChange()
    precondition(model.orderedEntries.map(\.id) == before)
    precondition(model.chooseApp(many[19], replacing: nil))
    precondition(model.apps.last == many[19])
    model.undoAppChange()
    precondition(model.orderedEntries.map(\.id) == before)
    model.theme = "Pearl"
    precondition(DockModel(defaults: store).scheme == .light)
    print("PASS: app add/replace preserves later-page mixed order, rejects duplicate/missing apps, restart persistence, undo, automatic and explicit appearance")
}
