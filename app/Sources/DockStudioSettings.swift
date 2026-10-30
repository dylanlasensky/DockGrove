import SwiftUI
import AppKit

enum StudioSection: String, CaseIterable {
    case library = "Library", appearance = "Appearance", behavior = "Behavior", connections = "Connections", purchases = "Purchases"
    var icon: String {
        switch self { case .library: return "square.grid.2x2"; case .appearance: return "paintpalette"; case .behavior: return "slider.horizontal.3"; case .connections: return "person.crop.circle.badge.checkmark"; case .purchases: return "sparkles" }
    }
    var subtitle: String {
        switch self {
        case .library: return "A place for your everyday essentials."
        case .appearance: return "Make this little corner of your Mac feel like you."
        case .behavior: return "Choose how your Dock fits into your day."
        case .connections: return "App access and account setup in one place."
        case .purchases: return "More useful widgets. One simple purchase."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: DockModel
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var section: StudioSection = .library
    init(model: DockModel, section: StudioSection = .library) {
        self.model = model
        _section = State(initialValue: section)
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section == .library ? "Build your Dock" : section.rawValue).font(.system(size: 27, weight: .bold, design: .rounded))
                        Text(section.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { model.closeSettingsAction?() }.keyboardShortcut(.cancelAction)
                }
                if model.canUseFeatures && section != .purchases && section != .connections {
                    DockStudioPreview(model: model)
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Layout changes save immediately. Preview cards use sample content.")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    Group {
                        switch section {
                        case .library:
                            if model.canUseFeatures { StudioLibrary(model: model, openPurchases: { section = .purchases }) }
                            else { LicenseSettingsView() }
                        case .appearance:
                            if model.canUseFeatures { StudioAppearance(model: model) }
                        case .behavior:
                            if model.canUseFeatures { StudioBehavior(model: model) }
                        case .connections:
                            if model.canUseFeatures { StudioConnections(model: model) }
                        case .purchases:
                            if PurchaseConfiguration.enabled { PurchaseSettingsView() }
                            else { LicenseSettingsView() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading).padding(.bottom, 16)
                }.scrollIndicators(.visible)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 960, idealWidth: 1080, minHeight: 690, idealHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(model.scheme)
        .toggleStyle(.switch)
        .onReceive(model.$connectionSettingsKind) { kind in if kind != nil { section = .connections } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 9) { BrandIcon().frame(width: 32, height: 32); Text("DockGrove").font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.9) }
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR SPACE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 7)
                ForEach(StudioSection.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        Label(item.rawValue, systemImage: item.icon).font(.system(size: 13, weight: section == item ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                            .background(section == item ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(section == item ? Color.accentColor : .primary)
                    }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if PurchaseConfiguration.enabled {
                    Label(purchases.tier.title, systemImage: purchases.tier == .free ? "leaf" : "checkmark.seal.fill").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                if !model.isAdditionalDock { Button("Manage docks…") { model.manageDocksAction?() }.buttonStyle(.link) }
                Button("Restore Apple Dock") { model.changeDockAction?(false) }.buttonStyle(.link)
                Button("Quit DockGrove") { NSApp.terminate(nil) }.buttonStyle(.link)
                Text("Thoughtfully at hand.").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 10)
            }
        }.padding(18).frame(width: 200).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

private struct StudioLibrary: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    let openPurchases: () -> Void
    @State private var library = "Widgets"
    @State private var query = ""
    @State private var category = "All"
    init(model: DockModel, openPurchases: @escaping () -> Void) {
        self.model = model; kit = model.toolkit; self.openPurchases = openPurchases
    }
    private var widgets: [ToolKind] {
        ToolKind.allCases.filter { (category == "All" || $0.studioCategory == category) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    private var apps: [DockApp] {
        kit.applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Picker("Library", selection: $library) { Text("Widgets").tag("Widgets"); Text("Apps").tag("Apps") }.pickerStyle(.segmented).frame(width: 190)
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(library == "Widgets" ? "Find a widget" : "Find an app", text: $query).textFieldStyle(.plain) }
                    .padding(9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                if library == "Apps" { Button { kit.scanApplications(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(kit.scanningApps).help("Refresh installed apps") }
            }
            if library == "Widgets" {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(["All", "Everyday", "Productivity", "Media", "Developer", "Companions"], id: \.self) { value in
                            Button { category = value } label: {
                                Text(value).font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(category == value ? Color.primary.opacity(0.11) : .clear, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(category == value ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                if widgets.isEmpty { ContentUnavailableView.search(text: query) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 14)], spacing: 14) {
                    ForEach(widgets) { kind in
                        StudioWidgetCard(kind: kind, model: model, openPurchases: openPurchases)
                    }
                }
            } else {
                if kit.scanningApps { ProgressView("Finding your apps…").controlSize(.small) }
                if !kit.scanningApps && apps.isEmpty { ContentUnavailableView.search(text: query) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(apps) { app in
                        let pinned = model.apps.contains(app)
                        Button {
                            let item = DockStudioItem(kind: .app, value: app.id)
                            if pinned { _ = model.removeStudioItem(item) } else { _ = model.placeStudioItem(item) }
                        } label: {
                            VStack(spacing: 9) {
                                Image(nsImage: app.icon).resizable().frame(width: 44, height: 44)
                                Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(pinned ? "In your Dock" : "Drag to add").font(.system(size: 9)).foregroundStyle(pinned ? Color.accentColor : .secondary)
                            }.frame(maxWidth: .infinity).padding(14)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(pinned ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06)))
                        }.buttonStyle(.plain)
                            .overlay {
                                NativeStudioDragSource(item: DockStudioItem(kind: .app, value: app.id)) {
                                    let item = DockStudioItem(kind: .app, value: app.id)
                                    if pinned { _ = model.removeStudioItem(item) } else { _ = model.placeStudioItem(item) }
                                }
                            }
                            .accessibilityLabel((pinned ? "Remove " : "Add ") + app.name + " from Dock library")
                    }
                }
            }
        }.onChange(of: library) { _, value in if value == "Apps" { kit.scanApplications() } }
    }
}

private struct StudioWidgetCard: View {
    let kind: ToolKind
    @ObservedObject var model: DockModel
    let openPurchases: () -> Void
    private var enabled: Bool { model.toolkit.enabled.contains(kind.rawValue) && model.canAccess(kind) }
    private func activate() {
        guard model.canAccess(kind) else { openPurchases(); return }
        let item = model.studioItem(.tool(kind))!
        if enabled { _ = model.removeStudioItem(item) } else { _ = model.placeStudioItem(item) }
    }
    var body: some View {
        if model.canAccess(kind) {
            card.overlay { NativeStudioDragSource(item: model.studioItem(.tool(kind))!, clicked: activate) }
        } else { card }
    }
    private var card: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if model.toolkit.shape(for: kind) == .rounded { WidgetShowcase(kind: kind) }
                    else {
                        ShapedWidgetFace(kind: kind, style: model.toolkit.shape(for: kind), caption: kind == .focus ? "25:00" : kind == .weather ? "72°" : kind.title, accent: model.color)
                            .frame(width: CGFloat(model.toolkit.shape(for: kind).width(height: 72) ?? 174))
                            .frame(maxWidth: .infinity)
                    }
                }.frame(height: 72).allowsHitTesting(false)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(enabled ? "In your Dock" : model.canAccess(kind) ? "Drag or click to add" : kind.requiredAccess.title)
                            .font(.system(size: 10)).foregroundStyle(enabled ? Color.accentColor : .secondary)
                    }
                    Spacer(minLength: 3)
                    Image(systemName: enabled ? "checkmark.circle.fill" : model.canAccess(kind) ? "plus.circle" : "lock.fill")
                        .foregroundStyle(enabled ? Color.accentColor : .secondary).font(.system(size: 14))
                }
            }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(enabled ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityLabel(kind.title + (enabled ? ", in your Dock, click to remove" : model.canAccess(kind) ? ", drag or click to add" : ", requires " + kind.requiredAccess.title))
    }
}

private struct StudioAppearance: View {
    @ObservedObject var model: DockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Pick a mood").font(.headline)
            HStack(spacing: 12) {
                ForEach(["Automatic", "Glass", "Graphite", "Pearl"], id: \.self) { theme in
                    Button { model.theme = theme } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 5) { ForEach(0..<4) { i in RoundedRectangle(cornerRadius: 5).fill([Color.blue, .purple, .orange, .green][i].gradient).frame(width: 19, height: 23) } }
                                .padding(10).background(theme == "Pearl" ? Color.white.opacity(0.8) : theme == "Graphite" ? Color.black.opacity(0.8) : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 13))
                            Text(theme).font(.caption.weight(.medium))
                        }.frame(maxWidth: .infinity).padding(12).background(model.theme == theme ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.theme == theme ? Color.accentColor : .secondary.opacity(0.15)))
                    }.buttonStyle(.plain)
                }
            }
            if !model.isAdditionalDock { NotchSettingsView(model: model) }
            StudioToolbarSize(model: model)
            StudioWidgetShapes(model: model)
            StudioPanel(title: "Color") {
                StudioColorPacks(model: model)
                Toggle("Rich widget cards", isOn: Binding(get: { model.toolkit.richWidgets }, set: { model.toolkit.richWidgets = $0 }))
                Toggle("Use album colors in music widgets", isOn: $model.albumColors)
            }
            Text("Color packs adapt to light and dark appearance. Your custom color stays available.").font(.caption).foregroundStyle(.secondary)
            StudioPanel(title: "Position") {
                TextField("Dock name", text: $model.dockName).textFieldStyle(.roundedBorder)
                StudioNumberControl(title: "Horizontal position", value: $model.alignment, range: 0...1, step: 0.01, scale: 100, unit: "%")
                Picker("Edge", selection: Binding(get: { model.toolkit.edge }, set: { model.toolkit.edge = $0 })) {
                    Text("Bottom").tag("Bottom"); Text("Top").tag("Top"); Text("Floating").tag("Floating")
                }.pickerStyle(.segmented).disabled(model.replacingDock)
                if model.toolkit.edge == "Floating" { StudioNumberControl(title: "Vertical position", value: $model.elevation, range: 0...1, step: 0.01, scale: 100, unit: "%") }
            }
        }
    }
}

private struct StudioWidgetShapes: View {
    @ObservedObject var model: DockModel
    @State private var selected: ToolKind = .focus
    var body: some View {
        StudioPanel(title: "Widget shapes") {
            StudioChoiceControl(title: "Customize widget", selection: Binding(get: { selected.rawValue }, set: { selected = ToolKind(rawValue: $0) ?? .focus }), options: ToolKind.allCases.filter { $0 != .spacer && $0 != .separator }.map { StudioChoice(value: $0.rawValue, title: $0.title, icon: $0.icon) })
            HStack(spacing: 10) {
                ForEach(WidgetShapeStyle.allCases) { shape in
                    Button { model.setWidgetShape(shape, for: selected) } label: {
                        VStack(spacing: 8) {
                            WidgetSilhouette(style: shape).fill(model.color.opacity(0.2))
                                .overlay(Image(systemName: selected.icon).foregroundStyle(model.color))
                                .frame(width: shape.width(height: 48) == 48 ? 48 : 86, height: 48)
                            Text(shape.title).font(.caption.weight(.medium))
                        }.frame(maxWidth: .infinity).padding(10)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.toolkit.shape(for: selected) == shape ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: model.toolkit.shape(for: selected) == shape ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel(shape.title + " shape for " + selected.title)
                }
            }
            Text("Mix shapes on the same Dock. Compact shapes open the full widget when clicked. Right-click a Dock or preview widget to change its shape there.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StudioColorPacks: View {
    @ObservedObject var model: DockModel
    @State private var group = "All"
    @State private var selectedPack = "Classic"
    private var pack: AccentPalette.Pack {
        AccentPalette.packs.first { $0.name == selectedPack } ?? AccentPalette.packs[0]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Color collections").font(.headline)
                Spacer()
                Text("\(AccentPalette.packs.count) packs · \(AccentPalette.packs.reduce(0) { $0 + $1.colors.count }) colors")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(AccentPalette.groups, id: \.self) { category in
                        Button { group = category } label: {
                            Text(category).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(group == category ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06), in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(group == category ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
            Divider()
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.name + " accents").font(.callout.weight(.semibold))
                    Text(pack.colors.contains(model.accent) ? model.accent : "Custom accent").font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 100, alignment: .leading)
                Spacer(minLength: 0)
                ForEach(pack.colors, id: \.self) { name in
                    Button { model.accent = name } label: {
                        Circle().fill(AccentPalette.color(name)).frame(width: 23, height: 23).padding(3)
                            .overlay(Circle().stroke(model.accent == name ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 2))
                    }.buttonStyle(.plain).help(name).accessibilityLabel(name + " accent")
                        .accessibilityAddTraits(model.accent == name ? .isSelected : [])
                }
                ColorPicker("Custom", selection: Binding(get: { model.color }, set: { model.accent = AccentPalette.hex($0) }), supportsOpacity: false).labelsHidden().help("Choose a custom accent")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                ForEach(AccentPalette.packs.filter { group == "All" || $0.group == group }) { collection in
                    Button {
                        selectedPack = collection.name
                        model.accent = collection.colors[0]
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 0) {
                                ForEach(collection.colors, id: \.self) { name in
                                    Rectangle().fill(AccentPalette.color(name)).frame(height: 24)
                                }
                            }.clipShape(RoundedRectangle(cornerRadius: 7))
                            HStack {
                                Text(collection.name).font(.callout.weight(.semibold))
                                Spacer(minLength: 2)
                                if collection.colors.contains(model.accent) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(collection.mood).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                .frame(height: 27, alignment: .topLeading)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedPack == collection.name ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: selectedPack == collection.name ? 2 : 1))
                    }.buttonStyle(.plain).help(collection.mood)
                        .accessibilityLabel(collection.name + " color pack, " + collection.mood)
                }
            }
        }.onAppear {
            selectedPack = AccentPalette.packs.first { $0.colors.contains(model.accent) }?.name ?? "Classic"
        }
    }
}

private struct StudioBehavior: View {
    @ObservedObject var model: DockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "At a glance") {
                Toggle("Show clock and date", isOn: $model.showClock)
                Toggle(model.canAccessAI ? "Show Codex usage tile" : "Codex usage · Full Access", isOn: $model.showUsageCard).disabled(!model.canAccessAI)
                if !model.isAdditionalDock {
                    Toggle("Use DockGrove as my Dock", isOn: Binding(get: { model.replacingDock }, set: { model.changeDockAction?($0) }))
                    Text("Apple’s Dock returns when you turn this off or quit DockGrove.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Show DockGrove", isOn: Binding(get: { model.visible }, set: { model.visible = $0; model.visibilityAction?() }))
                if let error = model.systemError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            WorkspaceSettings(model: model, kit: model.toolkit)
            if !model.isAdditionalDock { SnapSettings(model: model) }
            if model.canAccessAI {
                StudioPanel(title: "Codex connection") {
                    Text("Read plan limits from your existing Codex sign-in. Your messages are not counted or collected.").font(.callout).foregroundStyle(.secondary)
                    Toggle("Refresh usage automatically", isOn: $model.usageEnabled)
                    TextField("Codex executable (auto-detected)", text: $model.customCLI).textFieldStyle(.roundedBorder)
                    Button(model.fetching ? "Refreshing…" : "Refresh usage") { model.refreshUsage() }.disabled(model.fetching)
                    if let error = model.usageError { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }
}

private struct StudioPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline); content() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.primary.opacity(0.07)))
    }
}


struct StudioToolbarSize: View {
    @ObservedObject var model: DockModel
    var body: some View {
        StudioPanel(title: "Toolbar size") {
            HStack(spacing: 12) {
                preset("Compact", width: 0.65, height: 88, icon: 40)
                preset("Balanced", width: 0.85, height: 104, icon: 48)
                preset("Spacious", width: 1, height: 140, icon: 56)
            }
            StudioNumberControl(title: "Toolbar width", value: $model.widthFraction, range: 0.35...1, step: 0.01, scale: 100, unit: "%", onBegin: model.rememberStudioLayout)
            StudioNumberControl(title: "Toolbar height", value: Binding(get: { model.barHeight }, set: { model.toolbarHeight = $0 }), range: max(88, model.iconSize + 44)...180, step: 2, unit: "pt", onBegin: model.rememberStudioLayout)
            StudioNumberControl(title: "Icon size", value: $model.iconSize, range: 32...64, step: 2, unit: "pt", onBegin: model.rememberStudioLayout)
            Toggle("Fit width to content", isOn: Binding(get: { model.fitToolbarToContent }, set: { model.rememberStudioLayout(); model.fitToolbarToContent = $0 }))
            HStack(alignment: .top) {
                Text("Width is a percentage of your display. The bar keeps each widget whole and uses pages when needed. Height grows to keep icons comfortable.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset size") { model.rememberStudioLayout(); model.widthFraction = 1; model.toolbarHeight = 92; model.iconSize = 48; model.fitToolbarToContent = true }
            }
        }
    }
    private func preset(_ title: String, width: Double, height: Double, icon: Double) -> some View {
        Button {
            model.rememberStudioLayout(); model.widthFraction = width; model.toolbarHeight = height; model.iconSize = icon; model.fitToolbarToContent = false
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 7).fill(model.color.opacity(0.16))
                    .overlay(HStack(spacing: 5) { ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 3).fill(model.color.opacity(0.7)).frame(width: 9, height: 9) } })
                    .frame(width: 112 * width, height: height / 4)
                    .frame(height: 35)
                Text(title).font(.caption.weight(.medium))
            }.frame(maxWidth: .infinity).padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(title + " toolbar size")
    }
}


/// Scrubbable value badge with discrete buttons for keyboard and assistive access.
struct StudioNumberControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var scale: Double = 1
    let unit: String
    var onBegin: () -> Void = {}
    @State private var dragOrigin: Double?
    static func bounded(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, range.lowerBound + ((value - range.lowerBound) / step).rounded() * step))
    }
    private func change(_ proposed: Double) { value = Self.bounded(proposed, range: range, step: step) }
    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Button { onBegin(); change(value - step) } label: { Image(systemName: "minus").frame(width: 28, height: 28) }
                .buttonStyle(.plain).disabled(value <= range.lowerBound).accessibilityLabel("Decrease " + title.lowercased())
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right").font(.caption2).foregroundStyle(.secondary)
                Text("\(Int((value * scale).rounded())) \(unit)").monospacedDigit().fontWeight(.semibold)
            }.frame(width: 104, height: 36)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(dragOrigin == nil ? 0.15 : 0.6)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { gesture in
                    if dragOrigin == nil { onBegin(); dragOrigin = value }
                    change((dragOrigin ?? value) + Double(gesture.translation.width / 4) * step)
                }.onEnded { _ in dragOrigin = nil })
                .help("Drag left or right to adjust " + title.lowercased())
                .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue("\(Int((value * scale).rounded())) \(unit)")
            Button { onBegin(); change(value + step) } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                .buttonStyle(.plain).disabled(value >= range.upperBound).accessibilityLabel("Increase " + title.lowercased())
        }
    }
}

struct StudioChoice: Identifiable {
    let value: String
    let title: String
    var icon: String = "circle.grid.2x2"
    var id: String { value }
}

struct StudioChoiceControl: View {
    let title: String
    @Binding var selection: String
    let options: [StudioChoice]
    @State private var showing = false
    @State private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filtered: [StudioChoice] {
        options.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !showing { query = "" }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showing.toggle() }
            } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Label(options.first { $0.value == selection }?.title ?? selection, systemImage: options.first { $0.value == selection }?.icon ?? "circle.grid.2x2")
                    Image(systemName: showing ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                }.padding(12).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(title + ": " + (options.first { $0.value == selection }?.title ?? selection))
                .accessibilityValue(showing ? "Expanded" : "Collapsed")
                .help(showing ? "Collapse choices" : "Show choices inline")
            if showing {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search " + title.lowercased(), text: $query).textFieldStyle(.plain)
                    }.padding(9).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 10) {
                            ForEach(filtered) { option in
                                Button { selection = option.value } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: option.icon).font(.title3).frame(width: 28)
                                        Text(option.title).fontWeight(.medium).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        if selection == option.value { Image(systemName: "checkmark.circle.fill") }
                                    }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(10)
                                        .background(selection == option.value ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityAddTraits(selection == option.value ? .isSelected : [])
                            }
                        }
                        if filtered.isEmpty { Text("No matching choices").foregroundStyle(.secondary).padding() }
                    }.frame(height: options.count > 6 ? 220 : 90)
                    HStack {
                        Text("Select a card to apply it.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Collapse") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showing = false } }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
        }.background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
    }
}
