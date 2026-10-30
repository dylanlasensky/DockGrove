import SwiftUI
import AppKit

extension ToolKind {
    var studioCategory: String {
        switch self {
        case .pet: return "Companions"
        case .claudeCodeUsage, .geminiUsage, .openaiUsage, .anthropicUsage, .cursorUsage, .github: return "Developer"
        case .music, .spotify, .appleMusic, .audio, .voiceMemo: return "Media"
        case .focus, .notes, .tasks, .calendar, .googleCalendar, .reminders, .habits, .progress: return "Productivity"
        default: return "Everyday"
        }
    }
    var studioColor: Color {
        switch studioCategory {
        case "Companions": return .orange
        case "Developer": return .purple
        case "Media": return .pink
        case "Productivity": return .blue
        default: return .teal
        }
    }
    var studioExample: String {
        switch self {
        case .calculator: return "24 × 7 = 168"
        case .currency: return "USD → EUR"
        case .voiceMemo: return "Ready to record"
        case .audio: return "Built-in speakers"
        case .appGroups: return "Your work essentials"
        case .webSearch: return "A little curiosity…"
        case .search: return "Find an application"
        case .files: return "Everything at hand"
        case .clipboard: return "Your recent copies"
        case .bookmarks: return "Your favorite places"
        case .folders: return "Downloads · 3 files"
        case .stopwatch: return "00:42.8"
        case .habits: return "A little, every day"
        case .progress: return "Make today count"
        case .clocks: return "London · 4:30 PM"
        case .converter: return "10 km → 6.21 mi"
        case .capture: return "Capture a moment"
        case .colors: return "#6EA9FF"
        case .controls: return "Your Mac, at a glance"
        case .reminders: return "A fresh start"
        case .windows: return "Room to focus"
        default: return title
        }
    }
}

/// Presentation only: browsing a gallery never starts a microphone, monitor,
/// permission prompt, network request, or a third-party application.
struct WidgetShowcase: View {
    let kind: ToolKind
    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .pet:
                CatPortrait(resting: false, animal: "Miso", accent: .orange).frame(width: 60, height: 54)
                VStack(alignment: .leading, spacing: 4) { Text("A little company").font(.system(size: 11, weight: .semibold)); Text("Happy to see you").font(.system(size: 9)).foregroundStyle(.secondary) }
            case .weather:
                Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 29))
                VStack(alignment: .leading, spacing: 2) { Text("72°").font(.system(size: 27, weight: .medium, design: .rounded)); Text("Partly cloudy").font(.system(size: 9)).foregroundStyle(.secondary) }
            case .focus, .stopwatch:
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(kind == .focus ? "TIME TO FOCUS" : "STOPWATCH")
                    Text(kind == .focus ? "25:00" : "00:42.8").font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(kind.studioColor)
            case .music, .spotify, .appleMusic:
                RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48).overlay(Image(systemName: "music.note").font(.title2).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your soundtrack").font(.system(size: 11, weight: .semibold))
                    Text("A moment for you").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack(spacing: 13) { Image(systemName: "backward.fill"); Image(systemName: "play.fill"); Image(systemName: "forward.fill") }.font(.system(size: 9))
                }
            case .calendar, .googleCalendar:
                VStack(spacing: 1) { Text("FRI").font(.system(size: 9, weight: .bold)).foregroundStyle(.red); Text("30").font(.system(size: 25, weight: .light)) }.frame(width: 38)
                VStack(alignment: .leading, spacing: 4) { Text("Room for good work").font(.system(size: 11, weight: .semibold)); Text("10:00 · Planning time").font(.system(size: 9)).foregroundStyle(.secondary) }
            case .tasks, .reminders, .habits:
                VStack(alignment: .leading, spacing: 5) {
                    eyebrow(kind.title.uppercased())
                    Label("Make something great", systemImage: "circle").font(.system(size: 10))
                    Label("Take a little break", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .notes:
                VStack(alignment: .leading, spacing: 4) { eyebrow("A QUICK THOUGHT"); Text("Small ideas.\nWonderful possibilities.").font(.system(size: 11)).lineSpacing(2) }
            case .system, .progress:
                VStack(alignment: .leading, spacing: 5) {
                    HStack { eyebrow(kind == .system ? "CPU" : "TODAY"); Spacer(); Text(kind == .system ? "24%" : "62%").font(.system(size: 10, weight: .semibold)) }
                    Sparkline(values: [12, 18, 15, 28, 23, 35, 24, 30, 26, 24], color: kind.studioColor).frame(height: 26)
                }
            case .water:
                RingMetric(value: 0.6, label: "3", color: .cyan).frame(width: 43, height: 43)
                VStack(alignment: .leading, spacing: 4) { Text("Stay hydrated").font(.system(size: 11, weight: .semibold)); Text("3 of 5 glasses").font(.system(size: 9)).foregroundStyle(.secondary) }
            case .github:
                VStack(alignment: .leading, spacing: 5) { eyebrow("GITHUB"); Label("All checks passed", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green); Text("Your next great project").font(.system(size: 9)).foregroundStyle(.secondary) }
            case .claudeCodeUsage, .geminiUsage, .openaiUsage, .anthropicUsage, .cursorUsage:
                VStack(alignment: .leading, spacing: 5) { eyebrow(kind.title.uppercased()); Text("Room to create").font(.system(size: 12, weight: .semibold)); ProgressView(value: 0.68).tint(.purple) }
            case .spacer:
                HStack(spacing: 8) { Image(systemName: "arrow.left"); Text("A little breathing room"); Image(systemName: "arrow.right") }.font(.system(size: 10)).foregroundStyle(.secondary)
            case .separator:
                Spacer(); Rectangle().fill(.secondary.opacity(0.4)).frame(width: 1, height: 40); Spacer()
            default:
                Image(systemName: kind.icon).font(.system(size: 25, weight: .medium)).foregroundStyle(kind.studioColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) { eyebrow(kind.title.uppercased()); Text(kind.studioExample).font(.system(size: 11, weight: .medium)).lineLimit(2) }
            }
        }.padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .modifier(WidgetSurface())
            .accessibilityElement(children: .ignore).accessibilityLabel(kind.title + " sample preview")
    }
    private func eyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(.secondary).lineLimit(1)
    }
}

struct StudioEntryPreview: View {
    let entry: DockEntry
    @ObservedObject var model: DockModel
    var body: some View {
        Group {
            switch entry {
            case .app(let app):
                VStack(spacing: 3) {
                    Image(nsImage: app.icon).resizable().frame(width: model.iconSize, height: model.iconSize)
                    Circle().fill(app.isRunning ? Color.primary.opacity(0.7) : .clear).frame(width: 3, height: 3)
                }
            case .tool(let kind):
                if kind == .separator { Divider().frame(height: 42) }
                else if kind == .spacer { Image(systemName: "arrow.left.and.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
                else if model.toolkit.shape(for: kind) != .rounded {
                    ShapedWidgetFace(kind: kind, style: model.toolkit.shape(for: kind), caption: kind == .focus ? "25:00" : kind == .weather ? "72°" : kind.title, accent: model.color)
                }
                else if model.toolkit.richWidgets { WidgetShowcase(kind: kind) }
                else { VStack(spacing: 5) { Image(systemName: kind.icon).font(.system(size: 20)); Text(kind.title).font(.system(size: 9)).lineLimit(1) }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(WidgetSurface(radius: 12)) }
            case .clock:
                VStack(alignment: .leading, spacing: 4) { Text(Date(), style: .time).font(.system(size: 19, weight: .medium, design: .rounded)); Text(Date(), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.system(size: 9)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(WidgetSurface())
            case .usage:
                VStack(alignment: .leading, spacing: 5) { Text("CODEX USAGE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary); Text("68% remaining").font(.system(size: 14, weight: .semibold)); ProgressView(value: 0.68).tint(.purple) }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity).modifier(WidgetSurface())
            case .add: EmptyView()
            }
        }.frame(width: max(12, entry.width(iconSize: model.iconSize, rich: model.toolkit.richWidgets, shapes: model.toolkit.widgetShapes, tileHeight: model.tileHeight)), height: model.tileHeight)
    }
}

struct DockStudioPreview: View {
    @ObservedObject var model: DockModel
    @State private var page = 0
    @State private var endTarget = false
    @State private var removeTarget = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("YOUR DOCK", systemImage: "dock.rectangle").font(.system(size: 10, weight: .bold)).tracking(1)
                Text(model.dockName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.undoStudioLayout() } label: { Label("Undo layout", systemImage: "arrow.uturn.backward") }.disabled(model.studioHistory.isEmpty).controlSize(.small)
            }
            GeometryReader { geometry in
                let entries = model.studioEntries
                let widths = entries.map { max(12, $0.width(iconSize: model.iconSize, rich: model.toolkit.richWidgets, shapes: model.toolkit.widgetShapes, tileHeight: model.tileHeight)) } + [42]
                let natural = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * DockPageLayout.gap + 112
                let requested = min(geometry.size.width, max((widths.max() ?? 236) + 112, geometry.size.width * model.widthFraction))
                let previewWidth = model.fitToolbarToContent ? min(requested, natural) : requested
                let pages = DockPageLayout.pages(widths: widths, available: max(1, previewWidth - 112))
                let current = min(page, pages.count - 1)
                HStack(spacing: 10) {
                    Button { page = max(0, current - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 24, height: 64)
                    }.disabled(current == 0).accessibilityLabel("Previous preview page")
                    HStack(spacing: DockPageLayout.gap) {
                        ForEach(pages[current], id: \.self) { index in
                            if entries.indices.contains(index) {
                                StudioDraggableTile(entry: entries[index], nextID: entries.dropFirst(index + 1).first?.id, model: model)
                            } else {
                                RoundedRectangle(cornerRadius: 13).strokeBorder(endTarget ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                    .overlay(Image(systemName: "plus").foregroundStyle(endTarget ? Color.accentColor : .secondary))
                                    .frame(width: 42, height: 58)
                                    .dropDestination(for: DockStudioItem.self) { items, _ in
                                        guard items.count == 1 else { return false }; return model.placeStudioItem(items[0])
                                    } isTargeted: { endTarget = $0 }
                                    .accessibilityLabel("Drop here to add at the end of your Dock")
                            }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 4) {
                        Button { page = min(pages.count - 1, current + 1) } label: {
                            Image(systemName: "chevron.right").frame(width: 24, height: 40)
                        }.disabled(current == pages.count - 1).accessibilityLabel("Next preview page")
                        Text("\(current + 1)/\(pages.count)").font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                    }.frame(width: 32)
                }.buttonStyle(.plain).padding(14).frame(width: previewWidth, height: geometry.size.height)
                    .background { DockPlate(theme: model.theme) }
                    .frame(maxWidth: .infinity)
                    .onChange(of: pages.count) { _, count in page = min(page, count - 1) }
            }.frame(height: model.tileHeight + 28).padding(.vertical, 8)
            HStack {
                Text("Drag cards here or onto your Dock. Use the arrows to see every tile.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Label("Drop to remove", systemImage: "trash").font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(removeTarget ? Color.red.opacity(0.14) : Color.secondary.opacity(0.08), in: Capsule())
                    .foregroundStyle(removeTarget ? .red : .secondary)
                    .dropDestination(for: DockStudioItem.self) { items, _ in
                        guard items.count == 1 else { return false }; return model.removeStudioItem(items[0])
                    } isTargeted: { removeTarget = $0 }
            }
        }.padding(18)
            .background(LinearGradient(colors: [Color.accentColor.opacity(0.09), Color.secondary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.primary.opacity(0.07)))
    }
}

private struct StudioDraggableTile: View {
    let entry: DockEntry
    let nextID: String?
    @ObservedObject var model: DockModel
    @State private var targeted = false
    var body: some View {
        StudioEntryPreview(entry: entry, model: model)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(targeted ? Color.accentColor : .clear, lineWidth: 2))
            .draggable(model.studioItem(entry)!) { StudioEntryPreview(entry: entry, model: model) }
            .dropDestination(for: DockStudioItem.self) { items, point in
                guard items.count == 1 else { return false }
                let width = max(12, entry.width(iconSize: model.iconSize, rich: model.toolkit.richWidgets, shapes: model.toolkit.widgetShapes, tileHeight: model.tileHeight))
                return model.placeStudioItem(items[0], before: point.x < width / 2 ? entry.id : nextID)
            } isTargeted: { targeted = $0 }
            .contextMenu {
                if case .tool(let kind) = entry, kind != .spacer, kind != .separator {
                    Menu("Widget shape") {
                        ForEach(WidgetShapeStyle.allCases) { shape in
                            Button(shape.title) { model.setWidgetShape(shape, for: kind) }
                        }
                    }
                    Divider()
                }
                Button("Move to start") { _ = model.placeStudioItem(model.studioItem(entry)!, before: model.studioEntries.first?.id) }
                Button("Move to end") { _ = model.placeStudioItem(model.studioItem(entry)!) }
                Divider()
                Button("Remove from Dock") { _ = model.removeStudioItem(model.studioItem(entry)!) }
            }
            .help(entry.title + " · Drag to reorder or right-click for options")
            .accessibilityLabel(entry.title + ", Dock preview tile")
    }
}
