import SwiftUI

enum WidgetShapeStyle: String, CaseIterable, Codable, Identifiable {
    case rounded, square, circle, pill
    var id: String { rawValue }
    var title: String { switch self { case .rounded: return "Card"; case .square: return "Square"; case .circle: return "Circle"; case .pill: return "Pill" } }
    func width(height: Double) -> Double? {
        switch self { case .rounded: return nil; case .square, .circle: return height; case .pill: return max(140, height * 2.2) }
    }
    static func validated(_ values: [String: String]) -> [String: String] {
        values.filter { ToolKind(rawValue: $0.key) != nil && $0.key != "spacer" && $0.key != "separator" && WidgetShapeStyle(rawValue: $0.value) != nil }
    }
}

struct WidgetSilhouette: Shape {
    let style: WidgetShapeStyle
    func path(in rect: CGRect) -> Path {
        switch style {
        case .circle: return Circle().path(in: rect)
        case .square: return RoundedRectangle(cornerRadius: 5).path(in: rect)
        case .pill: return Capsule().path(in: rect)
        case .rounded: return RoundedRectangle(cornerRadius: 18).path(in: rect)
        }
    }
}

/// Small shapes get a purpose-built summary; the full widget opens on click.
struct ShapedWidgetFace: View {
    let kind: ToolKind
    let style: WidgetShapeStyle
    let caption: String
    let accent: Color
    var animal = "Miso"
    var resting = false
    var weatherAttribution = false
    private var glyph: some View {
        Group {
            if kind == .pet { CatPortrait(resting: resting, animal: animal, accent: accent).frame(width: 40, height: 35) }
            else { Image(systemName: kind.icon).font(.system(size: 20, weight: .medium)).foregroundStyle(accent) }
        }
    }
    var body: some View {
        Group {
            if style == .pill {
                HStack(spacing: 10) {
                    glyph
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                        Text(caption).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                        attribution
                    }
                }.padding(.horizontal, 15)
            } else {
                VStack(spacing: 3) {
                    glyph
                    Text(caption).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, style == .circle ? 9 : 5)
                    attribution
                }.padding(.vertical, 6)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WidgetSilhouette(style: style).fill(LinearGradient(colors: [accent.opacity(0.16), Color.primary.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(WidgetSilhouette(style: style).stroke(Color.primary.opacity(0.14), lineWidth: 0.7))
            .clipShape(WidgetSilhouette(style: style)).contentShape(WidgetSilhouette(style: style))
    }
    @ViewBuilder private var attribution: some View {
        if weatherAttribution { Label("Weather", systemImage: "apple.logo").font(.system(size: 6)) }
    }
}

extension Toolkit {
    func shape(for kind: ToolKind) -> WidgetShapeStyle { WidgetShapeStyle(rawValue: widgetShapes[kind.rawValue] ?? "") ?? .rounded }
}

extension DockModel {
    func setWidgetShape(_ shape: WidgetShapeStyle, for kind: ToolKind) {
        guard kind != .spacer, kind != .separator, toolkit.shape(for: kind) != shape else { return }
        objectWillChange.send()
        rememberStudioLayout()
        toolkit.widgetShapes[kind.rawValue] = shape.rawValue
    }
    func studioItem(_ entry: DockEntry) -> DockStudioItem? {
        guard var item = DockStudioItem(entry) else { return nil }
        if case .tool(let kind) = entry { item.shape = toolkit.shape(for: kind).rawValue }
        return item
    }
}
