import SwiftUI

private struct ConnectionSetupKey: EnvironmentKey { static let defaultValue = false }
private struct ConnectionSettingsActionKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
/// Purchase access the Studio settings consult. Production reads the model's StoreKit-derived
/// access; injecting another value renders the screens for a given purchase state.
struct StudioAccess {
    var purchasesEnabled = PurchaseConfiguration.enabled
    var canUseFeatures: @MainActor (DockModel) -> Bool
    var canAccess: @MainActor (DockModel, ToolKind) -> Bool
    var canAccessAI: @MainActor (DockModel) -> Bool
    static let live = StudioAccess(canUseFeatures: { $0.canUseFeatures }, canAccess: { $0.canAccess($1) }, canAccessAI: { $0.canAccessAI })
}
private struct StudioAccessKey: EnvironmentKey { static let defaultValue = StudioAccess.live }
extension EnvironmentValues {
    var connectionSetupAllowed: Bool {
        get { self[ConnectionSetupKey.self] }
        set { self[ConnectionSetupKey.self] = newValue }
    }
    var connectionSettingsAction: () -> Void {
        get { self[ConnectionSettingsActionKey.self] }
        set { self[ConnectionSettingsActionKey.self] = newValue }
    }
    var studioAccess: StudioAccess {
        get { self[StudioAccessKey.self] }
        set { self[StudioAccessKey.self] = newValue }
    }
}
struct ConnectionSettingsButton: View {
    @Environment(\.connectionSettingsAction) private var openSettings
    var body: some View { Button(action: openSettings) { Label("Connection settings", systemImage: "gearshape") } }
}

struct StudioConnections: View {
    @ObservedObject var model: DockModel
    @Environment(\.studioAccess) private var access
    private var available: [ToolKind] {
        [.appleMusic, .spotify, .calendar, .googleCalendar, .reminders].filter { access.canAccess(model, $0) }
    }
    private var selectedAI: StudioAIProvider? {
        guard access.canAccessAI(model) else { return nil }
        if model.codexConnectionSelected { return .openai }
        return model.connectionSettingsKind.flatMap { StudioAIProvider(kind: $0) }
    }
    private var selected: ToolKind? {
        if selectedAI != nil { return nil }
        if let kind = model.connectionSettingsKind, available.contains(kind) { return kind }
        return available.first
    }
    private var initialMethod: AIConnectionMethod {
        if model.codexConnectionSelected { return .signIn }
        return [.openaiUsage, .anthropicUsage, .cursorUsage].contains(model.connectionSettingsKind) ? .token : .signIn
    }
    @ViewBuilder private func aiStatus(_ provider: StudioAIProvider) -> some View {
        switch provider {
        case .openai:
            ConnectionSummary(model: model) { $0.usageError ?? ($0.usage == nil ? "ChatGPT account: not checked" : "ChatGPT usage received") }
        case .claude:
            ConnectionSummary(model: model.toolkit.claudeCodeUsage) { $0.status.isEmpty ? ($0.report == nil ? "Local account: not checked" : "Local usage received") : $0.status }
        case .gemini:
            ConnectionSummary(model: model.toolkit.geminiUsage) { $0.status.isEmpty ? ($0.report == nil ? "Local account: not checked" : "Local usage received") : $0.status }
        case .cursor:
            ConnectionSummary(model: model.toolkit.cursorUsage) { $0.status.isEmpty ? ($0.snapshot == nil ? "API usage: not checked" : "API usage received") : $0.status }
        }
    }
    @ViewBuilder private func serviceStatus(_ kind: ToolKind) -> some View {
        switch kind {
        case .appleMusic: ConnectionSummary(model: model.toolkit.appleMusic) { $0.status }
        case .spotify: ConnectionSummary(model: model.toolkit.spotify) { $0.status }
        case .calendar: ConnectionSummary(model: model.toolkit.calendar) { $0.status }
        case .googleCalendar: ConnectionSummary(model: model.toolkit.googleCalendar) { $0.status }
        case .reminders: ConnectionSummary(model: model.toolkit.utilities) { $0.remindersStatus }
        default: EmptyView()
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175))], spacing: 10) {
                if access.canAccessAI(model) {
                    ForEach(StudioAIProvider.allCases) { provider in
                        Button {
                            model.codexConnectionSelected = provider == .openai
                            if let kind = provider.kind { model.connectionSettingsKind = kind }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                FontAwesomeLabel(provider.title, icon: provider.icon).font(.callout)
                                aiStatus(provider)
                            }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(selectedAI == provider ? Color.primary.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("connection." + provider.rawValue).accessibilityAddTraits(selectedAI == provider ? .isSelected : [])
                    }
                }
                ForEach(available) { kind in
                    Button { model.codexConnectionSelected = false; model.connectionSettingsKind = kind } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Group {
                            if let icon = FontAwesomeIcon.provider(kind) { FontAwesomeLabel(kind.title, icon: icon) }
                            else { Label(kind.title, systemImage: kind.icon) }
                            }.font(.callout)
                            serviceStatus(kind)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(selected == kind ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("connection." + kind.rawValue).accessibilityAddTraits(selected == kind ? .isSelected : [])
                }
            }
            if let provider = selectedAI {
                AIConnectionSettings(model: model, provider: provider, initialMethod: initialMethod)
                    .id(provider.rawValue + initialMethod.rawValue)
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            } else if let kind = selected {
                VStack(alignment: .leading, spacing: 16) {
                    Label(kind.title, systemImage: kind.icon).font(.headline)
                    ToolTile(kind: kind, model: model, kit: model.toolkit).contents
                        .environment(\.connectionSetupAllowed, true)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("Your current widgets do not require an account connection.").foregroundStyle(.secondary)
            }
        }
    }
}

/// Observes the actual source without starting a connection or reading credentials.
private struct ConnectionSummary<Model: ObservableObject>: View {
    @ObservedObject var model: Model
    let summary: (Model) -> String
    var body: some View {
        Text(summary(model)).font(.caption).foregroundStyle(.secondary)
            .lineLimit(2).help(summary(model))
    }
}
