import Foundation

/// Installed-application catalog backed by `AppIndex.yml`. Each app carries its name, location,
/// alternative names, and lookups learned from the searches that led to it. Lookups resolve
/// through hash maps built once per catalog change, so exact names, aliases and learned queries
/// are found without scanning.
struct AppSearchIndex {
    struct Record: Equatable {
        var path: String
        var name: String
        var bundleIdentifier: String?
        var modified: Date?
        var aliases: [String] = []
        /// Folded query → number of launches that followed it.
        var lookups: [String: Int] = [:]
    }

    static let maxLookupsPerApp = 40
    static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    let records: [Record]
    let apps: [DockApp]
    private let foldedNames: [String]
    private let foldedPaths: [String]
    private let foldedAliases: [[String]]
    private var byPath: [String: Int] = [:]
    private var byBundle: [String: Int] = [:]
    private var byTerm: [String: [Int]] = [:]
    private var learned: [String: [(index: Int, count: Int)]] = [:]

    init(_ records: [Record] = []) {
        self.records = records
        apps = records.map { DockApp(url: URL(fileURLWithPath: $0.path)) }
        foldedNames = records.map { Self.fold($0.name) }
        foldedPaths = records.map { Self.fold($0.path) }
        foldedAliases = records.map { $0.aliases.map(Self.fold).filter { !$0.isEmpty } }
        for (index, record) in records.enumerated() {
            byPath[foldedPaths[index]] = index
            if let bundle = record.bundleIdentifier { byBundle[Self.fold(bundle)] = index }
            for term in Set([foldedNames[index]] + foldedAliases[index]) { byTerm[term, default: []].append(index) }
            for (query, count) in record.lookups where count > 0 { learned[Self.fold(query), default: []].append((index, count)) }
        }
        for key in learned.keys { learned[key]?.sort { $0.count > $1.count } }
    }

    var count: Int { records.count }
    func name(of app: DockApp) -> String { record(atPath: app.id)?.name ?? app.name }
    func record(atPath path: String) -> Record? { byPath[Self.fold(path)].map { records[$0] } }
    func app(atPath path: String) -> DockApp? { byPath[Self.fold(path)].map { apps[$0] } }
    func app(bundleIdentifier: String) -> DockApp? { byBundle[Self.fold(bundleIdentifier)].map { apps[$0] } }
    /// Apps whose name or any alias equals `term`.
    func apps(named term: String) -> [DockApp] { (byTerm[Self.fold(term)] ?? []).map { apps[$0] } }

    /// Learned lookups for this exact query first (most launched first), then exact names and aliases,
    /// then name or alias prefixes, then any other name, alias or optional path match in catalog order.
    func search(_ query: String, includePaths: Bool = false) -> [DockApp] {
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return apps }
        var seen = Set<Int>(), ordered: [Int] = []
        func take(_ index: Int) { if seen.insert(index).inserted { ordered.append(index) } }
        (learned[folded] ?? []).forEach { take($0.index) }
        (byTerm[folded] ?? []).forEach(take)
        var others: [Int] = []
        for index in records.indices where !seen.contains(index) {
            let terms = [foldedNames[index]] + foldedAliases[index]
            if terms.contains(where: { $0.hasPrefix(folded) }) { take(index) }
            else if terms.contains(where: { $0.contains(folded) }) || (includePaths && foldedPaths[index].contains(folded)) { others.append(index) }
        }
        others.forEach(take)
        return ordered.map { apps[$0] }
    }

    /// The catalog after `app` was opened from a search for `query`, or nil when nothing should be learned.
    func recordingLaunch(of app: DockApp, query: String) -> AppSearchIndex? {
        let folded = String(Self.fold(query).prefix(40))
        guard !folded.isEmpty, let index = byPath[Self.fold(app.id)] else { return nil }
        var updated = records
        updated[index].lookups[folded, default: 0] += 1
        if updated[index].lookups.count > Self.maxLookupsPerApp,
           let weakest = updated[index].lookups.filter({ $0.key != folded }).min(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key {
            updated[index].lookups.removeValue(forKey: weakest)
        }
        return AppSearchIndex(updated)
    }
}

/// Reads and writes the small YAML subset used by `AppIndex.yml` and the bundled `AppAliases.yml`.
enum AppIndexYAML {
    static func encode(_ records: [AppSearchIndex.Record]) -> String {
        var lines = ["# DockGrove application index.",
                     "# Add alternative names under aliases; lookups are learned from the searches you open apps with.",
                     "version: 1", "apps:"]
        for record in records {
            lines.append("  - name: " + quote(record.name))
            lines.append("    path: " + quote(record.path))
            if let bundle = record.bundleIdentifier { lines.append("    bundle: " + quote(bundle)) }
            if let modified = record.modified { lines.append("    modified: \(modified.timeIntervalSince1970)") }
            lines.append("    aliases: [" + record.aliases.map(quote).joined(separator: ", ") + "]")
            if record.lookups.isEmpty { lines.append("    lookups: {}") }
            else {
                lines.append("    lookups:")
                for (query, count) in record.lookups.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }) {
                    lines.append("      " + quote(query) + ": \(count)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Entries without a path are kept so alias seeds can be matched by bundle identifier or name.
    static func decode(_ text: String) -> [AppSearchIndex.Record] {
        var records: [AppSearchIndex.Record] = []
        var current: AppSearchIndex.Record?
        var inLookups = false
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = raw.prefix { $0 == " " }.count
            var body = trimmed
            if trimmed.hasPrefix("- ") {
                if let current { records.append(current) }
                current = AppSearchIndex.Record(path: "", name: "", bundleIdentifier: nil, modified: nil)
                inLookups = false
                body = String(trimmed.dropFirst(2))
            } else if current == nil || indent < 4 {
                continue
            }
            guard let (key, value) = pair(body) else { continue }
            if inLookups && indent >= 6 && !trimmed.hasPrefix("- ") {
                if let count = Int(value), count > 0 { current?.lookups[AppSearchIndex.fold(key)] = count }
                continue
            }
            inLookups = false
            switch key {
            case "name": current?.name = scalar(value)
            case "path": current?.path = scalar(value)
            case "bundle": current?.bundleIdentifier = scalar(value)
            case "modified": current?.modified = Double(value).map(Date.init(timeIntervalSince1970:))
            case "aliases": current?.aliases = list(value)
            case "lookups": inLookups = value.isEmpty
            default: break
            }
        }
        if let current { records.append(current) }
        return records
    }

    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    /// Splits `key: value`, where the key may be quoted.
    private static func pair(_ text: String) -> (String, String)? {
        if text.hasPrefix("\"") {
            guard let (key, rest) = quoted(text), rest.hasPrefix(":") else { return nil }
            return (key, rest.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        guard let colon = text.firstIndex(of: ":") else { return nil }
        return (String(text[..<colon]).trimmingCharacters(in: .whitespaces), text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }
    /// Reads one double-quoted string from the start of `text`, returning it and the remainder.
    private static func quoted(_ text: String) -> (String, Substring)? {
        var result = "", escaped = false, index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            if escaped { result.append(character == "n" ? "\n" : character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { return (result, text[text.index(after: index)...]) }
            else { result.append(character) }
            index = text.index(after: index)
        }
        return nil
    }
    private static func scalar(_ value: String) -> String {
        value.hasPrefix("\"") ? quoted(value)?.0 ?? "" : value
    }
    private static func list(_ value: String) -> [String] {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value.isEmpty ? [] : [scalar(value)] }
        var items: [String] = []
        let separator: (Character) -> Bool = { $0 == " " || $0 == "," }
        var rest = Substring(value.dropFirst().dropLast()).drop(while: separator)
        while !rest.isEmpty {
            if rest.hasPrefix("\""), let (item, remainder) = quoted(String(rest)) { items.append(item); rest = remainder }
            else {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                items.append(rest[..<end].trimmingCharacters(in: .whitespaces)); rest = rest[end...]
            }
            rest = rest.drop(while: separator)
        }
        return items
    }
}

/// Owns `AppIndex.yml` in Application Support. Writes go through one serial queue so learned
/// lookups saved in quick succession land in order.
final class AppIndexStore: @unchecked Sendable {
    /// Tests keep the catalog in memory so they never write to the real Application Support folder.
    static let shared = AppIndexStore(url: TestEnvironment.isXCTest ? nil : BrandStorage.supportDirectory.appendingPathComponent("AppIndex.yml"))
    private let url: URL?
    private let seedURL: URL?
    private let queue = DispatchQueue(label: "DockGrove.AppIndexStore")
    private var memory = ""

    /// Pass `nil` to keep the file in memory, for tests.
    init(url: URL?, seedURL: URL? = Bundle.main.url(forResource: "AppAliases", withExtension: "yml")) {
        self.url = url; self.seedURL = seedURL
    }

    func load() -> [AppSearchIndex.Record] {
        queue.sync {
            let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? memory
            return AppIndexYAML.decode(text).filter { !$0.path.isEmpty && !$0.name.isEmpty }
        }
    }

    func save(_ records: [AppSearchIndex.Record]) { queue.sync { write(records) } }
    func saveLater(_ records: [AppSearchIndex.Record]) { queue.async { self.write(records) } }

    /// Starter aliases from the bundled seed, keyed by folded bundle identifier and folded name.
    func seedAliases() -> [String: [String]] {
        guard let seedURL, let text = try? String(contentsOf: seedURL, encoding: .utf8) else { return [:] }
        var aliases: [String: [String]] = [:]
        for record in AppIndexYAML.decode(text) where !record.aliases.isEmpty {
            if let bundle = record.bundleIdentifier { aliases[AppSearchIndex.fold(bundle)] = record.aliases }
            if !record.name.isEmpty { aliases[AppSearchIndex.fold(record.name)] = record.aliases }
        }
        return aliases
    }

    private func write(_ records: [AppSearchIndex.Record]) {
        let text = AppIndexYAML.encode(records)
        guard let url else { memory = text; return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
}
