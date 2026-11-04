import Foundation
@testable import DockGrove

func runLocalAIUsageTests() throws {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let claude = Data(#"{"model":{"display_name":"Claude"},"context_window":{},"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":1780003600},"seven_day":{"used_percentage":50.5,"resets_at":1780600000}},"cost":{"total_cost_usd":0.12},"transcript_path":"PRIVATE_PATH","prompt":"PRIVATE_PROMPT"}"#.utf8)
    let report = try LocalAIStore.decode(claude, provider: .claude, now: now)
    precondition(report.windows.count == 2 && report.windows[0].used == 24 && report.sessionCost == 0.12)
    precondition(report.activeWindows(at: now.addingTimeInterval(4000)).count == 1)
    precondition(report.activeWindows(at: now.addingTimeInterval(700000)).isEmpty)
    precondition(!report.stale(at: now) && report.stale(at: now.addingTimeInterval(1801)))
    let missing = try LocalAIStore.decode(Data(#"{"model":{},"context_window":{}}"#.utf8), provider: .claude, now: now)
    precondition(missing.windows.isEmpty && missing.sessionCost == nil)
    for invalid in [#"{"model":{},"context_window":{},"rate_limits":{"five_hour":{"used_percentage":101,"resets_at":1780003600}}}"#, #"{"model":{},"context_window":{},"rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1780003600}}}"#, #"{"model":{},"context_window":{},"cost":{"total_cost_usd":-1}}"#, "{}", "invalid"] {
        do { _ = try LocalAIStore.decode(Data(invalid.utf8), provider: .claude, now: now); preconditionFailure("Invalid Claude data accepted") } catch { }
    }
    let gemini = Data(#"{"response":"PRIVATE_RESPONSE","session_id":"PRIVATE_SESSION","stats":{"models":{"gemini-pro":{"tokens":{"total":130,"prompt":100,"candidates":30,"cached":40},"api":{"totalRequests":2}},"gemini-flash":{"tokens":{"total":15,"prompt":10,"candidates":5,"cached":0},"api":{"totalRequests":1}}}}}"#.utf8)
    let metrics = try LocalAIStore.decode(gemini, provider: .gemini, now: now)
    precondition(metrics.totalTokens == 145 && metrics.models.count == 2)
    precondition(metrics.models.first(where: { $0.name == "gemini-pro" })?.input == 60)
    for bad in ["-1", "true", "1.5", "null"] {
        let invalid = String(data: gemini, encoding: .utf8)!.replacingOccurrences(of: "\"total\":130", with: "\"total\":" + bad)
        do { _ = try LocalAIStore.decode(Data(invalid.utf8), provider: .gemini); preconditionFailure("Invalid Gemini total accepted") } catch { }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DockGrove-local-ai-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try LocalAIStore.save(metrics, provider: .gemini, directory: root)
    try LocalAIStore.save(metrics, provider: .gemini, directory: root)
    let reloaded = try LocalAIStore.load(.gemini, directory: root); precondition(reloaded.totalTokens == 145)
    let stored = try String(contentsOf: LocalAIStore.url(.gemini, directory: root), encoding: .utf8)
    precondition(!stored.contains("PRIVATE") && !stored.contains("response") && !stored.contains("session_id"))
    let encodedClaude = String(data: try JSONEncoder().encode(report), encoding: .utf8)!
    precondition(!encodedClaude.contains("PRIVATE") && !encodedClaude.contains("transcript"))
    let mode = try FileManager.default.attributesOfItem(atPath: LocalAIStore.url(.gemini, directory: root).path)[.posixPermissions] as! NSNumber
    precondition(mode.intValue == 0o600)
    let settings = root.appendingPathComponent("settings.json"), command = "'/Applications/DockGrove.app/Contents/MacOS/DockGrove' --claude-statusline"
    try Data(#"{"theme":"dark","permissions":{"deny":["secret"]}}"#.utf8).write(to: settings)
    try ClaudeStatusLineSetup.install(at: settings, command: command)
    try ClaudeStatusLineSetup.install(at: settings, command: command)
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    precondition(object["theme"] as? String == "dark" && (object["statusLine"] as? [String: String])?["command"] == command)
    try ClaudeStatusLineSetup.remove(at: settings, command: command)
    object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    precondition(object["statusLine"] == nil && object["permissions"] != nil)
    // A status line that is not a command cannot be chained; it stays untouched.
    object["statusLine"] = ["type": "static", "text": "mine"]
    let original = try JSONSerialization.data(withJSONObject: object); try original.write(to: settings)
    do { try ClaudeStatusLineSetup.install(at: settings, command: command, backups: root); preconditionFailure("Custom status line replaced") } catch { precondition(error as? LocalAIError == .existingStatusLine) }
    do { try ClaudeStatusLineSetup.remove(at: settings, command: command, backups: root); preconditionFailure("Changed status line removed") } catch { precondition(error as? LocalAIError == .changedSettings) }
    let after = try Data(contentsOf: settings); precondition(after == original)

    // A custom command status line is wrapped: DockGrove captures, then runs it with the same input.
    let custom: [String: Any] = ["type": "command", "command": "printf 'mine:'; /bin/cat", "padding": 2]
    object["statusLine"] = custom; try JSONSerialization.data(withJSONObject: object).write(to: settings)
    let wrapped = command + " --then " + ClaudeStatusLineSetup.quote("printf 'mine:'; /bin/cat")
    let didWrap = try ClaudeStatusLineSetup.install(at: settings, command: command, backups: root); precondition(didWrap)
    let wrappedData = try Data(contentsOf: settings)
    object = try JSONSerialization.jsonObject(with: wrappedData) as! [String: Any]
    var line = object["statusLine"] as! [String: Any]
    precondition(line["command"] as? String == wrapped && line["padding"] as? Int == 2 && line["type"] as? String == "command" && object["theme"] as? String == "dark")
    let backup = ClaudeStatusLineSetup.originalURL(root)
    precondition(FileManager.default.fileExists(atPath: backup.path))
    let rewrapped = try ClaudeStatusLineSetup.install(at: settings, command: command, backups: root); precondition(rewrapped, "Install is idempotent")
    let rewrappedData = try Data(contentsOf: settings); precondition(rewrappedData == wrappedData, "Never double-wraps")
    let restored = try ClaudeStatusLineSetup.remove(at: settings, command: command, backups: root); precondition(restored)
    object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    precondition(NSDictionary(dictionary: object["statusLine"] as! [String: Any]).isEqual(to: custom) && object["permissions"] != nil)
    precondition(!FileManager.default.fileExists(atPath: backup.path))

    // Without its saved copy, the original command is recovered from the wrapper itself.
    try ClaudeStatusLineSetup.install(at: settings, command: command, backups: root)
    try FileManager.default.removeItem(at: backup)
    let recovered = try ClaudeStatusLineSetup.remove(at: settings, command: command, backups: root); precondition(recovered)
    line = (try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any])["statusLine"] as! [String: Any]
    precondition(line["command"] as? String == "printf 'mine:'; /bin/cat" && line["padding"] as? Int == 2)

    // Edited after wrapping: preserved and reported.
    for edited in [command + " --then not-quoted", "someone-else"] {
        object["statusLine"] = ["type": "command", "command": edited]
        let data = try JSONSerialization.data(withJSONObject: object); try data.write(to: settings)
        do { try ClaudeStatusLineSetup.remove(at: settings, command: command, backups: root); preconditionFailure("Edited status line removed") } catch { precondition(error as? LocalAIError == .changedSettings) }
        let kept = try Data(contentsOf: settings); precondition(kept == data)
    }
    precondition(ClaudeStatusLineSetup.quote("a'b") == "'a'\\''b'")
    precondition(ClaudeStatusLineSetup.unquote(ClaudeStatusLineSetup.quote("a'b c '")) == "a'b c '")
    precondition(ClaudeStatusLineSetup.unquote("x") == nil && ClaudeStatusLineSetup.unquote("'a'b'") == nil)
    precondition(LocalAIStore.chainedCommand(["DockGrove", "--claude-statusline", "--then", "~/s.sh"]) == "~/s.sh")
    precondition(LocalAIStore.chainedCommand(["DockGrove", "--claude-statusline"]) == nil && LocalAIStore.chainedCommand(["DockGrove", "--then"]) == nil)
    print("PASS: Claude windows/missing/reset/staleness, Gemini multi-model nonoverlapping totals, duplicate import replacement, private-field stripping, file permissions and non-destructive status-line wrapping")
}
