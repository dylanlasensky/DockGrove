import Foundation

@MainActor func runAppIndexTests() throws {
    let records = [
        AppSearchIndex.Record(path: "/Applications/Safari.app", name: "Safari", bundleIdentifier: "com.apple.Safari", modified: Date(timeIntervalSince1970: 1_700_000_000.25), aliases: ["browser", "web"]),
        AppSearchIndex.Record(path: "/Applications/Visual Studio Code.app", name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", modified: nil, aliases: ["vscode", "code"]),
        AppSearchIndex.Record(path: "/Applications/Xcode.app", name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", modified: nil),
        AppSearchIndex.Record(path: "/Applications/Xcode-beta.app", name: "Xcode Beta", bundleIdentifier: nil, modified: nil),
        AppSearchIndex.Record(path: "/Users/test/Applications/Creme.app", name: "Crème \"Studio\"", bundleIdentifier: "test.creme", modified: nil, aliases: ["a, b"], lookups: ["cr": 2]),
    ]
    let index = AppSearchIndex(records)
    precondition(index.app(atPath: "/applications/xcode.app")?.id == "/Applications/Xcode.app" && index.app(atPath: "/Applications/Missing.app") == nil)
    precondition(index.app(bundleIdentifier: "COM.APPLE.SAFARI")?.id == "/Applications/Safari.app")
    precondition(index.apps(named: " Browser ").map(\.id) == ["/Applications/Safari.app"])
    precondition(index.search("code").map(\.id) == ["/Applications/Visual Studio Code.app", "/Applications/Xcode.app", "/Applications/Xcode-beta.app"])
    precondition(index.search("xcode").map(\.id) == ["/Applications/Xcode.app", "/Applications/Xcode-beta.app"])
    precondition(index.search("creme").map(\.id) == ["/Users/test/Applications/Creme.app"])
    precondition(index.search("users").isEmpty && index.search("users", includePaths: true).count == 1)
    precondition(index.search("  ").count == records.count && index.search("zzz").isEmpty)

    // Opening an app from a search teaches that query, and the learned lookup outranks name matches.
    precondition(index.search("x").first?.id == "/Applications/Xcode.app")
    var learned = index
    for _ in 0..<2 { learned = learned.recordingLaunch(of: index.apps[3], query: " X ")! }
    precondition(learned.search("x").first?.id == "/Applications/Xcode-beta.app" && learned.records[3].lookups == ["x": 2])
    precondition(learned.search("vs").first?.id == "/Applications/Visual Studio Code.app")
    precondition(index.recordingLaunch(of: index.apps[0], query: "   ") == nil)
    precondition(index.recordingLaunch(of: DockApp(url: URL(fileURLWithPath: "/Nope.app")), query: "n") == nil)
    var crowded = index
    for n in 0..<(AppSearchIndex.maxLookupsPerApp + 5) { crowded = crowded.recordingLaunch(of: index.apps[0], query: "q\(n)")! }
    precondition(crowded.records[0].lookups.count == AppSearchIndex.maxLookupsPerApp)

    // The YAML round-trips names, locations, aliases, lookups and awkward characters.
    let yaml = AppIndexYAML.encode(learned.records)
    precondition(yaml.contains("path: \"/Applications/Xcode-beta.app\"") && yaml.contains("aliases: [\"browser\", \"web\"]"))
    precondition(AppIndexYAML.decode(yaml) == learned.records)
    let handwritten = """
    apps:
      - name: Notes
        path: /System/Applications/Notes.app
        aliases: [memo, "quick note"]
        lookups:
          nt: 3
          bad: zero
    """
    let parsed = AppIndexYAML.decode(handwritten)
    precondition(parsed.count == 1 && parsed[0].name == "Notes" && parsed[0].aliases == ["memo", "quick note"] && parsed[0].lookups == ["nt": 3])

    // The store persists the YAML and only adds seed aliases to newly found apps.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DockGroveIndex." + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let seed = root.appendingPathComponent("seed.yml")
    try Data("apps:\n  - name: \"Alpha\"\n    aliases: [\"first\"]\n".utf8).write(to: seed)
    let store = AppIndexStore(url: root.appendingPathComponent("AppIndex.yml"), seedURL: seed)
    precondition(store.load().isEmpty && store.seedAliases() == ["alpha": ["first"]])
    store.save(learned.records)
    precondition(store.load() == learned.records)
    store.saveLater(index.records); precondition(store.load() == index.records)

    let apps = root.appendingPathComponent("Apps")
    for name in ["Beta", "Alpha"] { try FileManager.default.createDirectory(at: apps.appendingPathComponent(name + ".app"), withIntermediateDirectories: true) }
    let first = Toolkit.applicationRecords([apps.path], seeds: store.seedAliases()).filter { $0.path.hasPrefix(apps.standardizedFileURL.path) }
    precondition(first.map(\.name) == ["Alpha", "Beta"] && first[0].aliases == ["first"] && first[1].aliases.isEmpty)
    var edited = first; edited[0].name = "Cached Alpha"; edited[0].aliases = ["mine"]; edited[0].lookups = ["al": 1]
    let second = Toolkit.applicationRecords([apps.path], cached: edited, seeds: store.seedAliases()).filter { $0.path.hasPrefix(apps.standardizedFileURL.path) }
    precondition(second.map(\.name) == ["Beta", "Cached Alpha"] && second[1].aliases == ["mine"] && second[1].lookups == ["al": 1])
    print("PASS: YAML app index lookups by path/bundle/name/alias, learned search ranking and cap, YAML round-trip and hand-edited files, seed aliases, incremental rescan")
}
