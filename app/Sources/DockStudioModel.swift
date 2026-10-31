import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let dockStudioItem = UTType(exportedAs: "com.dylan.wavedock.studio-item", conformingTo: .data)
}

struct DockStudioItem: Codable, Transferable, Equatable {
    enum Kind: String, Codable { case app, widget, clock, usage }
    var kind: Kind
    var value: String
    var shape: String? = nil
    var id: String {
        switch kind { case .app: return "app:" + value; case .widget: return value; case .clock: return "clock"; case .usage: return "usage" }
    }
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dockStudioItem)
    }
    init(kind: Kind, value: String = "") { self.kind = kind; self.value = value }
    init?(_ entry: DockEntry) {
        switch entry {
        case .app(let app): self.init(kind: .app, value: app.id)
        case .tool(let tool): self.init(kind: .widget, value: tool.rawValue)
        case .clock: self.init(kind: .clock)
        case .usage: self.init(kind: .usage)
        case .add, .applications: return nil
        }
    }
}

struct DockStudioSnapshot {
    var apps: [DockApp]
    var widgets: [String]
    var order: [String]
    var clock: Bool
    var usage: Bool
    var shapes: [String: String]
    var iconSize: Double
    var widthFraction: Double
    var toolbarHeight: Double
    var fitToolbarToContent: Bool
}

extension DockModel {
    var studioEntries: [DockEntry] { orderedEntries.filter { DockStudioItem($0) != nil } }
    func rememberStudioLayout() {
        studioHistory.append(DockStudioSnapshot(apps: apps, widgets: toolkit.enabled, order: entryOrder, clock: showClock, usage: showUsageCard, shapes: toolkit.widgetShapes, iconSize: iconSize, widthFraction: widthFraction, toolbarHeight: toolbarHeight, fitToolbarToContent: fitToolbarToContent))
        if studioHistory.count > 30 { studioHistory.removeFirst() }
    }
    func undoStudioLayout() {
        guard let snapshot = studioHistory.popLast() else { return }
        apps = snapshot.apps; toolkit.enabled = snapshot.widgets; entryOrder = snapshot.order
        toolkit.widgetShapes = snapshot.shapes
        iconSize = snapshot.iconSize; widthFraction = snapshot.widthFraction
        toolbarHeight = snapshot.toolbarHeight; fitToolbarToContent = snapshot.fitToolbarToContent
        showClock = snapshot.clock; showUsageCard = snapshot.usage; persistApps()
    }

    /// Validate before changing anything: imported drags cannot bypass purchases.
    @discardableResult func placeStudioItem(_ item: DockStudioItem, before target: String? = nil) -> Bool {
        guard canUseFeatures, item.id != target else { return false }
        if let target, !studioEntries.contains(where: { $0.id == target }) { return false }
        if let shape = item.shape, WidgetShapeStyle(rawValue: shape) == nil { return false }
        switch item.kind {
        case .widget:
            guard let kind = ToolKind(rawValue: item.value), canAccess(kind) else { return false }
        case .app:
            guard item.value.hasPrefix("/") else { return false }
            let url = URL(fileURLWithPath: item.value).standardizedFileURL
            var directory: ObjCBool = false
            guard url.path == item.value, url.pathExtension.lowercased() == "app",
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { return false }
        case .usage: guard canAccessAI else { return false }
        case .clock: break
        }
        rememberStudioLayout()
        switch item.kind {
        case .widget:
            toolkit.toggle(ToolKind(rawValue: item.value)!, true)
            if let shape = item.shape { toolkit.widgetShapes[item.value] = shape }
        case .app:
            let app = DockApp(url: URL(fileURLWithPath: item.value))
            if !apps.contains(app) { apps.append(app); persistApps() }
        case .clock: showClock = true
        case .usage: showUsageCard = true
        }
        var order = studioEntries.map(\.id).filter { $0 != item.id }
        let insertion = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(item.id, at: insertion)
        // Keep temporarily locked/hidden items so restoring access restores layout.
        entryOrder = order + entryOrder.filter { !order.contains($0) }
        return true
    }

    @discardableResult func removeStudioItem(_ item: DockStudioItem) -> Bool {
        guard canUseFeatures else { return false }
        switch item.kind {
        case .widget: guard toolkit.enabled.contains(item.value) else { return false }
        case .app: guard apps.contains(where: { $0.id == item.value }) else { return false }
        case .clock: guard showClock else { return false }
        case .usage: guard showUsageCard else { return false }
        }
        rememberStudioLayout()
        switch item.kind {
        case .widget: toolkit.enabled.removeAll { $0 == item.value }
        case .app: apps.removeAll { $0.id == item.value }; persistApps()
        case .clock: showClock = false
        case .usage: showUsageCard = false
        }
        entryOrder.removeAll { $0 == item.id }
        return true
    }
}
