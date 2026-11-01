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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175))], spacing: 10) {
                if access.canAccessAI(model) {
                    ForEach(StudioAIProvider.allCases) { provider in
                        Button {
                            model.codexConnectionSelected = provider == .openai
                            if let kind = provider.kind { model.connectionSettingsKind = kind }
                        } label: {
                            FontAwesomeLabel(provider.title, icon: provider.icon).font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(selectedAI == provider ? Color.primary.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityAddTraits(selectedAI == provider ? .isSelected : [])
                    }
                }
                ForEach(available) { kind in
                    Button { model.codexConnectionSelected = false; model.connectionSettingsKind = kind } label: {
                        Group {
                            if let icon = FontAwesomeIcon.provider(kind) { FontAwesomeLabel(kind.title, icon: icon) }
                            else { Label(kind.title, systemImage: kind.icon) }
                        }.font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(selected == kind ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == kind ? .isSelected : [])
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
