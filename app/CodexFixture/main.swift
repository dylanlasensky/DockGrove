import Foundation

// Local Codex app-server protocol fixture. No account, network or credentials are used.
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
func write(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { fail("Unencodable reply") }
    return text
}

// Copies named codex-<mode> exercise the client's failure handling; the default name is a healthy server.
let mode = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
if mode == "codex-exit" { exit(0) }
if mode == "codex-flood" { while true { write(String(repeating: "x", count: 65_536)) } }
var initialized = false
while let line = readLine() {
    if mode == "codex-hang" { continue }
    guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { fail("Malformed message: " + line) }
    let method = message["method"] as? String
    switch method {
    case "initialize":
        let client = (message["params"] as? [String: Any])?["clientInfo"] as? [String: Any]
        guard client?["name"] as? String == "dockgrove" else { fail("Unexpected client") }
        if mode == "codex-error" { write(json(["id": 0, "error": ["code": -1, "message": "fixture"]]) + "\n"); continue }
        write(json(["id": 0, "result": ["userAgent": "fixture"]]) + "\n")
    case "initialized":
        initialized = true
    case "account/rateLimits/read":
        guard initialized else { fail("Rate limits read before initialized") }
        var result: [String: Any] = ["rateLimits": ["limitId": "codex", "primary": ["usedPercent": 37, "windowDurationMins": 300, "resetsAt": 2_000_000_000]]]
        if mode == "codex-nowindows" { result = ["rateLimits": ["limitId": "codex"]] }
        if mode == "codex-buckets" {
            let secondary: [String: Any] = ["secondary": ["usedPercent": 5, "windowDurationMins": 10080]]
            result = ["rateLimitsByLimitId": ["zeta": secondary, "codex": secondary, "alpha": secondary, "beta": secondary]]
        }
        let reply = json(["id": 1, "result": result])
        // An unrelated notification and a split response exercise the client's framing.
        write(json(["method": "account/updated", "params": [String: Any]()]) + "\n")
        write(String(reply.prefix(20)))
        write(String(reply.dropFirst(20)) + "\n")
    default:
        fail("Unexpected or mutating RPC: " + (method ?? "nil"))
    }
}
