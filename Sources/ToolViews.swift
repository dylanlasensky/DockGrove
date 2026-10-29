import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ToolTile: View {
    let kind: ToolKind
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @StateObject private var interaction = TileInteraction()
    var caption: String {
        switch kind {
        case .github: return kit.github.snapshot?.run?.displayStatus ?? "GitHub"
        case .water: return kit.utilities.waterDue ? "Water break" : "\(kit.utilities.water)/\(kit.utilities.waterGoal) glasses"
        case .habits: return "\(kit.utilities.habits.filter { $0.completedDays.contains(Habit.day(Date())) }.count) done today"
        case .weather: return kit.weatherText
        case .music: return "Music"
        case .focus: return kit.focusFinished ? "Complete" : kit.timerText
        case .tasks: return "\(kit.tasks.filter { !$0.done }.count) to do"
        case .files: return "\(kit.files.count) items"
        case .system: return kit.battery
        default: return kind.title
        }
    }
    var body: some View {
        Group {
            if kit.richWidgets {
                RichWidgetCard(kind: kind, model: model, kit: kit) { interaction.expanded.toggle(); if kind == .search { kit.scanApplications() } }
            } else {
                Button { interaction.expanded.toggle(); if kind == .search { kit.scanApplications() } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: kind.icon).font(.system(size: 20, weight: .medium)).foregroundStyle(model.color)
                        Text(caption).font(.system(size: 10, weight: .medium)).lineLimit(1).monospacedDigit()
                    }.frame(width: 72, height: max(48, model.iconSize)).modifier(WidgetSurface(radius: 12))
                }.buttonStyle(.plain).help(kind.title)
            }
        }
        .contextMenu {
            Button("Move earlier") { kit.moveWidget(kind, by: -1) }
            Button("Move later") { kit.moveWidget(kind, by: 1) }
            Divider()
            Button("Remove widget") { kit.toggle(kind, false) }
        }
        .popover(isPresented: $interaction.expanded, arrowEdge: kit.edge == "Top" ? .bottom : .top) {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Label(kind.title, systemImage: kind.icon).font(.headline); Spacer(); WaveMark().stroke(model.color.opacity(0.6), style: StrokeStyle(lineWidth: 1.8, lineCap: .round)).frame(width: 23, height: 23) }
                Divider()
                contents
            }.padding(22).frame(width: 350).preferredColorScheme(.dark)
        }
    }
    @ViewBuilder var contents: some View {
        switch kind {
        case .claudeCodeUsage: LocalAIUsageView(widget: kit.claudeCodeUsage)
        case .geminiUsage: LocalAIUsageView(widget: kit.geminiUsage)
        case .calculator: CalculatorView()
        case .currency: CurrencyView(widget: kit.currency)
        case .voiceMemo: VoiceMemoView(memo: kit.voiceMemo)
        case .audio: AudioControlView(audio: kit.audio)
        case .appGroups: AppGroupsView(groups: kit.groups, model: model)
        case .webSearch: WebSearchView()
        case .windows: WindowManagerView(manager: kit.windows, model: model)
        case .googleCalendar: CalendarAgendaView(calendar: kit.googleCalendar)
        case .spotify: MusicPlayerView(player: kit.spotify)
        case .appleMusic: MusicPlayerView(player: kit.appleMusic)
        case .openaiUsage: AIUsageView(widget: kit.openaiUsage)
        case .anthropicUsage: AIUsageView(widget: kit.anthropicUsage)
        case .cursorUsage: AIUsageView(widget: kit.cursorUsage)
        case .github: GitHubView(github: kit.github)
        case .bookmarks, .folders, .stopwatch, .water, .habits, .progress, .clocks, .converter, .capture, .colors, .controls, .reminders, .spacer, .separator:
            UtilityView(kind: kind, utility: kit.utilities)
        case .weather:
            Text(kit.weatherText).font(.system(size: 40, weight: .light, design: .rounded))
            Text(kit.weatherDetail).font(.callout).foregroundStyle(.secondary)
            TextField("City name", text: $kit.weatherCity).textFieldStyle(.roundedBorder).onSubmit { kit.fetchWeather() }
            Button(kit.weatherLoading ? "Loading…" : "Get weather") { kit.fetchWeather() }.disabled(kit.weatherLoading)
            Text("City search is sent to Open-Meteo when you refresh. No location permission needed.").font(.caption).foregroundStyle(.secondary)
            Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/")!).font(.caption)
        case .music:
            MusicPlayerView(player: kit.spotify)
            Divider()
            MusicPlayerView(player: kit.appleMusic)
        case .search:
            TextField("Find an app…", text: $kit.query).textFieldStyle(.roundedBorder)
            ScrollView { LazyVStack(spacing: 4) {
                ForEach(kit.applications.filter { kit.query.isEmpty || $0.name.localizedCaseInsensitiveContains(kit.query) }) { app in
                    HStack {
                        Button { model.open(app); interaction.expanded = false } label: {
                            HStack { Image(nsImage: app.icon).resizable().frame(width: 28, height: 28); Text(app.name); Spacer() }
                        }.buttonStyle(.plain)
                        Button { model.pin(app) } label: { Image(systemName: model.apps.contains(app) ? "pin.fill" : "pin") }.disabled(model.apps.contains(app)).help("Pin app")
                    }.padding(6)
                }
            }}.frame(height: 290)
        case .notes:
            TextEditor(text: $kit.note).font(.body).frame(height: 230).padding(6).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            Text("Saved automatically on this Mac.").font(.caption).foregroundStyle(.secondary)
        case .tasks:
            HStack { TextField("Add a task…", text: $kit.draftTask).onSubmit { kit.addTask() }; Button("Add", action: kit.addTask) }
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                ForEach(kit.tasks) { task in
                    HStack {
                        Button { if let i = kit.tasks.firstIndex(where: { $0.id == task.id }) { kit.tasks[i].done.toggle() } } label: { Image(systemName: task.done ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain).foregroundStyle(model.color)
                        Text(task.title).strikethrough(task.done).foregroundStyle(task.done ? .secondary : .primary)
                        Spacer()
                        Button { kit.tasks.removeAll { $0.id == task.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Remove task")
                    }
                }
                if kit.tasks.isEmpty { Text("A little space for what comes next.").foregroundStyle(.secondary) }
            }}.frame(maxHeight: 240)
            Button("Clear completed") { kit.tasks.removeAll { $0.done } }.disabled(!kit.tasks.contains { $0.done })
        case .focus:
            Text(kit.timerText).font(.system(size: 54, weight: .light, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity)
            if kit.focusFinished { Label("Session complete", systemImage: "checkmark.circle").foregroundStyle(model.color) }
            HStack { ForEach([5, 15, 25, 50], id: \.self) { minutes in Button("\(minutes)m") { kit.resetTimer(minutes) } } }
            HStack { Button(kit.focusEnd == nil ? "Start" : "Pause", action: kit.toggleTimer).buttonStyle(.borderedProminent).tint(model.color); Button("Reset") { kit.resetTimer(25) } }
            Text("Choose a short break or a focused session. A sound plays when time is up.").font(.caption).foregroundStyle(.secondary)
        case .files:
            Text("Drop files here to keep shortcuts handy.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(20).background(model.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url = url { Task { @MainActor in kit.addFile(url) } } } }; return !providers.isEmpty
                }
            ScrollView { VStack(spacing: 10) { ForEach(kit.files, id: \.self) { path in
                HStack {
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
                        HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 24, height: 24); Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1); Spacer() }
                    }.buttonStyle(.plain).onDrag { NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: { Image(systemName: "folder") }.help("Reveal in Finder")
                    Button { kit.files.removeAll { $0 == path } } label: { Image(systemName: "xmark") }.help("Remove shortcut")
                }
            } }}.frame(maxHeight: 230)
            HStack { Button("Add files…", action: kit.addFiles); Button("Downloads") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) } }
            Text("Removing a shortcut leaves the original file in place.").font(.caption).foregroundStyle(.secondary)
        case .system: SystemDetailView(monitor: kit.monitor, kit: kit)
        case .calendar: CalendarAgendaView(calendar: kit.calendar)
        case .clipboard:
            Toggle("Capture copied text", isOn: $kit.clipboardEnabled)
            Text("Opt-in, memory only, up to 20 entries. Marked password-manager copies are skipped. Turn off capture for other sensitive text.").font(.caption).foregroundStyle(.secondary)
            ScrollView { VStack(spacing: 8) { ForEach(kit.clipboard, id: \.self) { text in
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Text(text).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.buttonStyle(.bordered)
            } }}.frame(maxHeight: 250)
            Button("Clear history") { kit.clipboard = [] }
        }
    }
}

struct WorkspaceSettings: View {
    @State private var widgetSearch = ""
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Layout & profiles", systemImage: "rectangle.3.group").font(.headline)
            Picker("Position", selection: $kit.edge) { Text("Bottom").tag("Bottom"); Text("Top").tag("Top") }.pickerStyle(.segmented).disabled(model.replacingDock)
            Picker("Display", selection: $kit.screenIndex) { ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Text(screen.localizedName).tag(index) } }
            Toggle("Automatically hide WaveDock", isOn: $kit.autoHide)
            Toggle("Hide when windows overlap", isOn: $kit.hideOnOverlap)
            Toggle("Include unpinned running apps", isOn: $kit.showRunning)
            HStack { TextField("Name this layout…", text: $kit.profileName); Button("Save layout") { model.saveProfile() }.disabled(kit.profileName.trimmingCharacters(in: .whitespaces).isEmpty) }
            ForEach(kit.profiles) { profile in
                HStack { Text(profile.name); Spacer(); Button("Apply") { model.applyProfile(profile) }; Button("Remove") { kit.profiles.removeAll { $0.id == profile.id } } }
            }
            HStack { Button("Export layouts…", action: model.exportProfiles); Button("Import layouts…", action: model.importProfiles) }
            Divider()
            LoginSettings(utility: kit.utilities)
            Label("Widget library", systemImage: "square.grid.2x2").font(.headline)
            Text("Enable the tools you want in your Dock. Use the page arrows when the Dock fills up. Settings stays visible on every page.").font(.caption).foregroundStyle(.secondary)
            TextField("Find a widget…", text: $widgetSearch)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ToolKind.allCases.filter { widgetSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(widgetSearch) }) { kind in
                    Toggle(isOn: Binding(get: { kit.enabled.contains(kind.rawValue) }, set: { kit.toggle(kind, $0) })) {
                        HStack(spacing: 8) { Image(systemName: kind.icon).foregroundStyle(model.color).frame(width: 22); Text(kind.title).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                    }.toggleStyle(.switch).controlSize(.mini).padding(10).modifier(WidgetSurface(radius: 10)).help(kind.title)
                }
            }
        }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct LoginSettings: View {
    @ObservedObject var utility: Utilities
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Open WaveDock at login", isOn: Binding(get: { utility.loginEnabled }, set: { utility.setLogin($0) }))
            if let message = utility.status { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
