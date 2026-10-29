import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

final class TileInteraction: ObservableObject {
    @Published var hovered = false
    @Published var expanded = false
}

struct DockView: View {
    @ObservedObject var model: DockModel
    @State private var page = 0
    var entries: [DockEntry] {
        model.apps.map(DockEntry.app) + model.runningApps.map(DockEntry.app) + [.add] + (model.showUsageCard ? [.usage] : []) +
        model.toolkit.enabled.compactMap(ToolKind.init(rawValue:)).map(DockEntry.tool) + (model.showClock ? [.clock] : [])
    }
    var body: some View {
        let screen = model.selectedScreen
        let widths = entries.map { $0.width(iconSize: model.iconSize, rich: model.toolkit.richWidgets) }
        let natural = widths.reduce(0, +) + Double(max(0, widths.count - 1)) * DockPageLayout.gap
        let width = DockPageLayout.bodyWidth(screenWidth: min(screen?.frame.width ?? 1440, max((widths.max() ?? 236) + DockPageLayout.chrome + 44, (screen?.frame.width ?? 1440) * model.widthFraction)), naturalWidth: natural)
        let pages = DockPageLayout.pages(widths: widths, available: width - DockPageLayout.chrome)
        let current = min(page, pages.count - 1)
        HStack(spacing: 8) {
            Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 46) }
                .disabled(current == 0).help("Previous Dock page").accessibilityLabel("Previous Dock page")
            HStack(spacing: DockPageLayout.gap) {
                ForEach(pages[current], id: \.self) { i in
                    entry(entries[i]).frame(width: widths[i], height: max(64, model.iconSize + 20))
                }
                Spacer(minLength: 0)
            }.frame(width: max(1, width - DockPageLayout.chrome), height: max(64, model.iconSize + 20)).clipped()
            VStack(spacing: 3) {
                Button { page = min(pages.count - 1, current + 1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 26) }
                    .disabled(current == pages.count - 1).help("Next Dock page").accessibilityLabel("Next Dock page")
                Text("\(current + 1)/\(pages.count)").font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
            }.frame(width: 32)
            Button { model.settingsAction?() } label: { Image(systemName: "slider.horizontal.3").frame(width: 26, height: 46) }
                .help("WaveDock settings").accessibilityLabel("WaveDock settings")
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: width, height: max(64, model.iconSize + 20) + 24)
        .background { DockPlate(theme: model.theme) }
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.2), lineWidth: 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 27))
        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
        .foregroundStyle(.primary).preferredColorScheme(model.scheme)
        .onChange(of: entries.map(\.id)) { page = min(page, pages.count - 1) }
    }
    @ViewBuilder private func entry(_ item: DockEntry) -> some View {
        switch item {
        case .app(let app): AppTile(app: app, model: model)
        case .add: Button(action: model.addApps) { Image(systemName: "plus").frame(width: 28, height: model.iconSize) }.help("Pin an app")
        case .usage: UsageTile(model: model)
        case .tool(let kind):
            if kind == .spacer { Color.clear }
            else if kind == .separator { Divider().frame(height: 40) }
            else { ToolTile(kind: kind, model: model, kit: model.toolkit) }
        case .clock:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).modifier(WidgetSurface()).lineLimit(1).minimumScaleFactor(0.75)
            }
        }
    }
}

struct AppTile: View {
    let app: DockApp
    @ObservedObject var model: DockModel
    @StateObject private var interaction = TileInteraction()
    var body: some View {
        VStack(spacing: 4) {
            Button { model.open(app) } label: {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: model.iconSize, height: model.iconSize)
                    .scaleEffect(interaction.hovered ? 1.13 : 1).offset(y: interaction.hovered ? -4 : 0)
            }.buttonStyle(.plain).help(app.name)
            Circle().fill(app.isRunning ? model.color : .clear).frame(width: 4, height: 4)
        }
        .onDrag { NSItemProvider(object: app.id as NSString) }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { text, _ in if let text = text { Task { @MainActor in model.reorder(text, before: app) } } }; return true
        }
        .onHover { interaction.hovered = $0 }
        .animation(.spring(response: 0.23, dampingFraction: 0.65), value: interaction.hovered)
        .contextMenu {
            Button("Open \(app.name)") { model.open(app) }
            Divider()
            Button("Move left") { model.move(app, by: -1) }.disabled(model.apps.first == app)
            Button("Move right") { model.move(app, by: 1) }.disabled(model.apps.last == app)
            Divider()
            if model.apps.contains(app) { Button("Unpin") { model.remove(app) } }
            else { Button("Pin to Dock") { model.pin(app) } }
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == app.url }) {
                Button(running.isHidden ? "Show app" : "Hide app") { if running.isHidden { running.unhide() } else { running.hide() } }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            Button("Quit app") { NSWorkspace.shared.runningApplications.first { $0.bundleURL == app.url }?.terminate() }.disabled(!app.isRunning)
        }
    }
}

struct UsageTile: View {
    @ObservedObject var model: DockModel
    @StateObject private var interaction = TileInteraction()
    var body: some View {
        Button { interaction.expanded.toggle() } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").foregroundStyle(model.color)
                    Text(model.activeBucket?.title ?? "ChatGPT plan").fontWeight(.semibold)
                    Spacer()
                    if model.fetching { ProgressView().controlSize(.mini) }
                    else if model.usageError != nil { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                    else { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)) }
                }.font(.system(size: 10))
                if let bucket = model.activeBucket {
                    if let primary = bucket.primary { MiniMeter(window: primary, color: model.color) }
                    else if let secondary = bucket.secondary { MiniMeter(window: secondary, color: model.color) }
                } else {
                    HStack {
                        Text(model.usageError != nil ? "Connection unavailable" : "Connect your usage").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }.foregroundStyle(.white.opacity(0.65))
                }
            }.padding(.horizontal, model.toolkit.richWidgets ? 12 : 0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).modifier(WidgetSurface())
        }.buttonStyle(.plain)
        .popover(isPresented: $interaction.expanded, arrowEdge: model.toolkit.edge == "Top" ? .bottom : .top) { UsageDetails(model: model).padding(22).frame(width: 335).preferredColorScheme(.dark) }
    }
}

struct MiniMeter: View {
    let window: LimitWindow
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(Int(window.remaining))% left").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                Text(window.title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(window.remaining < 15 ? .orange : color).frame(width: geometry.size.width * window.remaining / 100)
                }
            }.frame(height: 4)
        }
    }
}

struct UsageDetails: View {
    @ObservedObject var model: DockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(model.color)
                Text("Your plan usage").font(.headline)
                Spacer()
                if model.fetching { ProgressView().controlSize(.small) }
            }
            if let usage = model.usage, usage.buckets.count > 1 {
                Picker("Allowance", selection: $model.selectedBucket) {
                    ForEach(usage.buckets, id: \.0) { id, bucket in Text(bucket.title).tag(id) }
                }
            }
            if let bucket = model.activeBucket {
                if let primary = bucket.primary { detail(primary) }
                if let secondary = bucket.secondary { detail(secondary) }
            }
            if let error = model.usageError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let refreshed = model.refreshed {
                Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))\(model.usageError != nil ? " · Previous reading" : "")").font(.caption).foregroundStyle(.secondary)
            }
            Text("Uses the limits reported by your signed-in Codex service. Regular ChatGPT message counts may not be included.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.usageEnabled ? "Refresh" : "Connect & refresh") { model.refreshUsage() }.disabled(model.fetching).buttonStyle(.borderedProminent).tint(model.color)
                Spacer()
                Button("Settings") { model.settingsAction?() }.buttonStyle(.bordered)
            }
        }
    }
    private func detail(_ window: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MiniMeter(window: window, color: model.color)
            Text(window.resetDescription).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: DockModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 13) {
                    BrandIcon().frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WaveDock").font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("A calmer space for everything you do.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("VERSION 0.7 · PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        Button("Done") { model.closeSettingsAction?() }
                    }
                }
                card("Make it yours", icon: "paintpalette") {
                    DockAppearanceSettings(model: model)
                    HStack {
                        Text("Icon size")
                        Slider(value: $model.iconSize, in: 32...64, step: 2).frame(width: 210)
                        Text("\(Int(model.iconSize))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Accent")
                        Spacer()
                        ForEach(AccentPalette.names, id: \.self) { name in
                            Button { model.accent = name } label: {
                                Circle().fill(AccentPalette.color(name)).frame(width: 22, height: 22)
                                    .overlay { if name == "None" { Image(systemName: "slash.circle").foregroundStyle(.black) } }
                                    .padding(3).overlay(Circle().stroke(model.accent == name ? Color.primary : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain).help(name).accessibilityLabel(name + " accent")
                        }
                        ColorPicker("Custom", selection: Binding(get: { model.color }, set: { model.accent = AccentPalette.hex($0) }), supportsOpacity: false).labelsHidden().help("Choose any accent color")
                    }
                    Text(model.accent == "None" ? "Neutral controls with no colored accent." : "Accent: " + model.accent).font(.caption).foregroundStyle(.secondary)
                    Toggle("Rich widget cards", isOn: Binding(get: { model.toolkit.richWidgets }, set: { model.toolkit.richWidgets = $0 }))
                    Toggle("Show clock and date", isOn: $model.showClock)
                    HStack {
                        Button("Pin apps…", action: model.addApps)
                        Text("Drag icons to reorder. Right-click for more actions.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                WorkspaceSettings(model: model, kit: model.toolkit)
                if !model.isAdditionalDock { card("Your Mac Dock", icon: "dock.rectangle") {
                    Toggle("Use WaveDock as my Dock", isOn: Binding(get: { model.replacingDock }, set: { model.changeDockAction?($0) }))
                    Text("Replaces Apple’s Dock at the bottom edge while WaveDock runs. Hides during full screen and restores your original Dock preferences when you quit.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error = model.systemError { Text(error).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button(model.visible ? "Hide WaveDock" : "Show WaveDock") { model.visible.toggle(); model.visibilityAction?() }
                        Button("Restore Apple Dock") { model.changeDockAction?(false) }
                    }
                }
                }
                if !model.isAdditionalDock { SnapSettings(model: model) }
                card("ChatGPT plan usage", icon: "sparkles") {
                    Text("Connect your existing ChatGPT sign-in through Codex. WaveDock reads the reported limits and reset times every five minutes. It does not count your chat messages.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Refresh usage automatically", isOn: $model.usageEnabled)
                    HStack {
                        TextField("Codex executable (auto-detected)", text: $model.customCLI).textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseCLI() }
                    }
                    Text(UsageClient.executable(custom: model.customCLI) == nil ? "Codex not found. Install Codex CLI or choose its executable." : "Codex found on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.fetching ? "Connecting…" : "Connect & refresh") { model.refreshUsage() }.disabled(model.fetching).buttonStyle(.borderedProminent).tint(model.color)
                        if model.usage != nil { Label("Usage received", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(model.color) }
                    }
                    if let error = model.usageError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                }
                HStack {
                    Text("WaveDock · Thoughtfully at hand.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit WaveDock") { NSApp.terminate(nil) }
                }
            }.padding(28)
        }.frame(width: 590, height: 720).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark)
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06)))
    }
    private func chooseCLI() {
        let picker = NSOpenPanel(); picker.title = "Choose the Codex executable"; picker.canChooseDirectories = false
        if picker.runModal() == .OK, let url = picker.url { model.customCLI = url.path }
    }
}
