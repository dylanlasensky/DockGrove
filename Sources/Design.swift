import AppKit
import SwiftUI

/// Exact owner-supplied DockGrove artwork, bundled once for all native surfaces.
struct BrandIcon: View {
    var body: some View {
        Image(nsImage: Self.artwork).resizable().scaledToFit().accessibilityLabel("DockGrove")
    }
    static let artwork: NSImage = {
        guard let url = Bundle.main.url(forResource:"DockGrove-icon",withExtension:"png"), let image=NSImage(contentsOf:url) else {
            return NSImage(size:NSSize(width:32,height:32))
        }
        return image
    }()
}
enum AccentPalette {
    static let names = ["None", "White", "Mint", "Blue", "Lilac", "Coral", "Rose", "Gold"]
    static func color(_ value: String) -> Color {
        switch value {
        case "None": return .primary
        case "White": return .white
        case "Mint": return Color(red: 0.43, green: 0.88, blue: 0.73)
        case "Blue": return Color(red: 77/255, green: 131/255, blue: 232/255)
        case "Lilac": return Color(red: 0.76, green: 0.65, blue: 1)
        case "Coral": return Color(red: 1, green: 0.57, blue: 0.47)
        case "Rose": return Color(red: 1, green: 0.52, blue: 0.69)
        case "Gold": return Color(red: 0.97, green: 0.78, blue: 0.38)
        default:
            guard let rgb = rgb(value) else { return .white }
            return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
        }
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
