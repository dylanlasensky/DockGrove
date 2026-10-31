import SwiftUI
import AppKit

extension DockEntry {
    static let applicationsID = "applications"
}

extension DockModel {
    /// The Applications stack always leads the Dock; it sits outside `entryOrder` so it cannot be reordered away.
    var dockEntries: [DockEntry] { (showApplicationsStack ? [.applications] : []) + orderedEntries }
}

struct ApplicationsStackTile: View {
    @ObservedObject var model: DockModel
    @StateObject private var interaction = TileInteraction()
    private static let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    var body: some View {
        VStack(spacing: 4) {
            Button { interaction.expanded.toggle() } label: {
                Image(nsImage: Self.folderIcon).resizable().interpolation(.high).frame(width: model.iconSize, height: model.iconSize)
                    .scaleEffect(interaction.hovered ? 1.13 : 1).offset(y: interaction.hovered ? -4 : 0)
            }.buttonStyle(.plain).help("Applications").accessibilityLabel("Applications")
            Circle().fill(.clear).frame(width: 4, height: 4)
        }
        .onHover { interaction.hovered = $0 }
        .animation(.spring(response: 0.23, dampingFraction: 0.65), value: interaction.hovered)
        .popover(isPresented: $interaction.expanded, arrowEdge: model.toolkit.edge == "Top" ? .bottom : .top) {
            ApplicationsGrid(model: model, kit: model.toolkit) { interaction.expanded = false }.preferredColorScheme(model.scheme)
        }
        .contextMenu {
            Button("Open Applications Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
            Button("Refresh Applications") { model.toolkit.scanApplications(force: true) }
        }
    }
}

struct ApplicationsGrid: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    var close: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private let columns = Array(repeating: GridItem(.fixed(84), spacing: 10), count: 6)
    private var results: [DockApp] { kit.appIndex.search(query) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Applications").font(.title3.bold())
                Spacer()
                if kit.scanningApps { ProgressView().controlSize(.small).accessibilityLabel("Refreshing applications") }
                Text("\(results.count) of \(kit.appIndex.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search applications", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { if let first = results.first { launch(first) } }
                if !query.isEmpty {
                    Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search").help("Clear search")
                }
            }.padding(8).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(results) { app in
                        Button { launch(app) } label: {
                            VStack(spacing: 5) {
                                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 56, height: 56)
                                Text(kit.appIndex.name(of: app)).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center).frame(height: 28, alignment: .top)
                            }.frame(width: 84).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(app.id)
                        .contextMenu {
                            Button("Open") { launch(app) }
                            Button("Pin to Dock") { model.pin(app) }.disabled(model.apps.contains(app))
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                        }
                    }
                }.padding(.vertical, 4)
            }
            .overlay {
                if results.isEmpty {
                    VStack(spacing: 6) {
                        if kit.scanningApps && kit.appIndex.count == 0 { ProgressView("Finding installed applications…") }
                        else { Text(query.isEmpty ? "No applications found" : "No matching applications").font(.headline).foregroundStyle(.secondary) }
                    }.allowsHitTesting(false)
                }
            }
        }
        .padding(18).frame(width: 600, height: 470)
        .onAppear { kit.scanApplications(force: true); searchFocused = true }
    }
    private func launch(_ app: DockApp) { kit.recordLaunch(app, query: query); model.open(app); close() }
}
