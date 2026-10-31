import AppKit
import SwiftUI

/// Exact owner-supplied DockGrove artwork, bundled once for all native surfaces.
struct BrandIcon: View {
    var body: some View {
        Image(nsImage: Self.artwork).resizable().scaledToFit().accessibilityLabel("DockGrove")
    }
    static let artwork: NSImage = loadArtwork("DockGrove-icon")
    static func loadArtwork(_ name: String) -> NSImage { NSImage(named: name) ?? NSImage(size: NSSize(width: 32, height: 32)) }
}
enum AccentPalette {
    static let names = ["None", "White", "Mint", "Blue", "Lilac", "Coral", "Rose", "Gold"]
    struct Pack: Identifiable {
        let name: String
        let group: String
        let mood: String
        let colors: [String]
        var id: String { name }
    }
    static let groups = ["All", "Essentials", "Nature", "Soft", "Vivid", "Earth", "Seasonal"]
    static let packs: [Pack] = [
        Pack(name: "Classic", group: "Essentials", mood: "The original DockGrove accents", colors: names),
        Pack(name: "Coastal", group: "Nature", mood: "Ocean blues and sandy shores", colors: ["Coastal Ocean", "Coastal Seafoam", "Coastal Sand", "Coastal Sky"]),
        Pack(name: "Orchard", group: "Nature", mood: "Fresh fruit and garden greens", colors: ["Orchard Leaf", "Orchard Peach", "Orchard Berry", "Orchard Honey"]),
        Pack(name: "Dusk", group: "Soft", mood: "Muted evening colors", colors: ["Dusk Violet", "Dusk Indigo", "Dusk Ember", "Dusk Mauve"]),
        Pack(name: "Forest", group: "Nature", mood: "Deep greens and woodland tones", colors: ["Forest Fern", "Forest Moss", "Forest Pine", "Forest Bark", "Forest Mist", "Forest Clover"]),
        Pack(name: "Arctic", group: "Nature", mood: "Cool blues and glacier tones", colors: ["Arctic Glacier", "Arctic Ice", "Arctic Fjord", "Arctic Polar", "Arctic Lagoon", "Arctic Periwinkle"]),
        Pack(name: "Sorbet", group: "Soft", mood: "Gentle fruit-inspired pastels", colors: ["Sorbet Peach", "Sorbet Lemon", "Sorbet Pistachio", "Sorbet Lilac", "Sorbet Melon", "Sorbet Blueberry"]),
        Pack(name: "Blossom", group: "Soft", mood: "Florals, rosewater and soft jade", colors: ["Blossom Sakura", "Blossom Wisteria", "Blossom Rosewater", "Blossom Jade", "Blossom Petal", "Blossom Iris"]),
        Pack(name: "Neon", group: "Vivid", mood: "Electric accents with high energy", colors: ["Neon Lime", "Neon Cyan", "Neon Pink", "Neon Violet", "Neon Orange", "Neon Laser"]),
        Pack(name: "Arcade", group: "Vivid", mood: "Bold retro game colors", colors: ["Arcade Magenta", "Arcade Azure", "Arcade Aqua", "Arcade Coin", "Arcade Cherry", "Arcade Plum"]),
        Pack(name: "Desert", group: "Earth", mood: "Sand, terracotta and sunset stone", colors: ["Desert Terracotta", "Desert Dune", "Desert Clay", "Desert Cactus", "Desert Oasis", "Desert Sunset"]),
        Pack(name: "Coffee", group: "Earth", mood: "Warm cafe neutrals", colors: ["Coffee Espresso", "Coffee Latte", "Coffee Mocha", "Coffee Caramel", "Coffee Matcha", "Coffee Cream"]),
        Pack(name: "Slate", group: "Earth", mood: "Quiet mineral and monochrome tones", colors: ["Slate Graphite", "Slate Steel", "Slate Pebble", "Slate Silver", "Slate Basalt", "Slate Sage"]),
        Pack(name: "Autumn", group: "Seasonal", mood: "Harvest reds and golden leaves", colors: ["Autumn Maple", "Autumn Amber", "Autumn Cranberry", "Autumn Pumpkin", "Autumn Olive", "Autumn Chestnut"]),
        Pack(name: "Aurora", group: "Nature", mood: "Northern lights after dark", colors: ["Aurora Mint", "Aurora Teal", "Aurora Indigo", "Aurora Orchid", "Aurora Dawn", "Aurora Emerald"]),
        Pack(name: "Festive", group: "Seasonal", mood: "Jewel tones and celebration", colors: ["Festive Ruby", "Festive Emerald", "Festive Gold", "Festive Sapphire", "Festive Amethyst", "Festive Copper"])
    ]
    static func assetName(_ name: String) -> String {
        if name == "None" { return "AccentNeutral" }
        if names.contains(name) { return "Accent" + name }
        return name.replacingOccurrences(of: " ", with: "")
    }
    static func color(_ value: String) -> Color {
        if let named = NSColor(named: assetName(value)) { return Color(nsColor: named) }
        guard let rgb = rgb(value) else { return value == "None" ? .primary : .white }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    static func rgb(_ hex: String) -> UInt32? {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt32(value, radix: 16)
    }
    static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
struct WidgetSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content.background(LinearGradient(colors: [Color.primary.opacity(opaque ? 0.14 : 0.075), Color.primary.opacity(opaque ? 0.12 : 0.035)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.7))
    }
}
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var body: some View {
        GeometryReader { g in
            Path { p in
                let peak = max(1, values.max() ?? 1)
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: g.size.width * Double(i) / Double(max(1, values.count - 1)), y: g.size.height * (1 - max(0, v) / peak))
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}
struct RingMetric: View {
    var value: Double
    var label: String
    var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: 4)
            Circle().trim(from: 0, to: min(1, max(0, value))).stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(label).font(.system(size: 17, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.7)
        }.padding(4)
    }
}

extension BrandIcon {
    static var menuImage: NSImage {
        let image = NSImage(size:NSSize(width:20,height:20),flipped:false) { bounds in
            artwork.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1)
            return true
        }
        image.isTemplate=false
        image.accessibilityDescription="DockGrove"
        return image
    }
}

struct DockPlate: View {
    var theme: String
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *), !opaque, theme != "Graphite" {
                NativeDockGlass()
            } else { RoundedRectangle(cornerRadius: 27).fill(.ultraThinMaterial) }
            #else
            RoundedRectangle(cornerRadius: 27).fill(.ultraThinMaterial)
            #endif
        }

            .overlay { if theme == "Graphite" || opaque { RoundedRectangle(cornerRadius:27).fill(Color(nsColor:.windowBackgroundColor)) } }
            .overlay(RoundedRectangle(cornerRadius:27).stroke(Color.primary.opacity(contrast == .increased ? 0.6 : 0.12)))
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
struct NativeDockGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView(); view.cornerRadius = 27; view.style = .regular
        return view
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = 27
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
    }
}

#endif
