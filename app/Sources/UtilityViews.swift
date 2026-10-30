import SwiftUI
import AppKit

struct UtilityView: View {
    @Environment(\.connectionSetupAllowed) private var setupAllowed
    let kind: ToolKind
    @ObservedObject var utility: Utilities
    @State private var title = ""
    @State private var address = ""
    @State private var zone = "America/Los_Angeles"
    @State private var amount = "1"
    @State private var category = UnitConversion.Category.length
    @State private var from = "m"
    @State private var to = "ft"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            if let status = utility.status { Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case .bookmarks:
            TextField("Bookmark name", text: $title)
            TextField("https://example.com", text: $address)
            Button("Add bookmark") { if utility.addBookmark(title: title, address: address) { title = ""; address = "" } }.disabled(address.isEmpty)
            ScrollView { VStack(alignment: .leading) { ForEach(utility.bookmarks) { item in
                HStack {
                    if let url = Bookmark.url(item.address) { Link(item.title, destination: url).lineLimit(1) }
                    Spacer()
                    Button("Remove") { utility.bookmarks.removeAll { $0.id == item.id } }
                }.padding(.vertical, 4)
            } }}.frame(maxHeight: 250)
        case .folders:
            HStack { Button("Up") { utility.loadFolder(utility.folder.deletingLastPathComponent()) }; Text(utility.folder.path).lineLimit(2).font(.caption).textSelection(.enabled) }
            TextField("Search this folder", text: $utility.folderQuery)
            Picker("Sort", selection: $utility.folderSort) { Text("Name").tag("Name"); Text("Newest").tag("Newest") }.pickerStyle(.segmented)
            ScrollView { LazyVStack(alignment: .leading) { ForEach(utility.sortedFolderItems, id: \.path) { url in
                Button {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && url.pathExtension != "app" { utility.loadFolder(url) }
                    else { NSWorkspace.shared.open(url) }
                } label: {
                    HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24); Text(url.lastPathComponent).lineLimit(1); Spacer() }
                }.buttonStyle(.plain).padding(4)
                    .onDrag { NSItemProvider(object: url as NSURL) }
                    .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            } }}.frame(height: 230).onAppear { utility.loadFolder() }
            HStack { Button("Choose…", action: utility.chooseFolder); Button("Downloads") { utility.loadFolder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }; Button("Refresh") { utility.loadFolder() } }
        case .stopwatch:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(duration(utility.elapsed(at: context.date))).font(.system(size: 42, weight: .light, design: .monospaced))
            }
            HStack {
                Button(utility.stopwatchStart == nil ? "Start" : "Pause") { utility.toggleStopwatch() }
                Button("Lap") { utility.laps.append(utility.elapsed(at: Date())) }.disabled(utility.stopwatchStart == nil)
                Button("Reset", action: utility.resetStopwatch)
            }
            ScrollView { VStack { ForEach(Array(utility.laps.enumerated()), id: \.offset) { index, time in HStack { Text("Lap \(index + 1)"); Spacer(); Text(duration(time)).monospacedDigit() } } }}.frame(maxHeight: 180)
        case .water:
            Text("\(utility.water) / \(utility.waterGoal) glasses today").font(.title2)
            ProgressView(value: min(Double(utility.water), Double(utility.waterGoal)), total: Double(utility.waterGoal))
            HStack { Button("−1") { utility.drink(-1) }; Button("Drank a glass") { utility.drink(1) } }
            Stepper("Daily goal: \(utility.waterGoal)", value: $utility.waterGoal, in: 1...30)
            Toggle("Hourly reminder while DockGrove is open", isOn: $utility.waterReminder)
            if utility.waterDue { Label("Time for a water break", systemImage: "drop.fill").foregroundStyle(.cyan) }
            Text("Choose your own goal. Count resets at local midnight.").font(.caption).foregroundStyle(.secondary)
        case .habits:
            HStack { TextField("New habit", text: $title); Button("Add") {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { utility.habits.append(Habit(title: trimmed)); title = "" }
            } }
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(utility.habits) { habit in
                HStack {
                    Button { if let i = utility.habits.firstIndex(where: { $0.id == habit.id }) { utility.habits[i].toggle(at: Date()) } } label: { Image(systemName: habit.completedDays.contains(Habit.day(Date())) ? "checkmark.circle.fill" : "circle") }
                    VStack(alignment: .leading) { Text(habit.title); Text("\(habit.completedDays.count) recorded days").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Button("Remove") { utility.habits.removeAll { $0.id == habit.id } }
                }
            } }}.frame(maxHeight: 250)
        case .progress:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(["Day", "Month", "Year"], id: \.self) { label in
                        let component: Calendar.Component = label == "Day" ? .day : label == "Month" ? .month : .year
                        if let interval = Calendar.current.dateInterval(of: component, for: context.date) {
                            let progress = context.date.timeIntervalSince(interval.start) / interval.duration
                            HStack { Text(label); Spacer(); Text("\(Int(progress * 100))%").monospacedDigit() }
                            ProgressView(value: progress)
                        }
                    }
                }
            }
        case .clocks:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 14) { ForEach(utility.zones, id: \.self) { id in
                    HStack { VStack(alignment: .leading) { Text(id.replacingOccurrences(of: "_", with: " ")); Text(clock(context.date, id)).font(.title3).monospacedDigit() }; Spacer(); Button("Remove") { utility.zones.removeAll { $0 == id } } }
                } }
            }
            Picker("Time zone", selection: $zone) { ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) } }
            Button("Add clock") { if !utility.zones.contains(zone) { utility.zones.append(zone) } }.disabled(utility.zones.contains(zone))
        case .converter:
            Picker("Category", selection: $category) { ForEach(UnitConversion.Category.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .onChange(of: category) { let units = UnitConversion.units(category); from = units[0]; to = units[1] }
            TextField("Amount", text: $amount)
            HStack {
                Picker("From", selection: $from) { ForEach(UnitConversion.units(category), id: \.self) { Text($0).tag($0) } }
                Button { swap(&from, &to) } label: { Image(systemName: "arrow.left.arrow.right") }
                Picker("To", selection: $to) { ForEach(UnitConversion.units(category), id: \.self) { Text($0).tag($0) } }
            }
            if let value = Double(amount), let result = UnitConversion.convert(value, from: from, to: to, category: category) {
                Text(result.formatted(.number.precision(.significantDigits(1...10))) + " " + to).font(.title).textSelection(.enabled)
            } else { Text("Enter a valid number.").foregroundStyle(.secondary) }
            Text("Offline unit conversions. KB uses 1,000 bytes; KiB uses 1,024.").font(.caption).foregroundStyle(.secondary)
        case .capture:
            Button("Capture selection to clipboard", action: utility.screenshot).disabled(utility.busy)
            Button("Open macOS Screenshot toolbar") { launch("/System/Applications/Utilities/Screenshot.app") }
            Text("The macOS toolbar also offers window capture, full screen capture, recording, timers, and save locations.").font(.caption).foregroundStyle(.secondary)
        case .colors:
            Text(utility.colorHex).font(.system(size: 32, design: .monospaced)).textSelection(.enabled)
            HStack { Button("Pick from screen", action: utility.pickColor); Button("Copy hex") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(utility.colorHex, forType: .string) } }
        case .controls:
            Button("Mission Control") { launch("/System/Applications/Mission Control.app") }
            Button("Emoji & Symbols") { NSApp.orderFrontCharacterPalette(nil) }
            Button("Sound settings") { openSettings("com.apple.Sound-Settings.extension") }
            Button("Display settings") { openSettings("com.apple.Displays-Settings.extension") }
            Button("Wi-Fi settings") { openSettings("com.apple.wifi-settings-extension") }
            Button("Bluetooth settings") { openSettings("com.apple.BluetoothSettings") }
            Button("Desktop & Dock settings") { openSettings("com.apple.Desktop-Settings.extension") }
            Button("Open Trash") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
        case .reminders:
            Text(utility.remindersStatus).font(.caption).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(utility.reminders, id: \.calendarItemIdentifier) { reminder in
                HStack { Button { utility.completeReminder(reminder) } label: { Image(systemName: "circle") }.help("Mark complete in Apple Reminders"); Text(reminder.title ?? "Untitled") }
            } }}.frame(maxHeight: 250)
            if setupAllowed { Button("Allow / refresh Reminders access", action: utility.loadReminders) }
            else { ConnectionSettingsButton() }
        default: EmptyView()
        }
    }
    private func duration(_ t: TimeInterval) -> String { String(format: "%02d:%02d.%01d", Int(t) / 60, Int(t) % 60, Int(t * 10) % 10) }
    private func clock(_ date: Date, _ zone: String) -> String { let f = DateFormatter(); f.timeZone = TimeZone(identifier: zone); f.dateFormat = "EEE HH:mm:ss"; return f.string(from: date) }
    private func launch(_ path: String) { if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) { utility.status = "This system app is unavailable on this Mac." } }
    private func openSettings(_ pane: String) { if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) } }
}
