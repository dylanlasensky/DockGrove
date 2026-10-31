import Foundation
@testable import DockGrove

@MainActor func runAISignInTests(fixture: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DockGrove Sign-in ' " + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func executable(_ name: String) throws -> String {
        let path = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(atPath: fixture, toPath: path.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        return path.path
    }
    let success = try executable("success"), denied = try executable("denied"), waiting = try executable("waiting")
    let signIn = AISignIn()
    var callbacks = 0
    func settle() async throws {
        for _ in 0..<150 {
            if !signIn.busy { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        preconditionFailure("Sign-in did not settle")
    }
    for provider in [AISignInProvider.codex, .claude] {
        for checkOnly in [false, true] {
            let before = callbacks
            signIn.start(provider, custom: success, checkOnly: checkOnly) { callbacks += 1 }
            try await settle()
            precondition(signIn.authenticated && callbacks == before + 1)
        }
    }
    print("PASS: Codex and Claude sign-in/status commands complete and refresh exactly once")
    signIn.start(.codex, custom: denied) { callbacks += 1 }
    try await settle()
    precondition(!signIn.authenticated && callbacks == 4)
    signIn.start(.claude, custom: waiting) { callbacks += 1 }
    signIn.start(.codex, custom: success) { callbacks += 1 }
    precondition(signIn.busy)
    signIn.cancel()
    try await Task.sleep(nanoseconds: 150_000_000)
    precondition(!signIn.busy && !signIn.authenticated && callbacks == 4)
    signIn.start(.codex, custom: success) { callbacks += 1 }
    try await settle()
    precondition(signIn.authenticated && callbacks == 5)
    print("PASS: refused login, duplicate start, cancel and retry do not refresh stale accounts")
    signIn.start(.claude, custom: waiting, timeout: 0.1) { callbacks += 1 }
    try await settle()
    precondition(!signIn.authenticated && callbacks == 5 && signIn.status.contains("timed out"))
    let broken = folder.appendingPathComponent("broken")
    try Data("not an executable".utf8).write(to: broken)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: broken.path)
    signIn.start(.claude, custom: broken.path) { callbacks += 1 }
    try await settle()
    precondition(!signIn.authenticated && !signIn.busy && callbacks == 5)
    print("PASS: timeout and failed process launch return to a retryable state")

    let fakeGemini = folder.appendingPathComponent("gemini ' test")
    let recorder = "#!/bin/zsh\n[[ $# == 0 && -z ${GEMINI_API_KEY+x} && -z ${GOOGLE_API_KEY+x} ]] || exit 2\n[[ $PWD == " + ClaudeStatusLineSetup.quote(folder.path) + " ]] || exit 3\n"
    try recorder.write(to: fakeGemini, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeGemini.path)
    let script = folder.appendingPathComponent("signin.command")
    try AICommand.geminiScript(executable: fakeGemini.path, directory: folder.path).write(to: script, atomically: true, encoding: .utf8)
    let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/zsh"); child.arguments = [script.path]
    child.environment = ["HOME": NSHomeDirectory(), "GEMINI_API_KEY": "fixture", "GOOGLE_API_KEY": "fixture"]
    child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
    try child.run(); child.waitUntilExit()
    precondition(child.terminationStatus == 0)
    precondition(AICommand.environment["OPENAI_API_KEY"] == nil && AICommand.environment["ANTHROPIC_API_KEY"] == nil)
    print("PASS: Gemini launch handles quoted paths, clears API overrides and sends no prompt")
}
