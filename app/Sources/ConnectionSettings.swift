import SwiftUI

private struct ConnectionSetupKey: EnvironmentKey { static let defaultValue = false }
private struct ConnectionSettingsActionKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var connectionSetupAllowed: Bool {
        get { self[ConnectionSetupKey.self] }
        set { self[ConnectionSetupKey.self] = newValue }
    }
    var connectionSettingsAction: () -> Void {
        get { self[ConnectionSettingsActionKey.self] }
        set { self[ConnectionSettingsActionKey.self] = newValue }
    }
}
struct ConnectionSettingsButton: View {
    @Environment(\.connectionSettingsAction) private var openSettings
    var body: some View { Button(action: openSettings) { Label("Connection settings", systemImage: "gearshape") } }
}

struct StudioConnections: View {
    @ObservedObject var model: DockModel
    private var available: [ToolKind] {
        [.appleMusic, .spotify, .calendar, .googleCalendar, .reminders, .claudeCodeUsage, .geminiUsage, .openaiUsage, .anthropicUsage, .cursorUsage].filter { model.canAccess($0) }
    }
    private var selected: ToolKind? {
        if model.codexConnectionSelected && model.canAccessAI { return nil }
        if let kind = model.connectionSettingsKind, available.contains(kind) { return kind }
        return available.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Manage app access and account setup here. Open the provider’s app or account settings when you need to sign in.").font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175))], spacing: 10) {
                if model.canAccessAI {
                    Button { model.codexConnectionSelected = true } label: {
                        Label("ChatGPT / Codex", systemImage: "sparkles").font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(model.codexConnectionSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(model.codexConnectionSelected ? .isSelected : [])
                }
                ForEach(available) { kind in
                    Button { model.codexConnectionSelected = false; model.connectionSettingsKind = kind } label: {
                        Label(kind.title, systemImage: kind.icon).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(selected == kind ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == kind ? .isSelected : [])
                }
            }
            if model.codexConnectionSelected && model.canAccessAI {
                CodexConnectionView(model: model)
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
