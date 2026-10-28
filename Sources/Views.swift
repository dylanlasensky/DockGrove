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
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 15) {
            HStack(spacing: 9) {
                ForEach(model.apps) { app in AppTile(app: app, model: model) }
                ForEach(model.runningApps) { app in AppTile(app: app, model: model) }
                Button(action: model.addApps) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55)).frame(width: 28, height: model.iconSize)
                }.buttonStyle(.plain).help("Pin an app")
            }.frame(height: model.iconSize + 14)
            Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 42)
            UsageTile(model: model)
            ForEach(model.toolkit.enabled.compactMap(ToolKind.init(rawValue:))) { kind in
                if kind == .spacer { Color.clear.frame(width: 24, height: 40) }
                else if kind == .separator { Divider().frame(height: 40) }
                else { ToolTile(kind: kind, model: model, kit: model.toolkit) }
            }
            if model.showClock {
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 42)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }.frame(minWidth: 77, alignment: .leading)
                }
            }
            Button { model.settingsAction?() } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15)).foregroundStyle(.white.opacity(0.6)).frame(width: 24, height: 36)
            }.buttonStyle(.plain).help("WaveDock settings")
        }.padding(.horizontal, 20).padding(.vertical, 13) }
        .frame(width: min((NSScreen.screens.indices.contains(model.toolkit.screenIndex) ? NSScreen.screens[model.toolkit.screenIndex].frame.width : (NSScreen.main?.frame.width ?? 1440)) - 48, 450 + Double(model.apps.count + model.runningApps.count) * (model.iconSize + 9) + Double(model.toolkit.enabled.count) * 87), height: model.iconSize + 52)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.20), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 7)
        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .fixedSize()
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
            }.frame(width: 177, height: max(48, model.iconSize), alignment: .center)
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
                    Image(systemName: "water.waves").font(.system(size: 30, weight: .medium)).foregroundStyle(model.color)
                        .frame(width: 58, height: 58).background(model.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WaveDock").font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("Your apps. Your usage. Your Dock.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("EARLY ACCESS 0.3").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        Button("Done") { model.closeSettingsAction?() }
                    }
                }
                card("Make it yours", icon: "paintpalette") {
                    HStack {
                        Text("Icon size")
                        Slider(value: $model.iconSize, in: 32...64, step: 2).frame(width: 210)
                        Text("\(Int(model.iconSize))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Picker("Accent", selection: $model.accent) { ForEach(["Mint", "Blue", "Lilac", "Coral"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    Toggle("Show clock and date", isOn: $model.showClock)
                    HStack {
                        Button("Pin apps…", action: model.addApps)
                        Text("Drag icons to reorder. Right-click for more actions.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                WorkspaceSettings(model: model, kit: model.toolkit)
                card("Your Mac Dock", icon: "dock.rectangle") {
                    Toggle("Use WaveDock as my Dock", isOn: Binding(get: { model.replacingDock }, set: { model.changeDockAction?($0) }))
                    Text("Replaces Apple’s Dock at the bottom edge while WaveDock runs. Hides during full screen and restores your original Dock preferences when you quit.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error = model.systemError { Text(error).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button(model.visible ? "Hide WaveDock" : "Show WaveDock") { model.visible.toggle(); model.visibilityAction?() }
                        Button("Restore Apple Dock") { model.changeDockAction?(false) }
                    }
                }
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
                    Text("Made for Dylan · Free, local, and yours to edit.").font(.caption).foregroundStyle(.secondary)
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
