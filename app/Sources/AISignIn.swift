import AppKit
import SwiftUI

/// Uses each provider's installed CLI. Credentials and browser callbacks stay with that CLI.
enum AISignInProvider {
    case codex, claude
    var title: String { self == .codex ? "ChatGPT / Codex" : "Claude Code" }
    var arguments: [String] { self == .codex ? ["login"] : ["auth", "login", "--claudeai"] }
    var statusArguments: [String] { self == .codex ? ["login", "status"] : ["auth", "status"] }
    var setupURL: URL { URL(string: self == .codex ? "https://developers.openai.com/codex/cli/" : "https://code.claude.com/docs/en/setup")! }
    func executable(custom: String = "") -> String? {
        if self == .codex { return UsageClient.executable(custom: custom) }
        return AICommand.executable("claude", custom: custom)
    }
}

enum AICommand {
    static func executable(_ name: String, custom: String = "") -> String? {
        ([custom, NSHomeDirectory() + "/.local/bin/" + name, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name])
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }
    static var environment: [String: String] {
        // Do not inherit API-key overrides that would silently select a different account.
        var result: [String: String] = [:]
        for name in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY"] {
            result[name] = ProcessInfo.processInfo.environment[name]
        }
        result["PATH"] = NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return result
    }
    static func geminiScript(executable: String, directory: String) -> String {
        """
        #!/bin/zsh
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        unset GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_GENAI_USE_VERTEXAI GOOGLE_GENAI_USE_GCA
        cd -- \(ClaudeStatusLineSetup.quote(directory)) || exit 1
        printf '%s\\n' 'Choose Sign in with Google in Gemini. If already signed in, use /auth to change accounts.' 'Exit Gemini when finished, then import a session report in DockGrove.'
        exec \(ClaudeStatusLineSetup.quote(executable))

        """
    }
}

@MainActor final class AISignIn: ObservableObject {
    @Published private(set) var busy = false
    static let initialStatus = "Use an existing CLI account, or sign in below."
    @Published private(set) var status = AISignIn.initialStatus
    @Published private(set) var authenticated = false
    private var process: Process?
    private var timeoutTask: Task<Void, Never>?
    private var generation = 0

    func start(_ provider: AISignInProvider, custom: String = "", checkOnly: Bool = false,
               timeout: TimeInterval? = nil, onSuccess: @escaping () -> Void = {}) {
        guard !busy else { return }
        guard let path = provider.executable(custom: custom) else {
            authenticated = false
            status = "Install \(provider.title) to continue."
            return
        }
        authenticated = false
        generation += 1
        let request = generation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = checkOnly ? provider.statusArguments : provider.arguments
        child.environment = AICommand.environment
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        child.standardInput = FileHandle.nullDevice
        // No auth URLs, tokens, email addresses or other CLI output enter app logs.
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] child in
            let successful = child.terminationReason == .exit && child.terminationStatus == 0
            Task { @MainActor [weak self] in
                guard let self, self.generation == request else { return }
                self.timeoutTask?.cancel(); self.timeoutTask = nil
                self.process = nil; self.busy = false; self.authenticated = successful
                self.status = successful ? "CLI account signed in. Usage availability depends on your plan." :
                    (checkOnly ? "No signed-in CLI account found." : "Sign-in did not complete. Try again.")
                if successful { onSuccess() }
            }
        }
        do {
            try child.run()
            process = child; busy = true; authenticated = false
            status = checkOnly ? "Checking CLI account…" : "Finish signing in in your browser. Waiting for \(provider.title)…"
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((timeout ?? (checkOnly ? 20 : 300)) * 1_000_000_000))
                guard !Task.isCancelled, let self, self.generation == request, self.busy else { return }
                self.cancel(message: "Sign-in timed out. Try again.")
            }
        } catch { status = "Could not open \(provider.title). Check CLI setup." }
    }
    func cancel(message: String = "Stopped waiting for sign-in. Your existing CLI account has not been signed out.") {
        generation += 1; timeoutTask?.cancel(); timeoutTask = nil
        if let child = process, child.isRunning {
            child.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil; busy = false; authenticated = false; status = message
    }
    deinit { timeoutTask?.cancel(); if let process, process.isRunning { process.terminate() } }
}

struct AISignInControls: View {
    @ObservedObject var signIn: AISignIn
    let provider: AISignInProvider
    var custom = ""
    var onSuccess: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(signIn.status, systemImage: signIn.authenticated ? "checkmark.circle" : "person.crop.circle")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                if signIn.busy {
                    ProgressView().controlSize(.small)
                    Button { signIn.cancel() } label: { FontAwesomeLabel("Cancel sign-in", icon: .close) }
                } else {
                    Button { signIn.start(provider, custom: custom, onSuccess: onSuccess) } label: {
                        FontAwesomeLabel("Sign in with \(provider.title)", icon: provider == .codex ? .openAI : .claude)
                    }.buttonStyle(.bordered)
                    Button { signIn.start(provider, custom: custom, checkOnly: true, onSuccess: onSuccess) } label: { FontAwesomeLabel("Use existing sign-in", icon: .key) }
                }
                Link(destination: provider.setupURL) { FontAwesomeLabel("CLI setup", icon: .externalLink) }.foregroundStyle(.primary)
            }
            Text("Sign-in uses your browser and the provider’s CLI on this Mac. Changing accounts also changes that CLI’s account. DockGrove does not collect your password.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CodexConnectionView: View {
    @ObservedObject var model: DockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ChatGPT / Codex").font(.headline)
            Text("View the allowance windows reported by Codex. This does not include all ChatGPT message limits.").font(.callout).foregroundStyle(.secondary)
            AISignInControls(signIn: model.codexSignIn, provider: .codex, custom: model.customCLI) { model.reloadSignedInUsage() }
            TextField("Codex executable (auto-detected)", text: $model.customCLI).textFieldStyle(.roundedBorder).disabled(model.codexSignIn.busy)
            Toggle("Refresh usage automatically", isOn: $model.usageEnabled)
            UsageDetails(model: model, showAccountSettings: false)
        }
    }
}

struct GeminiSignInControls: View {
    var compact = false
    var onImport: () -> Void = {}
    @State private var opened = false
    @State private var status = "Google sign-in is managed by the Gemini CLI in Terminal."
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                Text(opened ? "Finish Google sign-in, then import a session report." : "Google sign-in through Gemini CLI in Terminal.").font(.callout).foregroundStyle(.secondary)
                Button(action: opened ? onImport : openGemini) {
                    FontAwesomeLabel(opened ? "Import usage" : "Sign in", icon: opened ? .code : .google)
                }.buttonStyle(.bordered)
                if status != "Google sign-in is managed by the Gemini CLI in Terminal." && !opened { Text(status).font(.caption).foregroundStyle(.secondary) }
            } else {
            Text(status).font(.callout)
            HStack {
                Button(action: openGemini) { FontAwesomeLabel("Sign in with Google in Gemini…", icon: .google) }.buttonStyle(.bordered)
                Link("Install Gemini CLI", destination: URL(string: "https://geminicli.com/docs/get-started/installation/")!)
            }
            Text("Choose Sign in with Google, or /auth to change accounts. After signing in, import a session report below to show usage. Signing in alone does not provide a live remaining-quota feed.")
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func openGemini() {
        guard let executable = AICommand.executable("gemini") else { status = "Install Gemini CLI first, then return here to sign in."; return }
        do {
            let folder = BrandStorage.supportDirectory.appendingPathComponent("Gemini Sign In", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = folder.appendingPathComponent("Sign in to Gemini.command")
            try AICommand.geminiScript(executable: executable, directory: folder.path).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open([script], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async { opened = error == nil; status = error == nil ? "Continue in Terminal, then import a usage report below." : "Could not open Terminal. Run gemini manually to sign in." }
            }
        } catch { status = "Could not prepare Gemini sign-in. Run gemini in Terminal to sign in." }
    }
}
