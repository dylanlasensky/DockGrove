import SwiftUI

enum FontAwesomeIcon: String, CaseIterable {
    case openAI = "openai", claude, google, key
    case refresh = "arrows-rotate", close = "xmark", externalLink = "arrow-up-right-from-square"
    case purchase = "credit-card", play, pause, settings = "gear", account = "circle-user", code
    var assetName: String { "fa-" + rawValue }
    static func provider(_ kind: ToolKind) -> FontAwesomeIcon? {
        switch kind {
        case .claudeCodeUsage, .anthropicUsage: return .claude
        case .geminiUsage: return .google
        case .openaiUsage: return .openAI
        case .cursorUsage: return .code
        default: return nil
        }
    }
}

struct FontAwesomeLabel: View {
    let title: String
    let icon: FontAwesomeIcon
    init(_ title: String, icon: FontAwesomeIcon) { self.title = title; self.icon = icon }
    var body: some View {
        HStack(spacing: 8) {
            Image(icon.assetName).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 15, height: 15).accessibilityHidden(true)
            Text(title)
        }
    }
}
