import Foundation

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
    object["statusLine"] = ["type": "command", "command": "my-existing-status-line"]
    let original = try JSONSerialization.data(withJSONObject: object); try original.write(to: settings)
    do { try ClaudeStatusLineSetup.install(at: settings, command: command); preconditionFailure("Custom status line replaced") } catch { }
    do { try ClaudeStatusLineSetup.remove(at: settings, command: command); preconditionFailure("Changed status line removed") } catch { }
    let after = try Data(contentsOf: settings); precondition(after == original)
    precondition(ClaudeStatusLineSetup.quote("a'b") == "'a'\\''b'")
    print("PASS: Claude windows/missing/reset/staleness, Gemini multi-model nonoverlapping totals, duplicate import replacement, private-field stripping, file permissions and non-destructive status-line setup")
}
