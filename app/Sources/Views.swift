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
    @State private var lastDrag = CGSize.zero
    @State private var draggedID: String?
    @State private var dragPoint = CGPoint.zero
    @State private var dwell = DragPageDwell()
    @State private var arrowFrames: [Int: CGRect] = [:]
    @State private var dropTarget: String?
    @State private var turnedDuringDrag = false
    @State private var studioDropTarget: String?
    @State private var studioBarTarget = false
    @GestureState private var dragging = false
    private let dragClock = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    var entries: [DockEntry] { model.canUseFeatures ? model.orderedEntries : [] }
    var body: some View {
        let screen = model.selectedScreen
        let widths = entries.map { $0.width(iconSize: model.iconSize, rich: model.toolkit.richWidgets, shapes: model.toolkit.widgetShapes, tileHeight: model.tileHeight) }
        let width = model.toolbarWidth(screenWidth: screen?.frame.width ?? 1440, widths: widths)
        let pages = DockPageLayout.pages(widths: widths, available: width - DockPageLayout.chrome)
        let current = min(page, pages.count - 1)
        HStack(spacing: 8) {
            if !model.canUseFeatures { Button("Activate DockGrove") { model.settingsAction?() } }
            Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 46) }
                .background(arrowGeometry(-1))
                .foregroundStyle(dwell.direction == -1 ? model.color : .primary)
                .disabled(current == 0).help("Previous Dock page; hold a dragged tile here to turn pages").accessibilityLabel("Previous Dock page")
                .dropDestination(for: DockStudioItem.self) { items, _ in
                    acceptStudioPageDrop(items, destination: current - 1, pages: pages)
                }
            HStack(spacing: DockPageLayout.gap) {
                ForEach(pages[current].map { entries[$0] }) { item in
                    tile(item)
                }
                Spacer(minLength: 0)
            }.frame(width: max(1, width - DockPageLayout.chrome), height: model.tileHeight).clipped()
            VStack(spacing: 3) {
                Button { page = min(pages.count - 1, current + 1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 26) }
                    .background(arrowGeometry(1))
                    .foregroundStyle(dwell.direction == 1 ? model.color : .primary)
                    .disabled(current == pages.count - 1).help("Next Dock page; hold a dragged tile here to turn pages").accessibilityLabel("Next Dock page")
                    .dropDestination(for: DockStudioItem.self) { items, _ in
                        acceptStudioPageDrop(items, destination: current + 1, pages: pages)
                    }
                Text("\(current + 1)/\(pages.count)").font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
            }.frame(width: 32)
            Button { model.settingsAction?() } label: { Image(systemName: "slider.horizontal.3").frame(width: 26, height: 46) }
                .help("DockGrove settings").accessibilityLabel("DockGrove settings")
        }
        .contentShape(Rectangle())
        .dropDestination(for: DockStudioItem.self) { items, _ in
            guard items.count == 1 else { return false }
            return model.placeStudioItem(items[0])
        } isTargeted: { studioBarTarget = $0 }
        // This recognizer belongs to the stable Dock, not a tile removed by paging.
        .highPriorityGesture(DragGesture(minimumDistance:8,coordinateSpace:.global)
            .updating($dragging) { _, active, _ in active = true }
            .onChanged { value in
                if draggedID == nil {
                    draggedID = model.tileFrames.first(where: { $0.value.contains(value.startLocation) })?.key
                }
                guard draggedID != nil else { return }
                dragPoint = value.location
                dropTarget = model.tileFrames.first(where: { $0.key != draggedID && $0.value.contains(value.location) })?.key
            }
            .onEnded { value in
                defer { clearDrag() }
                guard let source = draggedID else { return }
                if let target = model.tileFrames.first(where: { $0.key != source && $0.value.contains(value.location) })?.key {
                    withAnimation(.easeInOut(duration:0.18)) { model.moveEntry(source,onto:target) }
                } else if let direction = arrowFrames.first(where: { $0.value.insetBy(dx:-5,dy:-8).contains(value.location) })?.key {
                    let destination = turnedDuringDrag ? current : current + direction
                    guard pages.indices.contains(destination), destination != current || turnedDuringDrag else { return }
                    let candidates = pages[destination].map { entries[$0].id }.filter { $0 != source }
                    guard let target = direction > 0 ? candidates.first : candidates.last else { return }
                    model.moveEntry(source,onto:target)
                    let moved = model.orderedEntries
                    let updated = DockPageLayout.pages(widths:moved.map { $0.width(iconSize:model.iconSize,rich:model.toolkit.richWidgets,shapes:model.toolkit.widgetShapes,tileHeight:model.tileHeight) },available:width-DockPageLayout.chrome)
                    if let index = moved.firstIndex(where: { $0.id == source }), let destinationPage = updated.firstIndex(where: { $0.contains(index) }) { page = destinationPage }
                }
            })
        .onReceive(dragClock) { date in
            guard draggedID != nil, dragging else { return }
            let direction = arrowFrames.first(where: { $0.value.insetBy(dx:-5,dy:-8).contains(dragPoint) })?.key ?? 0
            if let next = dwell.update(direction:direction,page:current,count:pages.count,now:date.timeIntervalSinceReferenceDate) {
                dropTarget = nil
                model.tileFrames.removeAll()
                turnedDuringDrag = true
                page = next
            }
        }
        .onChange(of:dragging) { active in if !active { clearDrag() } }
        .onDisappear { clearDrag() }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: width, height: model.tileHeight + 24)
        .background { DockPlate(theme: model.theme) }
        .overlay(alignment:.top) {
            Capsule().fill(model.color.opacity(0.6)).frame(width:28,height:4).padding(7).contentShape(Rectangle())
                .help("Drag to move this Dock. Replacement docks stay at the bottom.")
                .gesture(DragGesture().onChanged { value in
                    guard let screen else { return }
                    let dx = value.translation.width-lastDrag.width, dy = value.translation.height-lastDrag.height
                    model.alignment = min(1,max(0,model.alignment + dx/max(1,screen.frame.width-width-20)))
                    if !model.replacingDock {
                        if model.toolkit.edge != "Floating" { model.elevation = model.toolkit.edge == "Top" ? 1 : 0; model.toolkit.edge = "Floating" }
                        model.elevation = min(1,max(0,model.elevation-dy/max(1,screen.visibleFrame.height-model.dockHeight)))
                    }
                    lastDrag = value.translation
                }.onEnded { _ in lastDrag = .zero })
        }
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(studioBarTarget ? model.color : Color(nsColor: .separatorColor), lineWidth: studioBarTarget ? 2 : 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 27))
        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
        .overlay(alignment:.top) {
            if let source = entries.first(where: { $0.id == draggedID }) {
                Text("Moving " + source.title).font(.system(size:9,weight:.medium)).padding(.horizontal,8).padding(.vertical,2)
                    .background(.regularMaterial,in:Capsule()).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.primary).preferredColorScheme(model.scheme)
        .onChange(of: entries.map(\.id)) { page = min(page, pages.count - 1) }
    }
    private func tile(_ item: DockEntry) -> some View {
        UnifiedDockTile(item:item,model:model,targeted:dropTarget == item.id || studioDropTarget == item.id,dragged:draggedID == item.id,content:{ entry(item) })
            .frame(width:item.width(iconSize:model.iconSize,rich:model.toolkit.richWidgets,shapes:model.toolkit.widgetShapes,tileHeight:model.tileHeight),height:model.tileHeight)
            .dropDestination(for: DockStudioItem.self) { items, point in
                guard items.count == 1 else { return false }
                let next = model.studioEntries.drop(while: { $0.id != item.id }).dropFirst().first?.id
                let target = item.id == "add" ? nil : point.x < item.width(iconSize: model.iconSize, rich: model.toolkit.richWidgets, shapes: model.toolkit.widgetShapes, tileHeight: model.tileHeight) / 2 ? item.id : next
                return model.placeStudioItem(items[0], before: target)
            } isTargeted: { active in
                if active { studioDropTarget = item.id }
                else if studioDropTarget == item.id { studioDropTarget = nil }
            }
    }
    private func acceptStudioPageDrop(_ items: [DockStudioItem], destination: Int, pages: [[Int]]) -> Bool {
        guard items.count == 1, pages.indices.contains(destination) else { return false }
        let target = pages[destination].map { entries[$0] }.first { $0.id != "add" }?.id
        guard model.placeStudioItem(items[0], before: target) else { return false }
        page = destination
        return true
    }
    private func clearDrag() { draggedID = nil; dropTarget = nil; turnedDuringDrag = false; dwell.reset() }
    private func arrowGeometry(_ direction: Int) -> some View {
        GeometryReader { geometry in
            Color.clear.onAppear { arrowFrames[direction] = geometry.frame(in:.global) }
                .onChange(of:geometry.frame(in:.global)) { arrowFrames[direction] = $0 }
        }
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
    @State private var dropTarget = false
    @StateObject private var interaction = TileInteraction()
    var body: some View {
        VStack(spacing: 4) {
            Button { model.open(app) } label: {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: model.iconSize, height: model.iconSize)
                    .scaleEffect(interaction.hovered ? 1.13 : 1).offset(y: interaction.hovered ? -4 : 0)
            }.buttonStyle(.plain).help(app.name)
            Circle().fill(app.isRunning ? model.color : .clear).frame(width: 4, height: 4)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
            model.acceptFiles(providers, for: app)
        }
        .onHover { interaction.hovered = $0 }
        .animation(.spring(response: 0.23, dampingFraction: 0.65), value: interaction.hovered)
        .contextMenu {
            Button("Windows…") { model.showAppWindows(app) }
            Button("Replace app…") { model.showAppPicker(replacing: app) }
            Button("Undo app change") { model.undoAppChange() }.disabled(model.appHistory.isEmpty)
            Button("Open \(app.name)") { model.open(app) }
            Divider()
            Button("Move left") { model.move(app, by: -1) }.disabled(model.apps.first == app)
            Button("Move right") { model.move(app, by: 1) }.disabled(model.apps.last == app)
            Divider()
            if model.apps.contains(app) { Button("Unpin") { model.remove(app) } }
            else { Button("Pin to Dock") { model.pin(app) } }
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL.path == app.id }) {
                Button(running.isHidden ? "Show app" : "Hide app") { if running.isHidden { running.unhide() } else { running.hide() } }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            Button("Quit app") { NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == app.id }?.terminate() }.disabled(!app.isRunning)
        }
    }
}

struct UsageTile: View {
    @ObservedObject var model: DockModel
    @State private var dropTarget = false
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
                    else { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                }.font(.system(size: 10))
                if let bucket = model.activeBucket {
                    if let primary = bucket.primary { MiniMeter(window: primary, color: model.color) }
                    else if let secondary = bucket.secondary { MiniMeter(window: secondary, color: model.color) }
                } else {
                    HStack {
                        Text(model.usageError != nil ? "Connection unavailable" : "Connect your usage").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }.foregroundStyle(.secondary)
                }
            }.padding(.horizontal, model.toolkit.richWidgets ? 12 : 0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).modifier(WidgetSurface())
        }.buttonStyle(.plain)
        .popover(isPresented: $interaction.expanded, arrowEdge: model.toolkit.edge == "Top" ? .bottom : .top) { UsageDetails(model: model).padding(22).frame(width: 335).preferredColorScheme(model.scheme) }
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
                Text(window.title).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(window.remaining < 15 ? .orange : color).frame(width: geometry.size.width * window.remaining / 100)
                }
            }.frame(height: 4)
        }
    }
}

struct UsageDetails: View {
    @ObservedObject var model: DockModel
    var showAccountSettings = true
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
                Button("Refresh") { model.refreshUsage() }.disabled(model.fetching).buttonStyle(.borderedProminent).tint(model.color)
                Spacer()
                if showAccountSettings { Button("Account settings") { model.openCodexConnection() }.buttonStyle(.bordered) }
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

struct UnifiedDockTile<Content:View>: View {
    let item:DockEntry
    @ObservedObject var model:DockModel
    var targeted: Bool
    var dragged: Bool
    @ViewBuilder var content:()->Content
    var body:some View {
        content().contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius:14).stroke(targeted ? model.color : .clear,lineWidth:2))
            .background(GeometryReader { geometry in
                Color.clear.onAppear { model.tileFrames[item.id]=geometry.frame(in:.global) }
                    .onChange(of:geometry.frame(in:.global)) { model.tileFrames[item.id]=$0 }
            })
            .opacity(dragged ? 0.45 : 1)
            .onDisappear { model.tileFrames.removeValue(forKey:item.id) }

    }
}
