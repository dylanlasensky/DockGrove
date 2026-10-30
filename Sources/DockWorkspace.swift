import AppKit
import SwiftUI
import Combine

enum DockGeometry {
    static func frame(size: CGSize, screen: CGRect, visible: CGRect, edge: String, alignment: Double, elevation: Double, replacing: Bool) -> CGRect {
        let width = min(size.width, screen.width - 20), height = min(size.height, visible.height - 20)
        let x = screen.minX + 10 + (screen.width - width - 20) * min(1,max(0,alignment))
        let bottom = replacing ? screen.minY : visible.minY
        let y: CGFloat
        if edge == "Top" { y = visible.maxY - height }
        else if edge == "Floating" { y = visible.minY + (visible.height-height) * min(1,max(0,elevation)) }
        else { y = bottom }
        return CGRect(x:x,y:y,width:width,height:height)
    }
    static func reserve(_ visible: CGRect, docks: [CGRect]) -> CGRect {
        var bottom = visible.minY, top = visible.maxY
        for dock in docks where dock.intersects(visible) {
            if abs(dock.minY-visible.minY) < 8 { bottom = max(bottom,dock.maxY) }
            if abs(dock.maxY-visible.maxY) < 8 { top = min(top,dock.minY) }
        }
        return CGRect(x:visible.minX,y:bottom,width:visible.width,height:max(100,top-bottom))
    }
}
@MainActor final class ExtraDock: Identifiable {
    let id: String
    let model: DockModel
    let panel: DockPanel
    let settings: NSWindow
    var visibility = DockVisibility()
    var subscriptions = Set<AnyCancellable>()
    init(id: String, defaults: UserDefaults, index: Int) {
        self.id = id
        if defaults.object(forKey:"dockName") == nil {
            defaults.set("Dock \(index+2)",forKey:"dockName"); defaults.set(index == 0 ? "Top" : "Floating",forKey:"edge")
            defaults.set(["spotify","pet"],forKey:"widgets"); defaults.set([],forKey:"apps"); defaults.set(false,forKey:"showRunning"); defaults.set(false,forKey:"showUsageCard")
            defaults.set(0.35 + Double(index)*0.2,forKey:"elevation")
        }
        model = DockModel(defaults:defaults); model.isAdditionalDock = true
        panel = DockPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenNone,.stationary,.ignoresCycle]
        panel.contentView = NSHostingView(rootView:DockView(model:model))
        settings = NSWindow(contentRect:NSRect(x:0,y:0,width:590,height:720),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        settings.isReleasedWhenClosed = false; settings.contentView = NSHostingView(rootView:SettingsView(model:model)); settings.center()
        model.settingsAction = { [weak self] in self?.showSettings() }
        model.closeSettingsAction = { [weak self] in self?.settings.orderOut(nil) }
    }
    func showSettings() { settings.title = model.dockName; settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
}
@MainActor final class DockWorkspace: ObservableObject {
    @Published var docks: [ExtraDock] = []
    let defaults: UserDefaults
    let prefix: String
    var configure: ((ExtraDock)->Void)?
    init(defaults:UserDefaults, testing:Bool) {
        self.defaults = defaults; prefix = testing ? "DockGroveUITests.dock." : (LicenseConfiguration.commercial ? "com.wavedock.extra." : "com.wavedock.development.extra.")
    }
    func restore() {
        let ids = defaults.stringArray(forKey:"additionalDocks") ?? []
        var seen = Set<String>()
        for id in ids.prefix(3) where UUID(uuidString:id) != nil && seen.insert(id).inserted { append(id) }
    }
    func add() { guard docks.count < 3 else { return }; append(UUID().uuidString); persist() }
    private func append(_ id:String) { let dock = ExtraDock(id:id,defaults:UserDefaults(suiteName:prefix+id)!,index:docks.count); configure?(dock); docks.append(dock) }
    func remove(_ id:String) {
        guard let dock = docks.first(where:{$0.id == id}) else { return }
        dock.panel.orderOut(nil); dock.settings.orderOut(nil); dock.model.toolkit.voiceMemo.stop()
        docks.removeAll { $0.id == id }; persist()
        // Retain scoped data so an accidental removal never deletes notes or recordings.
    }
    private func persist() { defaults.set(docks.map(\.id),forKey:"additionalDocks") }
}
struct DockWorkspaceView: View {
    @ObservedObject var workspace: DockWorkspace
    @ObservedObject var primary: DockModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("A place for every part of your day.").font(.title2.bold())
            Text("Up to four independent docks. Each keeps its own apps, widgets, colors, display, position and page.").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack { Label(primary.dockName,systemImage:"dock.rectangle"); Spacer(); Button("Customize") { primary.settingsAction?() } }
            ForEach(workspace.docks) { dock in DockWorkspaceRow(dock:dock,remove:{workspace.remove(dock.id)}) }
            Button("Add a Dock",action:workspace.add).disabled(workspace.docks.count >= 3)
            Text("Only the primary Dock can replace Apple’s Dock. Extra docks also hide in full screen and when your Mac sleeps. Removing a dock keeps its local data.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(24).frame(width:540)
    }
}
struct DockWorkspaceRow: View {
    let dock: ExtraDock
    @ObservedObject var model: DockModel
    let remove: ()->Void
    init(dock:ExtraDock,remove:@escaping ()->Void) { self.dock=dock; self.model=dock.model; self.remove=remove }
    var body: some View { HStack { TextField("Dock name",text:$model.dockName); Toggle("Visible",isOn:$model.visible); Button("Customize",action:dock.showSettings); Button("Remove",action:remove) }.padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12)) }
}
struct DockAppearanceSettings: View {
    @ObservedObject var model: DockModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            TextField("Dock name",text:$model.dockName).textFieldStyle(.roundedBorder)
            Picker("Appearance",selection:$model.theme) { ForEach(["Automatic","Glass","Graphite","Pearl","System"],id:\.self) { Text($0) } }
            HStack { Text("Maximum width"); Slider(value:$model.widthFraction,in:0.35...1); Text("\(Int(model.widthFraction*100))%").monospacedDigit() }
            HStack { Text("Horizontal position"); Slider(value:$model.alignment,in:0...1) }
            Picker("Position",selection:Binding(get:{model.toolkit.edge},set:{model.toolkit.edge=$0})) { Text("Bottom").tag("Bottom"); Text("Top").tag("Top"); Text("Floating").tag("Floating") }.disabled(model.replacingDock)
            if model.toolkit.edge == "Floating" { HStack { Text("Floating height"); Slider(value:$model.elevation,in:0...1) }; Text("Floating docks stay visible on the desktop; edge auto-hide applies to top and bottom docks.").font(.caption).foregroundStyle(.secondary) }
            Button("Reset position") { model.alignment=0.5; model.elevation=0.5; model.widthFraction=1; model.toolkit.edge=model.isAdditionalDock ? "Top" : "Bottom" }
            Toggle("Show Codex usage tile",isOn:$model.showUsageCard)
            Toggle("Use album colors in music widgets",isOn:$model.albumColors)
            Button("Manage all docks…") { model.manageDocksAction?() }
        }
    }
}
