import Foundation
import SwiftUI
import AppKit

enum LocalAIProvider: String { case claude, gemini
    var title: String { self == .claude ? "Claude Code" : "Gemini CLI" }
    var documentation: URL { URL(string: self == .claude ? "https://code.claude.com/docs/en/statusline" : "https://geminicli.com/docs/cli/headless/")! }
}
struct LocalAIWindow: Codable { let name: String; let used: Double; let resets: Date }
struct LocalAIModel: Codable, Identifiable {
    var id: String { name }; let name: String; let total: Int64; let input: Int64; let output: Int64; let cached: Int64; let requests: Int64
}
struct LocalAIReport: Codable {
    let provider: String; let observed: Date; let windows: [LocalAIWindow]; let models: [LocalAIModel]; let sessionCost: Double?
    var totalTokens: Int64 { models.reduce(0) { $0 + $1.total } }
    func activeWindows(at now: Date) -> [LocalAIWindow] { windows.filter { $0.resets > now } }
    func stale(at now: Date) -> Bool { now.timeIntervalSince(observed) > 1800 }
}
enum LocalAIError: Error, LocalizedError {
    case invalid, tooLarge, existingStatusLine, changedSettings, missing
    var errorDescription: String? { switch self {
    case .invalid: return "This is not a supported usage report. No new data was saved."
    case .tooLarge: return "This report is too large. The maximum is 20 MB."
    case .existingStatusLine: return "Claude Code already has a custom status line. It has been preserved. Use the setup guide to integrate DockGrove’s capture command."
    case .changedSettings: return "The status line changed outside DockGrove. It was preserved; remove the DockGrove command manually if needed."
    case .missing: return "No local report yet. Connect a status line or import a report to begin."
    } }
}
enum LocalAIStore {
    static let maxBytes = 20_000_000
    static var folder: URL { BrandStorage.supportDirectory.appendingPathComponent("AI Usage") }
    static func url(_ provider: LocalAIProvider, directory: URL = folder) -> URL { directory.appendingPathComponent(provider.rawValue + ".json") }
    static func number(_ value: Any?) throws -> Double {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= 0 else { throw LocalAIError.invalid }; return n.doubleValue
    }
    static func integer(_ value: Any?) throws -> Int64 {
        let n = try number(value); guard n < Double(Int64.max), n.rounded(.down) == n else { throw LocalAIError.invalid }; return Int64(n)
    }
    static func decode(_ data: Data, provider: LocalAIProvider, now: Date = Date()) throws -> LocalAIReport {
        guard data.count <= maxBytes else { throw LocalAIError.tooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LocalAIError.invalid }
        if provider == .claude {
            // Recognize the official status-line envelope; do not save any other fields.
            guard root["model"] is [String: Any], root["context_window"] is [String: Any] else { throw LocalAIError.invalid }
            var windows: [LocalAIWindow] = []
            if let raw = root["rate_limits"] {
                guard let rates = raw as? [String: Any] else { throw LocalAIError.invalid }
                for (key, title) in [("five_hour", "5-hour window"), ("seven_day", "Weekly window"), ("spend_limit", "Gateway spend limit")] {
                    guard let value = rates[key], !(value is NSNull) else { continue }
                    guard let row = value as? [String: Any] else { throw LocalAIError.invalid }
                    let used = try number(row["used_percentage"]), reset = try number(row["resets_at"])
                    guard used <= 100, reset < 253402300800 else { throw LocalAIError.invalid }
                    let date = Date(timeIntervalSince1970: reset)
                    if date > now { windows.append(LocalAIWindow(name: title, used: used, resets: date)) }
                }
            }
            var cost: Double?
            if let row = root["cost"] as? [String: Any], let value = row["total_cost_usd"] { cost = try number(value) }
            return LocalAIReport(provider: provider.rawValue, observed: now, windows: windows, models: [], sessionCost: cost)
        }
        guard let stats = root["stats"] as? [String: Any], let models = stats["models"] as? [String: Any], !models.isEmpty, models.count <= 100 else { throw LocalAIError.invalid }
        var rows: [LocalAIModel] = [], combined: Int64 = 0
        for (name, raw) in models.sorted(by: { $0.key < $1.key }) {
            guard !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), let model = raw as? [String: Any], let tokens = model["tokens"] as? [String: Any], let api = model["api"] as? [String: Any] else { throw LocalAIError.invalid }
            let total = try integer(tokens["total"]), prompt = try integer(tokens["prompt"]), output = try integer(tokens["candidates"]), cached = try integer(tokens["cached"]), requests = try integer(api["totalRequests"])
            guard cached <= prompt else { throw LocalAIError.invalid }
            let (sum, overflow) = combined.addingReportingOverflow(total); guard !overflow else { throw LocalAIError.invalid }; combined = sum
            // prompt includes cached input. Never sum overlapping categories into total.
            rows.append(LocalAIModel(name: name, total: total, input: prompt - cached, output: output, cached: cached, requests: requests))
        }
        return LocalAIReport(provider: provider.rawValue, observed: now, windows: [], models: rows, sessionCost: nil)
    }
    static func save(_ report: LocalAIReport, provider: LocalAIProvider, directory: URL = folder) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = url(provider, directory: directory)
        try JSONEncoder().encode(report).write(to: target, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    static func load(_ provider: LocalAIProvider, directory: URL = folder) throws -> LocalAIReport {
        let target = url(provider, directory: directory)
        guard FileManager.default.fileExists(atPath: target.path) else { throw LocalAIError.missing }
        let data = try boundedFile(target)
        let report = try JSONDecoder().decode(LocalAIReport.self, from: data)
        guard report.provider == provider.rawValue, report.observed.timeIntervalSince1970.isFinite,
              report.observed <= Date().addingTimeInterval(300), report.windows.count <= 3, report.models.count <= 100 else { throw LocalAIError.invalid }
        var total: Int64 = 0
        for row in report.models {
            guard row.total >= 0, row.input >= 0, row.output >= 0, row.cached >= 0, row.requests >= 0 else { throw LocalAIError.invalid }
            let (sum, overflow) = total.addingReportingOverflow(row.total); guard !overflow else { throw LocalAIError.invalid }; total = sum
        }
        guard report.windows.allSatisfy({ $0.used.isFinite && (0...100).contains($0.used) && $0.resets.timeIntervalSince1970.isFinite }), report.sessionCost.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw LocalAIError.invalid }
        return report
    }
    static func boundedFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try boundedInput(handle)
    }
    static func boundedInput(_ handle: FileHandle) throws -> Data {
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, maxBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk); guard data.count <= maxBytes else { throw LocalAIError.tooLarge }
        }
        return data
    }
    static func capture(_ provider: LocalAIProvider) -> Int32 {
        do {
            let report = try decode(boundedInput(.standardInput), provider: provider)
            try save(report, provider: provider)
            if provider == .claude {
                print(report.windows.isEmpty ? "Claude · DockGrove connected" : report.windows.map { "\($0.name): \(Int(100 - $0.used))% left" }.joined(separator: " · "))
            } else { print("Gemini session saved to DockGrove: \(report.totalTokens) tokens. Response text was not retained.") }
            return 0
        } catch { fputs("DockGrove: usage capture failed; no new report saved.\n", stderr); return 1 }
    }
}
enum ClaudeStatusLineSetup {
    static func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static var command: String { quote(Bundle.main.executableURL!.path) + " --claude-statusline" }
    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static func install(at url: URL = settingsURL, command: String = command) throws {
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let root = try JSONSerialization.jsonObject(with: LocalAIStore.boundedFile(url)) as? [String: Any] else { throw LocalAIError.invalid }; settings = root
        }
        if let existing = settings["statusLine"], !(existing is NSNull) {
            guard let row = existing as? [String: Any], row["command"] as? String == command, row["type"] as? String == "command" else { throw LocalAIError.existingStatusLine }
            return
        }
        settings["statusLine"] = ["type": "command", "command": command]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func remove(at url: URL = settingsURL, command: String = command) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard var settings = try JSONSerialization.jsonObject(with: LocalAIStore.boundedFile(url)) as? [String: Any] else { throw LocalAIError.invalid }
        guard let value = settings["statusLine"] else { return }
        guard let row = value as? [String: Any], row["command"] as? String == command else { throw LocalAIError.changedSettings }
        settings.removeValue(forKey: "statusLine")
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
@MainActor final class LocalAIWidget: ObservableObject {
    let provider: LocalAIProvider
    @Published var report: LocalAIReport?
    @Published var status = ""
    private var timer: Timer?
    init(_ provider: LocalAIProvider) { self.provider = provider }
    func start() {
        refresh(); guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh() {
        do { report = try LocalAIStore.load(provider); status = "Last received " + report!.observed.formatted(date: .abbreviated, time: .shortened) }
        catch { report = nil; status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func connectClaude() {
        do { try ClaudeStatusLineSetup.install(); status = "Connected. Start a new Claude Code session and send a prompt to receive its report." }
        catch { status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func disconnectClaude() {
        do { try ClaudeStatusLineSetup.remove(); status = "DockGrove status line removed. Existing Claude settings preserved." }
        catch { status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func importReport() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.message = "Choose a Gemini CLI --output-format json report. Only usage statistics are retained."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let parsed = try LocalAIStore.decode(LocalAIStore.boundedFile(url), provider: .gemini); try LocalAIStore.save(parsed, provider: .gemini); refresh() }
        catch { status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func clear() {
        do { let url = LocalAIStore.url(provider); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; report = nil; status = "Local usage snapshot cleared." }
        catch { status = "Could not clear the local snapshot." }
    }
    deinit { timer?.invalidate() }
}
struct LocalAIUsageView: View {
    @ObservedObject var widget: LocalAIWidget
    var automaticallyRefresh = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(widget.provider == .claude ? "Claude Code’s reported allowance windows. Available for supported Pro/Max sessions after an API response." : "The latest imported Gemini CLI session. These are session token counts, not remaining subscription allowances.").font(.caption).foregroundStyle(.secondary)
            if let report = widget.report {
                if report.stale(at: Date()) { Label("Older report · refresh from your CLI", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
                if widget.provider == .claude {
                    let windows = report.activeWindows(at: Date())
                    if windows.isEmpty { Text("No active allowance windows reported.").font(.callout) }
                    ForEach(windows.indices, id: \.self) { i in
                        let window = windows[i]
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(window.name); Spacer(); Text("\(Int(100 - window.used))% left").monospacedDigit() }
                            ProgressView(value: 100 - window.used, total: 100)
                            Text("Resets " + window.resets.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let cost = report.sessionCost { Text("Session API-equivalent cost: " + cost.formatted(.currency(code: "USD"))).font(.caption); Text("Not a subscription invoice.").font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text(report.totalTokens.formatted() + " tokens").font(.title2).monospacedDigit()
                    ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(report.models) { row in
                        VStack(alignment: .leading, spacing: 4) { Text(row.name).font(.headline).lineLimit(2); Text("\(row.requests.formatted()) requests · \(row.total.formatted()) total tokens"); Text("Input \(row.input.formatted()) · Output \(row.output.formatted()) · Cached \(row.cached.formatted())").foregroundStyle(.secondary) }.font(.caption)
                    } } }.frame(maxHeight: 160)
                }
            }
            Text(widget.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if widget.provider == .claude {
                Button("Connect Claude Code status line", action: widget.connectClaude)
                Button("Remove DockGrove status line", action: widget.disconnectClaude)
                Text("Adds a command to ~/.claude/settings.json. Custom status lines are never overwritten. Keep DockGrove in the same location after connecting.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Import Gemini session JSON…", action: widget.importReport)
                Button("Copy CLI capture command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("gemini --output-format json -p 'YOUR PROMPT' | " + ClaudeStatusLineSetup.quote(Bundle.main.executableURL!.path) + " --gemini-report", forType: .string) }
                Text("Use with a run you choose to make. DockGrove never runs a prompt or charges your AI account to refresh.").font(.caption2).foregroundStyle(.secondary)
            }
            HStack { Button("Refresh", action: widget.refresh); Button("Clear local snapshot", action: widget.clear) }
            Link("Provider setup documentation", destination: widget.provider.documentation).font(.caption)
            Text("Only usage metrics stay on this Mac. No prompts, responses, credentials or transcript paths are retained.").font(.caption2).foregroundStyle(.secondary)
        }.onAppear { if automaticallyRefresh { widget.start() } }
    }
}
