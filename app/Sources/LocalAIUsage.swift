import Foundation
import SwiftUI
import AppKit

enum LocalAIProvider: String { case claude, gemini
    var title: String { self == .claude ? "Claude Code" : "Gemini CLI" }
    var documentation: URL { URL(string: self == .claude ? "https://code.claude.com/docs/en/statusline" : "https://geminicli.com/docs/cli/headless/")! }
}
/// One allowance window. `resets` is nil when Claude Code gave a reset time DockGrove could not
/// read; `resetText` then keeps its words. Both new fields are optional so older files still load.
struct LocalAIWindow: Codable {
    let name: String; let used: Double; let resets: Date?; var resetText: String? = nil
    var resetLabel: String? { resets.map { "Resets " + $0.formatted(date: .abbreviated, time: .shortened) } ?? resetText.map { "Resets " + $0 } }
}
/// A "What's contributing to your usage?" line from `/usage`, such as "89% Start fresh…".
struct LocalAIDriver: Codable { let percent: Int; let text: String }
struct LocalAIModel: Codable, Identifiable {
    var id: String { name }; let name: String; let total: Int64; let input: Int64; let output: Int64; let cached: Int64; let requests: Int64
}
struct LocalAIReport: Codable {
    let provider: String; let observed: Date; let windows: [LocalAIWindow]; let models: [LocalAIModel]; let sessionCost: Double?
    /// "usage" for a report read from `claude -p /usage`; nil for the status line and Gemini.
    var source: String? = nil
    /// The `/usage` "Last 24h · … requests · … sessions" line and its top contributors.
    var summary: String? = nil
    var drivers: [LocalAIDriver]? = nil
    var totalTokens: Int64 { models.reduce(0) { $0 + $1.total } }
    func activeWindows(at now: Date) -> [LocalAIWindow] { windows.filter { $0.resets.map { $0 > now } ?? true } }
    /// The window closest to its limit, which the compact card shows.
    func mostConstrained(at now: Date) -> LocalAIWindow? { activeWindows(at: now).max { $0.used < $1.used } }
    func stale(at now: Date) -> Bool { now.timeIntervalSince(observed) > 1800 }
    /// The `/usage` report while it is fresh (it lists every window); otherwise the status line's,
    /// falling back to an older `/usage` report when nothing newer arrived. The status line's
    /// session cost is kept either way.
    static func merged(statusLine: LocalAIReport?, usage: LocalAIReport?, now: Date) -> LocalAIReport? {
        guard let usage else { return statusLine }
        if let statusLine, usage.stale(at: now), statusLine.observed > usage.observed { return statusLine }
        return LocalAIReport(provider: usage.provider, observed: usage.observed, windows: usage.windows, models: [], sessionCost: statusLine?.sessionCost,
                             source: usage.source, summary: usage.summary, drivers: usage.drivers)
    }
}
enum LocalAIError: Error, LocalizedError {
    case invalid, tooLarge, existingStatusLine, changedSettings, missing, cliMissing, signedOut, noLimits, cliFailed
    var errorDescription: String? { switch self {
    case .cliMissing: return "Install Claude Code to see every limit from /usage."
    case .signedOut: return "Sign in to Claude Code to see your limits."
    case .noLimits: return "Claude Code reported no subscription limits. /usage lists them for Pro and Max plans."
    case .cliFailed: return "Could not read /usage from Claude Code. Showing the latest status line report."
    case .invalid: return "This is not a supported usage report. No new data was saved."
    case .tooLarge: return "This report is too large. The maximum is 20 MB."
    case .existingStatusLine: return "Claude Code’s status line is not a command, so DockGrove left it unchanged and it keeps working. Use the setup guide to add DockGrove’s capture command to it."
    case .changedSettings: return "The status line changed outside DockGrove. It was preserved; remove the DockGrove command manually if needed."
    case .missing: return "No local report yet. Connect a status line or import a report to begin."
    } }
}
enum LocalAIStore {
    static let maxBytes = 20_000_000
    static var folder: URL { BrandStorage.supportDirectory.appendingPathComponent("AI Usage") }
    /// The status-line (or Gemini) report; `usage` is the separate `claude -p /usage` report.
    static func url(_ provider: LocalAIProvider, directory: URL = folder, usage: Bool = false) -> URL { directory.appendingPathComponent(provider.rawValue + (usage ? "-usage" : "") + ".json") }
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
                for (key, title) in [("five_hour", "5-hour window"), ("seven_day", "Weekly · all models"), ("spend_limit", "Gateway spend limit")] {
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
    static func save(_ report: LocalAIReport, provider: LocalAIProvider, directory: URL = folder, usage: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = url(provider, directory: directory, usage: usage)
        try JSONEncoder().encode(report).write(to: target, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    static func load(_ provider: LocalAIProvider, directory: URL = folder, usage: Bool = false) throws -> LocalAIReport {
        let target = url(provider, directory: directory, usage: usage)
        guard FileManager.default.fileExists(atPath: target.path) else { throw LocalAIError.missing }
        let data = try boundedFile(target)
        let report = try JSONDecoder().decode(LocalAIReport.self, from: data)
        guard report.provider == provider.rawValue, report.observed.timeIntervalSince1970.isFinite,
              report.observed <= Date().addingTimeInterval(300), report.windows.count <= 8, report.models.count <= 100, (report.drivers?.count ?? 0) <= 8, (report.summary?.count ?? 0) <= 200 else { throw LocalAIError.invalid }
        var total: Int64 = 0
        for row in report.models {
            guard row.total >= 0, row.input >= 0, row.output >= 0, row.cached >= 0, row.requests >= 0 else { throw LocalAIError.invalid }
            let (sum, overflow) = total.addingReportingOverflow(row.total); guard !overflow else { throw LocalAIError.invalid }; total = sum
        }
        guard report.windows.allSatisfy({ $0.used.isFinite && (0...100).contains($0.used) && ($0.resets?.timeIntervalSince1970.isFinite ?? true) && $0.name.count <= 100 && ($0.resetText?.count ?? 0) <= 200 }),
              (report.drivers ?? []).allSatisfy({ (0...100).contains($0.percent) && $0.text.count <= 200 }), report.sessionCost.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw LocalAIError.invalid }
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
    /// The user's own status-line command passed after `--then`, if any.
    static func chainedCommand(_ arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--then"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    /// Reads at most `maxBytes + 1` bytes without throwing, so a chained status line still gets its input.
    static func boundedPrefix(_ handle: FileHandle) -> Data {
        var data = Data()
        while data.count <= maxBytes, let chunk = try? handle.read(upToCount: min(65_536, maxBytes + 1 - data.count)), !chunk.isEmpty { data.append(chunk) }
        return data
    }
    /// With `original`, saves the report when it decodes and then runs the user's own status line
    /// through `/bin/sh -c` with the same input, forwarding its output and exit status. A capture
    /// failure never breaks their status line. Without it, prints DockGrove's own status line.
    static func capture(_ provider: LocalAIProvider, input: FileHandle = .standardInput, directory: URL = folder, then original: String? = nil, output: FileHandle = .standardOutput, shell: URL = URL(fileURLWithPath: "/bin/sh")) -> Int32 {
        if let original {
            let data = boundedPrefix(input)
            if let report = try? decode(data, provider: provider) { try? save(report, provider: provider, directory: directory) }
            let process = Process(), pipe = Pipe()
            process.executableURL = shell; process.arguments = ["-c", original]
            process.standardInput = pipe; process.standardOutput = output
            // An original that exits without reading its input must not kill DockGrove with SIGPIPE.
            _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            do { try process.run() } catch { fputs("DockGrove: could not run the original status line.\n", stderr); return 127 }
            try? pipe.fileHandleForReading.close()
            let writer = pipe.fileHandleForWriting
            DispatchQueue.global().async { try? writer.write(contentsOf: data); try? writer.close() }
            process.waitUntilExit()
            return process.terminationStatus
        }
        do {
            let report = try decode(boundedInput(input), provider: provider)
            try save(report, provider: provider, directory: directory)
            if provider == .claude {
                print(report.windows.isEmpty ? "Claude · DockGrove connected" : report.windows.map { "\($0.name): \(Int(100 - $0.used))% left" }.joined(separator: " · "))
            } else { print("Gemini session saved to DockGrove: \(report.totalTokens) tokens. Response text was not retained.") }
            return 0
        } catch { fputs("DockGrove: usage capture failed; no new report saved.\n", stderr); return 1 }
    }
}
/// Reads the text Claude Code's `/usage` prints, for example
/// "Current week (all models): 28% used · resets Nov 6 at 7:59pm (America/New_York)".
enum ClaudeUsageParser {
    static func title(_ label: String) -> String {
        let label = label.trimmingCharacters(in: .whitespaces)
        if label.caseInsensitiveCompare("session") == .orderedSame { return "5-hour window" }
        if label.lowercased().hasPrefix("week") {
            guard let open = label.firstIndex(of: "("), label.hasSuffix(")") else { return "Weekly · all models" }
            return "Weekly · " + label[label.index(after: open)..<label.index(before: label.endIndex)].trimmingCharacters(in: .whitespaces)
        }
        return label.prefix(1).uppercased() + label.dropFirst()
    }
    private static func match(_ pattern: String, _ text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<found.numberOfRanges).map { Range(found.range(at: $0), in: text).map { String(text[$0]) } }
    }
    /// "Nov 6 at 7:59pm (America/New_York)" is the next Nov 6 at that time in that zone; a time alone
    /// ("7:59pm (UTC)") is its next occurrence, today or tomorrow. Nil for anything else.
    static func resetDate(_ text: String, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        var rest = text.trimmingCharacters(in: .whitespaces)
        if let zone = match(#"^(.*?)\s*\(([^()]+)\)$"#, rest) {
            guard let name = zone[1], let timeZone = TimeZone(identifier: name) ?? TimeZone(abbreviation: name) else { return nil }
            calendar.timeZone = timeZone; rest = zone[0]! // the first group always takes part
        }
        let parts = rest.components(separatedBy: " at ")
        guard parts.count <= 2, let clock = match(#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#, parts[parts.count - 1].trimmingCharacters(in: .whitespaces)),
              var hour = Int(clock[0]!), hour <= 23 else { return nil }
        let minute = clock[1].flatMap { Int($0) } ?? 0, meridiem = clock[2]?.lowercased()
        if let meridiem { guard (1...12).contains(hour) else { return nil }; hour = hour % 12 + (meridiem == "pm" ? 12 : 0) }
        guard minute <= 59, clock[1] != nil || meridiem != nil else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now); components.hour = hour; components.minute = minute
        if parts.count == 1 {
            guard let today = calendar.date(from: components) else { return nil }
            return today >= now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        let months = DateFormatter(); months.locale = Locale(identifier: "en_US_POSIX")
        guard let day = match(#"^([a-z]+)\.? (\d{1,2})(?:, (\d{4}))?$"#, parts[0].trimmingCharacters(in: .whitespaces)),
              let name = day[0]?.lowercased(), let month = (0..<12).first(where: { months.monthSymbols[$0].lowercased() == name || months.shortMonthSymbols[$0].lowercased() == name }) else { return nil }
        components.month = month + 1; components.day = Int(day[1]!)
        if let year = day[2] { components.year = Int(year) }
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == components.day else { return nil }
        // Without a year, a date more than a day past is next year's.
        if day[2] == nil, date < now.addingTimeInterval(-86400) { return calendar.date(byAdding: .year, value: 1, to: date) }
        return date
    }
    /// Every "Current <label>: N% used[ · resets <time>]" line, plus the "Last 24h" summary and its top three contributors.
    static func parse(_ text: String, now: Date) -> (windows: [LocalAIWindow], summary: String?, drivers: [LocalAIDriver]) {
        var windows: [LocalAIWindow] = [], summary: String?, drivers: [LocalAIDriver] = [], inSummary = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let row = match(#"^Current ([^:]{1,80}): (\d{1,3}(?:\.\d+)?)% used(?:\s*[·•|-]\s*resets\s+(.{1,200}))?$"#, line), windows.count < 8,
               let used = Double(row[1]!) {
                let reset = row[2]?.trimmingCharacters(in: .whitespaces)
                windows.append(LocalAIWindow(name: title(row[0]!), used: min(used, 100), resets: reset.flatMap { resetDate($0, now: now) }, resetText: reset))
                continue
            }
            if line.hasPrefix("Last 24h"), line.count <= 200 { summary = line; inSummary = true; continue }
            if line.isEmpty { inSummary = false; continue }
            if inSummary, drivers.count < 3, let row = match(#"^(\d{1,3})%\s+(.{1,200})$"#, line), let percent = Int(row[0]!), percent <= 100 {
                drivers.append(LocalAIDriver(percent: percent, text: row[1]!))
            }
        }
        return (windows, summary, drivers)
    }
    /// The JSON `claude -p /usage --output-format json` prints. Throws `signedOut`, `noLimits` or `cliFailed`.
    static func report(_ data: Data, now: Date) throws -> LocalAIReport {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LocalAIError.cliFailed }
        let text = root["result"] as? String ?? ""
        let signedOut = ["not logged in", "log in", "login", "sign in", "authenticate"].contains { text.lowercased().contains($0) }
        if root["is_error"] as? Bool == true { throw signedOut ? LocalAIError.signedOut : .cliFailed }
        let parsed = parse(text, now: now)
        guard !parsed.windows.isEmpty else { throw signedOut ? LocalAIError.signedOut : .noLimits }
        return LocalAIReport(provider: LocalAIProvider.claude.rawValue, observed: now, windows: parsed.windows, models: [], sessionCost: nil,
                             source: "usage", summary: parsed.summary, drivers: parsed.drivers.isEmpty ? nil : parsed.drivers)
    }
}
/// Runs Claude Code's local `/usage` command. It makes no model request and costs nothing, and
/// `--no-session-persistence` keeps it out of the user's session history.
enum ClaudeUsageCommand {
    static let arguments = ["-p", "/usage", "--output-format", "json", "--no-session-persistence"]
    static let maxBytes = 1_000_000
    private final class Output: @unchecked Sendable { let lock = NSLock(); var data = Data(); var overflow = false }
    /// The production runner, so a widget can store it as a plain function value.
    static func live(_ executable: String) async throws -> Data { try await run(executable) }
    /// Runs the CLI on a background queue with a bounded output and a time limit.
    static func run(_ executable: String, timeout: TimeInterval = 30, maxBytes: Int = maxBytes) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(with: Result { try runSync(executable, timeout: timeout, maxBytes: maxBytes) }) }
        }
    }
    static func runSync(_ executable: String, timeout: TimeInterval, maxBytes: Int) throws -> Data {
        let process = Process(), pipe = Pipe(), output = Output()
        let finished = DispatchSemaphore(value: 0), exited = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = AICommand.environment(for: executable)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; finished.signal(); return }
            output.lock.lock(); if !output.overflow { output.data.append(chunk) }; let over = output.data.count > maxBytes; output.overflow = over; output.lock.unlock()
            if over { process.terminate() }
        }
        do { try process.run() } catch { pipe.fileHandleForReading.readabilityHandler = nil; throw LocalAIError.cliFailed }
        let deadline = DispatchTime.now() + timeout
        guard finished.wait(timeout: deadline) == .success, exited.wait(timeout: deadline) == .success else {
            pipe.fileHandleForReading.readabilityHandler = nil; process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            throw LocalAIError.cliFailed
        }
        output.lock.lock(); defer { output.lock.unlock() }
        guard !output.overflow, process.terminationReason == .exit else { throw LocalAIError.cliFailed }
        return output.data
    }
}
enum ClaudeStatusLineSetup {
    static func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static var command: String { quote(Bundle.main.executableURL!.path) + " --claude-statusline" }
    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    /// Where the user's own status line is kept while DockGrove's capture wraps it.
    static func originalURL(_ directory: URL) -> URL { directory.appendingPathComponent("claude-statusline-original.json") }
    /// Reverses `quote`; nil for anything `quote` could not have produced.
    static func unquote(_ value: String) -> String? {
        guard value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") else { return nil }
        let parts = String(value.dropFirst().dropLast()).components(separatedBy: "'\\''")
        guard !parts.contains(where: { $0.contains("'") }) else { return nil }
        return parts.joined(separator: "'")
    }
    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Enables DockGrove's capture. A custom command status line keeps working: DockGrove runs it
    /// after reading usage (`--then`), and its original settings are saved in `backups` so `remove`
    /// can restore them exactly. Returns true when a custom status line is wrapped.
    @discardableResult
    static func install(at url: URL = settingsURL, command: String = command, backups: URL = LocalAIStore.folder) throws -> Bool {
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let root = try JSONSerialization.jsonObject(with: LocalAIStore.boundedFile(url)) as? [String: Any] else { throw LocalAIError.invalid }; settings = root
        }
        var row: [String: Any] = ["type": "command", "command": command], wrapped = false
        if let existing = settings["statusLine"], !(existing is NSNull) {
            guard let current = existing as? [String: Any], current["type"] as? String == "command", let original = current["command"] as? String else { throw LocalAIError.existingStatusLine }
            if original == command { return false }
            if original.hasPrefix(command + " --then ") { return true }
            let chained = command + " --then " + quote(original)
            try writeJSON(["command": chained, "original": current], to: originalURL(backups))
            row = current; row["command"] = chained; wrapped = true
        }
        settings["statusLine"] = row
        try writeJSON(settings, to: url)
        return wrapped
    }
    /// Removes DockGrove's capture, restoring a wrapped status line. Returns true when one was restored.
    @discardableResult
    static func remove(at url: URL = settingsURL, command: String = command, backups: URL = LocalAIStore.folder) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard var settings = try JSONSerialization.jsonObject(with: LocalAIStore.boundedFile(url)) as? [String: Any] else { throw LocalAIError.invalid }
        guard let value = settings["statusLine"] else { return false }
        guard var row = value as? [String: Any], let current = row["command"] as? String else { throw LocalAIError.changedSettings }
        let backup = originalURL(backups), prefix = command + " --then "
        if current == command { settings.removeValue(forKey: "statusLine") }
        else if current.hasPrefix(prefix) {
            if let saved = try? JSONSerialization.jsonObject(with: LocalAIStore.boundedFile(backup)) as? [String: Any], saved["command"] as? String == current, let original = saved["original"] as? [String: Any] { settings["statusLine"] = original }
            else if let original = unquote(String(current.dropFirst(prefix.count))) { row["command"] = original; settings["statusLine"] = row }
            else { throw LocalAIError.changedSettings }
        } else { throw LocalAIError.changedSettings }
        try writeJSON(settings, to: url)
        try? FileManager.default.removeItem(at: backup)
        return current != command
    }
}
@MainActor final class LocalAIWidget: ObservableObject {
    let provider: LocalAIProvider
    let signIn = AISignIn()
    @Published var report: LocalAIReport?
    @Published var status = ""
    /// Progress and problems of the `claude -p /usage` reader, shown under the windows.
    @Published var usageStatus = ""
    @Published private(set) var usageBusy = false
    private(set) var timer: Timer?
    private(set) var usageTimer: Timer?
    private(set) var lastUsageRun: Date?
    /// File locations and system services. Tests point these at temporary files and fakes.
    var directory = LocalAIStore.folder
    var settingsURL = ClaudeStatusLineSetup.settingsURL
    var command = ClaudeStatusLineSetup.command
    var chooseFile: (String) -> URL? = SystemPicker.chooseFile(message:)
    var pasteboard = NSPasteboard.general
    /// Whether the app may run Claude Code's `/usage`. Off in test hosts, so nothing runs the real CLI.
    static var runsUsageCommand = !(TestEnvironment.isXCTest || CommandLine.arguments.contains("--ui-test") || CommandLine.arguments.contains("--native-test"))
    /// Runs `claude -p /usage` for an executable path; nil disables it. Tests inject a fake.
    var runUsage: ((String) async throws -> Data)? = LocalAIWidget.runsUsageCommand ? ClaudeUsageCommand.live : nil
    init(_ provider: LocalAIProvider) { self.provider = provider }
    func start() {
        refresh(); refreshUsageIfDue(); guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        if provider == .claude { usageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshUsageIfDue() } } }
    }
    func stop() { timer?.invalidate(); timer = nil; usageTimer?.invalidate(); usageTimer = nil }
    func refresh() {
        let line = Result { try LocalAIStore.load(provider, directory: directory) }
        let usage = provider == .claude ? try? LocalAIStore.load(provider, directory: directory, usage: true) : nil
        if let merged = LocalAIReport.merged(statusLine: try? line.get(), usage: usage, now: Date()) {
            report = merged; status = (merged.source == "usage" ? "Updated from /usage " : "Last received ") + merged.observed.formatted(date: .abbreviated, time: .shortened)
        } else if case .failure(let error) = line { report = nil; status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    /// Runs `/usage` when it has not run in the last five minutes.
    func refreshUsageIfDue() {
        guard lastUsageRun.map({ Date().timeIntervalSince($0) >= 290 }) ?? true else { return }
        refreshUsage()
    }
    /// Reloads the saved reports and asks Claude Code's `/usage` for every current window.
    func refreshUsage() {
        refresh()
        guard provider == .claude, let runUsage, !usageBusy else { return }
        lastUsageRun = Date()
        guard let path = signIn.resolve(.claude, "") else { usageStatus = LocalAIError.cliMissing.localizedDescription; return }
        usageBusy = true; usageStatus = "Reading /usage from Claude Code…"
        let directory = directory
        Task {
            do {
                let parsed = try ClaudeUsageParser.report(try await runUsage(path), now: Date())
                try LocalAIStore.save(parsed, provider: .claude, directory: directory, usage: true)
                usageStatus = ""
            } catch { usageStatus = (error as? LocalAIError ?? .cliFailed).localizedDescription }
            usageBusy = false; refresh()
        }
    }
    func connectClaude() {
        do {
            let wrapped = try ClaudeStatusLineSetup.install(at: settingsURL, command: command, backups: directory)
            status = "Connected." + (wrapped ? " Your custom status line keeps working; DockGrove reads usage, then runs it." : "") + " Start a new Claude Code session and send a prompt to receive its report."
        }
        catch { status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func disconnectClaude() {
        do {
            let restored = try ClaudeStatusLineSetup.remove(at: settingsURL, command: command, backups: directory)
            status = "DockGrove status line removed. " + (restored ? "Your original status line was restored." : "Existing Claude settings preserved.")
        }
        catch { status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func importReport() {
        guard let url = chooseFile("Choose a Gemini CLI --output-format json report. Only usage statistics are retained.") else { return }
        do { let parsed = try LocalAIStore.decode(LocalAIStore.boundedFile(url), provider: .gemini); try LocalAIStore.save(parsed, provider: .gemini, directory: directory); refresh() }
        catch { status = (error as? LocalAIError ?? .invalid).localizedDescription }
    }
    func clear() {
        do {
            for url in [LocalAIStore.url(provider, directory: directory), LocalAIStore.url(provider, directory: directory, usage: true)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            report = nil; status = "Local usage snapshot cleared."
        }
        catch { status = "Could not clear the local snapshot." }
    }
    func copyCaptureCommand() {
        pasteboard.clearContents()
        pasteboard.setString("gemini --output-format json -p 'YOUR PROMPT' | " + ClaudeStatusLineSetup.quote(Bundle.main.executableURL!.path) + " --gemini-report", forType: .string)
    }
    deinit { timer?.invalidate() }
}
struct LocalAIUsageView: View {
    @Environment(\.connectionSetupAllowed) private var environmentSetupAllowed
    @ObservedObject var widget: LocalAIWidget
    /// Overrides the environment's setup permission so tests can drive both layouts directly.
    var setupAllowedOverride: Bool?
    private var setupAllowed: Bool { setupAllowedOverride ?? environmentSetupAllowed }
    var automaticallyRefresh = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if setupAllowed {
                if widget.provider == .claude {
                    AISignInControls(signIn: widget.signIn, provider: .claude) { widget.connectClaude() }
                    Text("After sign-in, DockGrove enables its usage status line. An existing custom status line keeps working: DockGrove reads usage, then runs it. Usage arrives after your next Claude Code response.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                } else { GeminiSignInControls(); Divider() }
            }
            Text(widget.provider == .claude ? "Claude Code’s limits, as /usage lists them: the 5-hour session, the weekly window and per-model weekly windows. Read from your Pro/Max plan at no cost." : "The latest imported Gemini CLI session. These are session token counts, not remaining subscription allowances.").font(.caption).foregroundStyle(.secondary)
            if let report = widget.report {
                if report.stale(at: Date()) { Label("Older report · refresh from your CLI", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
                if widget.provider == .claude {
                    let windows = report.activeWindows(at: Date())
                    if windows.isEmpty { Text("No active allowance windows reported.").font(.callout) }
                    ForEach(windows.indices, id: \.self) { i in
                        let window = windows[i]
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(window.name); Spacer(); Text("\(Int(window.used.rounded()))% used").monospacedDigit() }
                            ProgressView(value: window.used, total: 100).tint(window.used >= 80 ? .orange : .accentColor)
                            if let reset = window.resetLabel { Text(reset).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    if let summary = report.summary, let drivers = report.drivers {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What’s driving usage").font(.caption.weight(.semibold))
                            Text(summary + " · approximate, this Mac only").font(.caption2).foregroundStyle(.secondary)
                            ForEach(drivers.indices, id: \.self) { i in
                                HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(drivers[i].percent)%").monospacedDigit().frame(width: 34, alignment: .trailing); Text(drivers[i].text).lineLimit(2) }.font(.caption)
                            }
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
            if !widget.usageStatus.isEmpty { Label(widget.usageStatus, systemImage: widget.usageBusy ? "arrow.triangle.2.circlepath" : "info.circle").font(.caption).fixedSize(horizontal: false, vertical: true) }
            if setupAllowed {
            if widget.provider == .claude {
                Button("Set up Claude Code status line", action: widget.connectClaude)
                Button("Remove DockGrove status line", action: widget.disconnectClaude)
                Text("Adds a command to ~/.claude/settings.json. A custom status line keeps working and is restored exactly when you remove DockGrove’s. Keep DockGrove in the same location after connecting.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Import Gemini session JSON…", action: widget.importReport)
                Button("Copy CLI capture command", action: widget.copyCaptureCommand)
                Text("Use with a run you choose to make. DockGrove never runs a prompt or charges your AI account to refresh.").font(.caption2).foregroundStyle(.secondary)
            }
            } else { ConnectionSettingsButton() }
            HStack { Button("Refresh", action: widget.refreshUsage).disabled(widget.usageBusy); Button("Clear local snapshot", action: widget.clear) }
            Link("Provider setup documentation", destination: widget.provider.documentation).font(.caption)
            Text("Only usage metrics stay on this Mac. No prompts, responses, credentials or transcript paths are retained.").font(.caption2).foregroundStyle(.secondary)
        }.onAppear { if automaticallyRefresh { widget.start() } }
    }
}
