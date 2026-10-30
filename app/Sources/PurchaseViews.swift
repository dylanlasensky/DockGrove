import SwiftUI
import StoreKit

struct PurchaseSettingsView: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var expandedTier: AccessTier?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose what belongs in your Dock").font(.title3.bold())
                    Text("One-time purchases. No subscription.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(purchases.hasLoadedEntitlements ? purchases.tier.title + " active" : "Checking purchases…")
                    .font(.caption.weight(.medium)).padding(8).background(Color.accentColor.opacity(0.1), in: Capsule())
            }
            HStack(alignment: .top, spacing: 12) {
                tierCard(.free)
                tierCard(.plus)
                tierCard(.full)
            }
            if let tier = expandedTier {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(tier == .free ? "Your everyday essentials" : tier == .plus ? "Everything added with Plus" : "Everything added with Full Access").font(.headline)
                        Spacer()
                        Button("Collapse") { expandedTier = nil }
                    }
                    Text(tier == .free ? "App launching, the clock, color packs, widget shapes, and layout controls are included." : tier == .plus ? "Includes everything in Free, plus these widgets." : "Includes everything in Plus, plus these widgets and Codex usage.")
                        .font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(ToolKind.allCases.filter { $0.requiredAccess == tier }) { kind in
                            Label(kind.title, systemImage: kind.icon).font(.caption)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).padding(8)
                                .background(tint(tier).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }
                        if tier == .full {
                            Label("Codex usage", systemImage: "chart.bar").font(.caption)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).padding(8)
                                .background(tint(tier).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            }
            Text("Third-party accounts or subscriptions may be required for connected services.")
                .font(.caption).foregroundStyle(.secondary)
            if purchases.tier == .plus {
                Text("Full Access is a separate one-time purchase. Your Plus payment is not credited toward it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Restore Purchases") { Task { await purchases.restore() } }.disabled(purchases.busy)
                if purchases.products.count < AccessTier.productIDs.count {
                    Button("Reload prices") { Task { await purchases.loadProducts() } }.disabled(purchases.loadingProducts || purchases.busy)
                }
                if purchases.busy || purchases.loadingProducts { ProgressView().controlSize(.small) }
            }
            if let message = purchases.message {
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Purchase status: " + message)
            }
        }.task { await purchases.load() }
    }

    private func tint(_ tier: AccessTier) -> Color { tier == .free ? .secondary : tier == .plus ? .blue : .purple }
    private func features(_ tier: AccessTier) -> [(String, String)] {
        switch tier {
        case .free: return [("App launching & search", "magnifyingglass"), ("Focus timer & tasks", "timer"), ("Clock & date", "clock"), ("Colors, shapes & layouts", "paintpalette")]
        case .plus: return [("Everything in Free", "checkmark.circle"), ("Weather & calendars", "cloud.sun"), ("Music & audio controls", "music.note"), ("Notes, files & clipboard", "doc.on.clipboard"), ("System & productivity tools", "gauge.with.dots.needle.50percent")]
        case .full: return [("Everything in Plus", "checkmark.circle"), ("All animated companions", "cat"), ("GitHub activity", "chevron.left.forwardslash.chevron.right"), ("Codex & CLI usage", "terminal"), ("API & team usage widgets", "chart.bar")]
        }
    }
    private func tierCard(_ tier: AccessTier) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: tier == .free ? "leaf" : tier == .plus ? "square.grid.2x2" : "sparkles").font(.title2).foregroundStyle(tint(tier))
                Spacer()
                if purchases.hasLoadedEntitlements && purchases.tier == tier {
                    Text("CURRENT").font(.system(size: 8, weight: .bold)).foregroundStyle(tint(tier))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(tier.title).font(.title2.bold())
                Text(tier == .free ? "A place to start" : tier == .plus ? "More for every day" : "The complete collection")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(tier == .free ? "Free" : purchases.product(for: tier)?.displayPrice ?? (purchases.loadingProducts ? "Loading…" : "Price unavailable"))
                    .font(.system(size: 24, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                Text(tier == .free ? "Included with DockGrove" : "One-time purchase").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(features(tier), id: \.0) { feature in
                    Label(feature.0, systemImage: feature.1).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            purchaseAction(tier).frame(maxWidth: .infinity, minHeight: 28)
            Button(expandedTier == tier ? "Hide included widgets" : "Explore included widgets") { expandedTier = expandedTier == tier ? nil : tier }
                .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(tint(tier))
                .accessibilityLabel("Explore " + tier.title + " included widgets")
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [tint(tier).opacity(0.09), Color(nsColor: .controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(tint(tier).opacity(purchases.tier == tier ? 0.65 : 0.2), lineWidth: purchases.tier == tier ? 1.5 : 1))
    }

    @ViewBuilder private func purchaseAction(_ tier: AccessTier) -> some View {
        if !purchases.hasLoadedEntitlements {
            Text("Checking purchases…").font(.caption).foregroundStyle(.secondary)
        } else if tier == .free || purchases.tier >= tier {
            Label(tier == .free ? "Included" : "Unlocked", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
        } else if let product = purchases.product(for: tier) {
            Button("Get " + tier.title) { Task { await purchases.purchase(tier) } }
                .buttonStyle(.borderedProminent).tint(tint(tier)).disabled(purchases.busy)
                .accessibilityLabel("Buy \(tier.title) for \(product.displayPrice), one time")
        } else {
            Text(purchases.loadingProducts ? "Loading price…" : "Currently unavailable").font(.caption).foregroundStyle(.secondary)
        }
    }
}
