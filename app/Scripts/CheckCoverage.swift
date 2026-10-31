import Foundation

// Fails unless every function in DockGrove.app is fully line-covered, apart from the reviewed
// entries in coverage-allowlist.txt. Usage: swift Scripts/CheckCoverage.swift <result.xcresult>
//
// Allowlist lines are `File.swift` (whole file) or `File.swift: function name` exactly as xccov
// prints it, each followed by ` # reason`. Entries that no longer match anything also fail.

func stop(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
guard CommandLine.arguments.count == 2 else { stop("Usage: swift Scripts/CheckCoverage.swift <result.xcresult>") }

let xccov = Process()
xccov.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
xccov.arguments = ["xccov", "view", "--report", "--json", CommandLine.arguments[1]]
let pipe = Pipe()
xccov.standardOutput = pipe
try xccov.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
xccov.waitUntilExit()
guard xccov.terminationStatus == 0 else { stop("xccov could not read \(CommandLine.arguments[1])") }

struct Report: Decodable { let targets: [Target] }
struct Target: Decodable { let name: String; let files: [File] }
struct File: Decodable { let name: String; let coveredLines: Int; let executableLines: Int; let functions: [Function] }
struct Function: Decodable { let name: String; let lineNumber: Int; let coveredLines: Int; let executableLines: Int }

let report = try JSONDecoder().decode(Report.self, from: data)
guard let app = report.targets.first(where: { $0.name == "DockGrove.app" }) else { stop("No DockGrove.app coverage in the result bundle") }

let allowlistURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("coverage-allowlist.txt")
var allowed: [String: Bool] = [:]
for raw in (try String(contentsOf: allowlistURL, encoding: .utf8)).components(separatedBy: .newlines) {
    let entry = raw.components(separatedBy: " # ")[0].trimmingCharacters(in: .whitespaces)
    guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
    guard raw.contains(" # ") else { stop("Allowlist entry needs a ` # reason`: \(raw)") }
    allowed[entry] = false
}

var gaps: [String] = []
var covered = 0, executable = 0
for file in app.files.sorted(by: { $0.name < $1.name }) {
    if allowed[file.name] != nil { allowed[file.name] = true; continue }
    covered += file.coveredLines; executable += file.executableLines
    for function in file.functions where function.coveredLines < function.executableLines {
        let key = "\(file.name): \(function.name)"
        if allowed[key] != nil { allowed[key] = true; continue }
        gaps.append("\(file.name):\(function.lineNumber) \(function.name) — \(function.coveredLines)/\(function.executableLines) lines")
    }
}
let stale = allowed.filter { !$0.value }.map(\.key).sorted()
print(String(format: "DockGrove.app line coverage, allowlisted code included: %.2f%% (%d/%d lines)", executable == 0 ? 100 : Double(covered) / Double(executable) * 100, covered, executable))
if !stale.isEmpty { print("Stale allowlist entries (remove them):"); stale.forEach { print("  " + $0) } }
if !gaps.isEmpty { print("\(gaps.count) functions are not fully covered:"); gaps.forEach { print("  " + $0) } }
if gaps.isEmpty && stale.isEmpty { print("Every function outside the allowlist is 100% line-covered.") }
exit(gaps.isEmpty && stale.isEmpty ? 0 : 1)
