import Foundation
import Darwin

struct LimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    var title: String {
        guard let mins = windowDurationMins else { return "Usage window" }
        if mins % 1440 == 0 { return "\(mins / 1440) day" }
        if mins % 60 == 0 { return "\(mins / 60) hour" }
        return "\(mins) min"
    }
    var resetDescription: String {
        guard let timestamp = resetsAt else { return "Reset time unavailable" }
        let date = Date(timeIntervalSince1970: timestamp)
        if date <= Date() { return "Awaiting reset refresh" }
        return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct LimitBucket: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: LimitWindow?
    let secondary: LimitWindow?
    let planType: String?
    var title: String { limitName ?? (limitId == "codex" ? "Codex" : limitId) ?? "Plan usage" }
}

struct UsageResponse: Decodable {
    let rateLimits: LimitBucket?
    let rateLimitsByLimitId: [String: LimitBucket]?
    var buckets: [(String, LimitBucket)] {
        if let all = rateLimitsByLimitId, !all.isEmpty {
            return all.sorted { a, b in
                if a.key == "codex" { return b.key != "codex" }
                if b.key == "codex" { return false }
                return a.key < b.key
            }
        }
        if let one = rateLimits { return [(one.limitId ?? "default", one)] }
        return []
    }
}

enum UsageError: LocalizedError {
    case missingCLI, timeout, disconnected, service, noWindows
    var errorDescription: String? {
        switch self {
        case .missingCLI: return "Choose the Codex executable in Settings, or install ChatGPT / Codex CLI."
        case .timeout: return "The usage service timed out. Try refreshing again."
        case .disconnected: return "Could not connect. Sign in with ChatGPT in Codex, then refresh."
        case .service: return "Usage is unavailable. Check your Codex sign-in and connection, then retry."
        case .noWindows: return "This account did not report any usage windows."
        }
    }
}

enum UsageClient {
    static func executable(custom: String) -> String? {
        let candidates = [custom,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex"]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    // Read-only account RPCs: no turns, prompts, token-file parsing, or inference requests.
    static func fetch(custom: String) throws -> UsageResponse {
        guard let executable = executable(custom: custom) else { throw UsageError.missingCLI }
        let child = Process()
        let input = Pipe(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        child.environment = environment
        child.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        // A child that exits early must produce an error, never SIGPIPE the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try child.run()
        defer {
            try? input.fileHandleForWriting.close()
            if child.isRunning { child.terminate() }
            let pid = child.processIdentifier
            // Avoid orphaned subprocesses if a service ignores SIGTERM.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(pid, SIGKILL) }
            }
            try? output.fileHandleForReading.close()
        }
        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "wavedock", "title": "WaveDock", "version": "0.7.0"]]])
        var buffer = Data()
        let deadline = Date().addingTimeInterval(25)
        let fd = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 250)
            if ready < 0 { if errno == EINTR { continue }; throw UsageError.disconnected }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { throw UsageError.disconnected }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 2_000_000 else { throw UsageError.service }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let id = object["id"] as? Int {
                    if object["error"] != nil { throw UsageError.service }
                    if id == 0 {
                        try send(["method": "initialized", "params": [:]])
                        try send(["id": 1, "method": "account/rateLimits/read"])
                    } else if id == 1, let result = object["result"] {
                        let data = try JSONSerialization.data(withJSONObject: result)
                        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
                        guard response.buckets.contains(where: { $0.1.primary != nil || $0.1.secondary != nil }) else { throw UsageError.noWindows }
                        return response
                    }
                }
            }
        }
        throw UsageError.timeout
    }
}
