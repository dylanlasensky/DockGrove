import SwiftUI
import AppKit

enum StudioAIProvider: String, CaseIterable, Identifiable {
    case openai, claude, gemini, cursor
    var id: String { rawValue }
    var title: String { switch self { case .openai: return "OpenAI"; case .claude: return "Claude"; case .gemini: return "Gemini"; case .cursor: return "Cursor" } }
    var icon: FontAwesomeIcon { switch self { case .openai: return .openAI; case .claude: return .claude; case .gemini: return .google; case .cursor: return .code } }
    var kind: ToolKind? { switch self { case .openai: return nil; case .claude: return .claudeCodeUsage; case .gemini: return .geminiUsage; case .cursor: return .cursorUsage } }
    init?(kind: ToolKind) {
        switch kind {
        case .openaiUsage: self = .openai
        case .claudeCodeUsage, .anthropicUsage: self = .claude
        case .geminiUsage: self = .gemini
        case .cursorUsage: self = .cursor
        default: return nil
        }
    }
    func supports(_ method: AIConnectionMethod) -> Bool {
        !(self == .gemini && method == .token) && !(self == .cursor && method == .cli)
    }
}
enum AIConnectionMethod: String, CaseIterable, Identifiable {
    case signIn = "Sign in", token = "API token", cli = "Use CLI"
    var id: String { rawValue }
    var icon: FontAwesomeIcon { switch self { case .signIn: return .account; case .token: return .key; case .cli: return .code } }
}

struct AIConnectionSettings: View {
    @ObservedObject var model: DockModel
    let provider: StudioAIProvider
    @State private var method: AIConnectionMethod
    init(model: DockModel, provider: StudioAIProvider, initialMethod: AIConnectionMethod) {
        self.model = model; self.provider = provider
        _method = State(initialValue: initialMethod)
    }
    private var apiWidget: AIUsageWidget? {
        switch provider { case .openai: return model.toolkit.openaiUsage; case .claude: return model.toolkit.anthropicUsage; case .cursor: return model.toolkit.cursorUsage; case .gemini: return nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FontAwesomeLabel(provider.title, icon: provider.icon).font(.headline)
            HStack(spacing: 6) {
                ForEach(AIConnectionMethod.allCases) { item in
                    Button { method = item } label: {
                        FontAwesomeLabel(item.rawValue, icon: item.icon)
                            .font(.callout).padding(.horizontal, 13).padding(.vertical, 9)
                            .background(method == item ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                        .disabled(!provider.supports(item))
                        .accessibilityAddTraits(method == item ? .isSelected : [])
                        .help(provider.supports(item) ? item.rawValue : "This method does not expose usage for \(provider.title).")
                }
            }.padding(4).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            if method == .token, let widget = apiWidget {
                CompactAPITokenSetup(widget: widget)
            } else {
                switch provider {
                case .openai:
                    CompactCLISetup(signIn: model.codexSignIn, provider: .codex, useCLI: method == .cli, custom: model.customCLI) {
                        model.reloadSignedInUsage()
                    }
                    CompactCodexUsage(model: model)
                    DisclosureGroup("Options") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Codex executable (automatic)", text: $model.customCLI).textFieldStyle(.roundedBorder)
                            Toggle("Auto-refresh", isOn: $model.usageEnabled)
                            Button("Refresh usage") { model.refreshUsage() }.disabled(model.fetching)
                            Link("Install or configure Codex", destination: AISignInProvider.codex.setupURL)
                            Text("Uses Codex on this Mac. Account changes also apply to Codex.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 10)
                    }
                case .claude:
                    CompactClaudeSetup(widget: model.toolkit.claudeCodeUsage, useCLI: method == .cli)
                case .gemini:
                    CompactGeminiSetup(widget: model.toolkit.geminiUsage, useCLI: method == .cli)
                case .cursor:
                    Text("View usage on Cursor. Add a team token to show it here.").font(.callout).foregroundStyle(.secondary)
                    Link(destination: model.toolkit.cursorUsage.provider.accountURL) {
                        FontAwesomeLabel("Continue to Cursor", icon: .externalLink)
                    }.buttonStyle(.bordered).foregroundStyle(.primary)
                }
            }
        }
    }
}

private struct CompactCLISetup: View {
    @ObservedObject var signIn: AISignIn
    let provider: AISignInProvider
    let useCLI: Bool
    var custom = ""
    var onSuccess: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(useCLI ? "Read usage from your signed-in \(provider == .codex ? "Codex" : "Claude Code")." : "Browser sign-in through \(provider == .codex ? "Codex" : "Claude Code") on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if signIn.busy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { signIn.cancel() }
                } else {
                    Button { signIn.start(provider, custom: custom, checkOnly: useCLI, onSuccess: onSuccess) } label: {
                        FontAwesomeLabel(useCLI ? "Use CLI" : "Sign in", icon: useCLI ? .code : provider == .codex ? .openAI : .claude)
                    }.buttonStyle(.bordered)
                }
                if signIn.authenticated { Label("Connected", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            }
            if !signIn.authenticated && signIn.status != AISignIn.initialStatus {
                Text(signIn.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CompactCodexUsage: View {
    @ObservedObject var model: DockModel
    var body: some View {
        if let usage = model.usage {
            VStack(alignment: .leading, spacing: 12) {
                Text("Codex plan limits").font(.subheadline.weight(.semibold))
                ForEach(usage.buckets, id: \.0) { _, bucket in
                    if usage.buckets.count > 1 { Text(bucket.title).font(.caption) }
                    if let window = bucket.primary { MiniMeter(window: window, color: model.color); Text(window.resetDescription).font(.caption).foregroundStyle(.secondary) }
                    if let window = bucket.secondary { MiniMeter(window: window, color: model.color); Text(window.resetDescription).font(.caption).foregroundStyle(.secondary) }
                }
                if let refreshed = model.refreshed { Text("Updated " + refreshed.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            }
        }
        if let error = model.usageError { Text(error).font(.caption).foregroundStyle(.secondary) }
    }
}

private struct CompactAPITokenSetup: View {
    @ObservedObject var widget: AIUsageWidget
    @State private var token = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(widget.provider == .cursor ? "Team admin token · last 7 days" : "Organization admin token · API usage, last 7 days")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                SecureField("Paste API token", text: $token).textFieldStyle(.roundedBorder).onSubmit(save)
                Button(action: save) { FontAwesomeLabel("Save", icon: .key) }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || widget.busy)
            }
            if widget.busy { ProgressView().controlSize(.small) }
            if let report = widget.snapshot {
                ForEach(report.totals.indices, id: \.self) { i in
                    HStack { Text(widget.provider.labels[i]); Spacer(); Text(report.totals[i].formatted()).monospacedDigit() }
                }
            }
            if !widget.status.isEmpty { Text(widget.status).font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Options") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-refresh hourly", isOn: $widget.autoRefresh)
                    Button("Refresh saved token", action: widget.refresh).disabled(widget.busy)
                    Link("Get an admin token", destination: widget.provider.accountURL)
                    Button("Remove saved token", action: widget.forget)
                    Text("Stored in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
        }.onDisappear { token = "" }
    }
    private func save() {
        guard !widget.busy, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        widget.connect(token); token = ""
    }
}

private struct CompactClaudeSetup: View {
    @ObservedObject var widget: LocalAIWidget
    let useCLI: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CompactCLISetup(signIn: widget.signIn, provider: .claude, useCLI: useCLI) {
                widget.clear(); widget.connectClaude()
            }
            if widget.report != nil { CompactLocalUsage(widget: widget) }
            else {
                Text(widget.status.isEmpty || widget.status.hasPrefix("No local report") ? "Usage appears after your next Claude Code response." : widget.status)
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Options") {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Enable usage capture", action: widget.connectClaude)
                    Button("Remove usage capture", action: widget.disconnectClaude)
                    Button("Clear saved usage", action: widget.clear)
                    Link("Install Claude Code", destination: AISignInProvider.claude.setupURL)
                    Text("Enables a status line without replacing custom settings. Limits update after a Claude Code response. Account changes also apply to Claude Code.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
        }.onAppear { widget.start() }
    }
}

private struct CompactGeminiSetup: View {
    @ObservedObject var widget: LocalAIWidget
    let useCLI: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if useCLI {
                Text("Import a Gemini CLI session to see token usage.").font(.callout).foregroundStyle(.secondary)
                Button(action: widget.importReport) { FontAwesomeLabel("Import usage", icon: .code) }.buttonStyle(.bordered)
            } else { GeminiSignInControls(compact: true, onImport: widget.importReport) }
            if widget.report != nil { CompactLocalUsage(widget: widget) }
            else if !widget.status.isEmpty && !widget.status.hasPrefix("No local report") {
                Text(widget.status).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Options") {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Import session JSON", action: widget.importReport)
                    Button("Copy capture command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("gemini --output-format json -p 'YOUR PROMPT' | " + ClaudeStatusLineSetup.quote(Bundle.main.executableURL!.path) + " --gemini-report", forType: .string)
                    }
                    Button("Clear saved usage", action: widget.clear)
                    Link("Install Gemini CLI", destination: URL(string: "https://geminicli.com/docs/get-started/installation/")!)
                    Text("Session tokens only. Gemini does not expose remaining plan usage through these API tokens.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
        }.onAppear { widget.start() }
    }
}

private struct CompactLocalUsage: View {
    @ObservedObject var widget: LocalAIWidget
    var body: some View {
        if let report = widget.report {
            VStack(alignment: .leading, spacing: 10) {
                Text(widget.provider == .claude ? "Claude Code limits" : "Latest Gemini session").font(.subheadline.weight(.semibold))
                if report.stale(at: Date()) { Label("Older reading", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                if widget.provider == .claude {
                    let windows = report.activeWindows(at: Date())
                    if windows.isEmpty { Text("No active limits reported.").font(.caption) }
                    ForEach(windows.indices, id: \.self) { i in
                        HStack { Text(windows[i].name); Spacer(); Text("\(Int(100 - windows[i].used))% left").monospacedDigit() }
                        ProgressView(value: 100 - windows[i].used, total: 100)
                        Text("Resets " + windows[i].resets.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(report.totalTokens.formatted() + " tokens").font(.title2).monospacedDigit()
                }
                Text(widget.status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
