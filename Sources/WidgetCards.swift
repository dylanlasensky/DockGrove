import SwiftUI
import AppKit

struct RichWidgetCard: View {
    let kind: ToolKind
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    var open: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) { summary.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
            controls
        }.padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(WidgetSurface()).help(kind.title).accessibilityElement(children: .contain)
    }
    @ViewBuilder var summary: some View {
        switch kind {
        case .focus:
            VStack(alignment: .leading, spacing: 3) {
                eyebrow(kit.focusFinished ? "SESSION COMPLETE" : "FOCUS", icon: "timer")
                Text(kit.timerText).font(.system(size: 27, weight: .medium)).monospacedDigit()
            }
        case .stopwatch:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                VStack(alignment: .leading, spacing: 3) { eyebrow("STOPWATCH", icon: "stopwatch"); Text(String(format: "%02d:%04.1f", Int(kit.utilities.elapsed(at: context.date)) / 60, kit.utilities.elapsed(at: context.date).truncatingRemainder(dividingBy: 60))).font(.system(size: 23, weight: .medium)).monospacedDigit() }
            }
        case .system:
            VStack(alignment: .leading, spacing: 6) {
                HStack { eyebrow("CPU", icon: "cpu"); Spacer(); Text(kit.monitor.available ? "\(Int(kit.monitor.cpu))%" : "—").font(.system(size: 12, weight: .semibold)).monospacedDigit() }
                Sparkline(values: kit.monitor.history, color: model.color).frame(height: 26)
            }.onAppear { kit.monitor.start() }
        case .water:
            HStack(spacing: 10) { RingMetric(value: Double(kit.utilities.water) / Double(kit.utilities.waterGoal), label: "\(kit.utilities.water)", color: model.color).frame(width: 47, height: 47)
                VStack(alignment: .leading, spacing: 4) { Text("Stay hydrated").font(.system(size: 12, weight: .semibold)); Text(kit.utilities.waterDue ? "Time for a glass" : "\(kit.utilities.waterGoal) glasses today").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        case .tasks:
            VStack(alignment: .leading, spacing: 4) {
                let tasks = Array(kit.tasks.filter { !$0.done }.prefix(3))
                if tasks.isEmpty { eyebrow("TASKS", icon: "checklist"); Text("A clear day ahead").font(.system(size: 12, weight: .medium)) }
                else { ForEach(tasks) { task in HStack(spacing: 6) { Circle().stroke(model.color, lineWidth: 1.2).frame(width: 7, height: 7); Text(task.title).font(.system(size: 11, weight: .medium)).lineLimit(1) } } }
            }
        case .notes:
            HStack(spacing: 9) { glyph("note.text"); VStack(alignment: .leading, spacing: 4) { Text("Quick note").font(.system(size: 12, weight: .semibold)); Text(kit.note.isEmpty ? "A thought worth keeping" : kit.note).font(.system(size: 10)).lineLimit(2).foregroundStyle(.secondary) } }
        case .spotify, .appleMusic, .music:
            let player = kind == .appleMusic ? kit.appleMusic : kit.spotify
            HStack(spacing: 9) { glyph(kind.icon); VStack(alignment: .leading, spacing: 4) {
                Text(player.track?.title ?? player.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(player.track.map { $0.artist.isEmpty ? ($0.playing ? "Playing" : "Paused") : $0.artist } ?? "Connect your music").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } }
        case .calendar, .googleCalendar:
            let calendar = kind == .googleCalendar ? kit.googleCalendar : kit.calendar
            HStack(spacing: 10) {
                VStack(spacing: 0) { Text(Date(), format: .dateTime.day()).font(.system(size: 24, weight: .semibold)); Text(Date(), format: .dateTime.month(.abbreviated)).font(.system(size: 9, weight: .medium)).foregroundStyle(model.color) }.frame(width: 34)
                VStack(alignment: .leading, spacing: 4) { Text(calendar.events.first?.title ?? (calendar.connected ? "Nothing upcoming" : kind.title)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let event = calendar.events.first { Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }
                    else { Text(calendar.connected ? "Enjoy the breathing room" : "Connect your calendars").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        case .weather:
            HStack { VStack(alignment: .leading, spacing: 2) { Text(kit.weatherText == "Choose a city" ? "—°" : kit.weatherText).font(.system(size: 28, weight: .medium)); Text(kit.weatherCity.isEmpty ? "Choose a city" : kit.weatherCity).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: "cloud.sun.fill").symbolRenderingMode(.hierarchical).foregroundStyle(model.color).font(.system(size: 27)) }
        case .progress:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let interval = Calendar.current.dateInterval(of: .month, for: context.date)!
                let fraction = context.date.timeIntervalSince(interval.start) / interval.duration
                VStack(alignment: .leading, spacing: 7) { HStack { Text(context.date, format: .dateTime.month(.wide)).font(.system(size: 11, weight: .medium)); Spacer(); Text("\(Int(fraction * 100))%").font(.system(size: 10)).foregroundStyle(.secondary) }; HStack(spacing: 3) { ForEach(0..<20) { i in Capsule().fill(Double(i) / 20 < fraction ? model.color : .white.opacity(0.1)) } }.frame(height: 17) }
            }
        case .appGroups:
            let paths = Array((kit.groups.groups.first?.paths ?? model.apps.map(\.id)).prefix(4))
            HStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.fixed(23)), GridItem(.fixed(23))], spacing: 3) { ForEach(paths, id: \.self) { path in Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 23, height: 23) } }
                VStack(alignment: .leading, spacing: 3) { Text(kit.groups.groups.first?.name ?? "App groups").font(.system(size: 12, weight: .semibold)).lineLimit(1); Text("Your apps, together").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
            }
        case .github:
            VStack(alignment: .leading, spacing: 4) { eyebrow("GITHUB", icon: kind.icon); Text(kit.github.snapshot?.run?.displayStatus ?? "Repository activity").font(.system(size: 12, weight: .medium)).lineLimit(1) }
        case .claudeCodeUsage, .geminiUsage:
            let widget = kind == .claudeCodeUsage ? kit.claudeCodeUsage : kit.geminiUsage
            VStack(alignment: .leading, spacing: 4) {
                eyebrow(widget.provider.title.uppercased(), icon: kind.icon)
                if let report = widget.report {
                    if widget.provider == .claude {
                        Text(report.activeWindows(at: Date()).first.map { "\(Int(100 - $0.used))% left" } ?? "No active limit").font(.system(size: 19, weight: .medium)).lineLimit(1)
                    } else { Text(report.totalTokens.formatted() + " tokens").font(.system(size: 17, weight: .medium)).lineLimit(1) }
                    Text(report.stale(at: Date()) ? "Older report" : widget.provider == .claude ? "Reported allowance" : "Latest imported session").font(.system(size: 9)).foregroundStyle(.secondary)
                } else { Text("Connect local usage").font(.system(size: 12, weight: .medium)).lineLimit(1) }
            }.onAppear { widget.start() }
        case .openaiUsage, .anthropicUsage, .cursorUsage:
            let widget = kind == .openaiUsage ? kit.openaiUsage : kind == .anthropicUsage ? kit.anthropicUsage : kit.cursorUsage
            VStack(alignment: .leading, spacing: 4) { eyebrow(kind == .openaiUsage ? "OPENAI API" : kind == .anthropicUsage ? "CLAUDE API" : "CURSOR TEAM", icon: "chart.bar.xaxis")
                Text(widget.snapshot?.totals.first.map { $0.formatted() } ?? "Connect usage").font(.system(size: widget.snapshot == nil ? 12 : 22, weight: .medium)).lineLimit(1)
            }
        case .currency:
            VStack(alignment: .leading, spacing: 4) { eyebrow(kit.currency.base + " → " + kit.currency.quote, icon: "arrow.left.arrow.right"); Text(kit.currency.converted.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "Daily exchange rates").font(.system(size: kit.currency.report == nil ? 12 : 23, weight: .medium)).lineLimit(1) }
        case .voiceMemo:
            HStack { glyph(kit.voiceMemo.recording ? "waveform" : "mic"); VStack(alignment: .leading, spacing: 4) { Text(kit.voiceMemo.recording ? "Recording" : "Voice memo").font(.system(size: 12, weight: .semibold)); Text(kit.voiceMemo.recording ? String(format: "%02d:%02d", Int(kit.voiceMemo.elapsed) / 60, Int(kit.voiceMemo.elapsed) % 60) : "Keep a thought").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary) } }
        default:
            HStack(spacing: 10) { glyph(kind.icon); VStack(alignment: .leading, spacing: 4) { Text(kind.title).font(.system(size: 12, weight: .semibold)).lineLimit(1); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) } }
        }
    }
    @ViewBuilder private var controls: some View {
        switch kind {
        case .focus: transport(kit.focusEnd == nil ? "play.fill" : "pause.fill", label: kit.focusEnd == nil ? "Start focus" : "Pause focus", action: kit.toggleTimer)
        case .stopwatch: transport(kit.utilities.stopwatchStart == nil ? "play.fill" : "pause.fill", label: "Start or pause stopwatch") { kit.utilities.toggleStopwatch() }
        case .water: transport("plus", label: "Log a glass of water") { kit.utilities.drink(1) }
        case .spotify, .appleMusic, .music:
            let player = kind == .appleMusic ? kit.appleMusic : kit.spotify
            if player.connected { transport(player.track?.playing == true ? "pause.fill" : "play.fill", label: player.track?.playing == true ? "Pause music" : "Play music") { player.refresh(command: .toggle) }.disabled(player.busy) }
        default: EmptyView()
        }
    }
    private var subtitle: String {
        switch kind { case .files: return "\(kit.files.count) saved shortcuts"; case .folders: return "Files at your fingertips"; case .search: return "Find an application"; case .webSearch: return "Find something new"; case .windows: return "Window layouts"; case .converter: return "Length, weight & more"; case .calculator: return "Everyday arithmetic"; case .audio: return "Volume & output"; case .bookmarks: return "\(kit.utilities.bookmarks.count) saved links"; case .clipboard: return kit.clipboardEnabled ? "\(kit.clipboard.count) recent copies" : "Private, until enabled"; case .clocks: return "Across time zones"; default: return "Open " + kind.title.lowercased() }
    }
    private func eyebrow(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary).lineLimit(1) }
    private func glyph(_ name: String) -> some View { Image(systemName: name).font(.system(size: 22, weight: .regular)).foregroundStyle(model.color).frame(width: 28) }
    private func transport(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).frame(width: 30, height: 30).background(.white.opacity(0.1), in: Circle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
