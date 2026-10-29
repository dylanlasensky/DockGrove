import AppKit
import SwiftUI
import ApplicationServices

enum SnapZone {
    /// AppKit screen coordinates; placement frames use Accessibility coordinates.
    static func placement(at p: CGPoint, screen: CGRect) -> WindowPlacement? {
        guard screen.insetBy(dx:-2,dy:-2).contains(p) else { return nil }
        let left=p.x <= screen.minX+14, right=p.x >= screen.maxX-14
        let top=p.y >= screen.maxY-14, bottom=p.y <= screen.minY+14
        if (left || right) && p.y >= screen.maxY-70 { return left ? .topLeft : .topRight }
        if (left || right) && p.y <= screen.minY+70 { return left ? .bottomLeft : .bottomRight }
        if left { return .left }; if right { return .right }
        if top { return .maximize }; if bottom { return .bottom }
        return nil
    }
}
struct SnapDwell {
    var zone: String?
    var since=Date.distantPast
    mutating func ready(_ next:String?, now:Date) -> Bool {
        guard let next else { zone=nil; return false }
        if zone != next { zone=next; since=now; return false }
        return now.timeIntervalSince(since) >= 0.18
    }
}
@MainActor final class WindowSnapper {
    private weak var model: DockModel?
    private var timer: Timer?
    private var keyMonitor: Any?
    private var pressed=false
    private var cancelled=false
    private var generation=0
    private var checking=false
    private var window: ManagedWindow?
    private var original: CGRect?
    private var target: CGRect?
    private var targetScreen: CGRect?
    private var targetPlacement: WindowPlacement?
    private var dwell=SnapDwell()
    private var preview: NSPanel?
    init(model:DockModel) { self.model=model }
    func start() {
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        keyMonitor=NSEvent.addGlobalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.cancel(); self?.cancelled=true } }
        }
    }
    func cancel() { generation += 1; window=nil; original=nil; target=nil; targetScreen=nil; targetPlacement=nil; dwell=SnapDwell(); preview?.orderOut(nil); checking=false }
    private func tick() {
        let down=NSEvent.pressedMouseButtons & 1 != 0
        defer { pressed=down }
        guard let model, model.snappingEnabled, model.toolkit.windows.trusted else { cancel(); return }
        if down && !pressed {
            cancelled=false; cancel()
            let point=NSEvent.mouseLocation, globalTop=NSScreen.screens.first?.frame.maxY ?? 0, request=generation
            Task {
                let result=await Task.detached(priority:.userInitiated) { Self.windowAt(CGPoint(x:point.x,y:globalTop-point.y)) }.value
                guard request == generation, NSEvent.pressedMouseButtons & 1 != 0 else { return }
                window=result?.0; original=result?.1
            }
        }
        if !down {
            if pressed, !cancelled, let window, let target, let original,
               let targetScreen, let targetPlacement, SnapZone.placement(at:NSEvent.mouseLocation,screen:targetScreen) == targetPlacement,
               !model.snapRequiresOption || NSEvent.modifierFlags.contains(.option) {
                model.toolkit.windows.snap(window,target:target,original:original)
            }
            cancel(); return
        }
        guard !cancelled, !checking, let window, let original else { return }
        guard !model.snapRequiresOption || NSEvent.modifierFlags.contains(.option),
              let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}),
              let placement=SnapZone.placement(at:NSEvent.mouseLocation,screen:screen.frame) else { target=nil; dwell=SnapDwell(); preview?.orderOut(nil); return }
        let zone=DockModel.displayID(screen)+placement.rawValue
        guard dwell.ready(zone,now:Date()) else { target=nil; preview?.orderOut(nil); return }
        checking=true; let request=generation
        Task {
            let current=await Task.detached(priority:.userInitiated) { WindowManager.bounds(window.element) }.value
            guard request == generation else { return }; checking=false
            guard NSEvent.pressedMouseButtons & 1 != 0, let current,
                  abs(current.minX-original.minX)+abs(current.minY-original.minY) > 8,
                  abs(current.width-original.width) < 5, abs(current.height-original.height) < 5,
                  screen.frame.contains(NSEvent.mouseLocation), SnapZone.placement(at:NSEvent.mouseLocation,screen:screen.frame) == placement else { target=nil; preview?.orderOut(nil); return }
            let usable=model.toolkit.windows.usableFrameProvider?(screen) ?? WindowManager.usableFrame(screen:screen,dockHeight:0)
            target=placement.frame(in:usable,current:current); targetScreen=screen.frame; targetPlacement=placement
            showPreview(target!)
        }
    }
    private func showPreview(_ rect:CGRect) {
        if preview == nil {
            let panel=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque=false; panel.backgroundColor = .clear; panel.level = .floating; panel.ignoresMouseEvents=true; panel.hasShadow=false
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenNone,.ignoresCycle]
            panel.contentView=NSHostingView(rootView:RoundedRectangle(cornerRadius:14).fill(Color.accentColor.opacity(0.15)).overlay(RoundedRectangle(cornerRadius:14).stroke(Color.accentColor.opacity(0.8),lineWidth:2)).padding(3))
            preview=panel
        }
        let top=NSScreen.screens.first?.frame.maxY ?? 0
        preview?.setFrame(CGRect(x:rect.minX,y:top-rect.maxY,width:rect.width,height:rect.height),display:true); preview?.orderFrontRegardless()
    }
    nonisolated static func windowAt(_ point:CGPoint) -> (ManagedWindow,CGRect)? {
        let system=AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system,0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system,Float(point.x),Float(point.y),&hit) == .success, let hit else { return nil }
        var value:CFTypeRef?, role:CFTypeRef?
        AXUIElementCopyAttributeValue(hit,kAXRoleAttribute as CFString,&role)
        let element:AXUIElement
        if role as? String == kAXWindowRole { element=hit }
        else { guard AXUIElementCopyAttributeValue(hit,kAXWindowAttribute as CFString,&value) == .success, let value, CFGetTypeID(value)==AXUIElementGetTypeID() else { return nil }; element=value as! AXUIElement }
        AXUIElementSetMessagingTimeout(element,0.3)
        var pid:pid_t=0; AXUIElementGetPid(element,&pid)
        guard pid != ProcessInfo.processInfo.processIdentifier, let app=NSRunningApplication(processIdentifier:pid), app.activationPolicy == .regular,
              let bounds=WindowManager.bounds(element), point.y >= bounds.minY, point.y <= bounds.minY+40 else { return nil }
        var full:CFTypeRef?; AXUIElementCopyAttributeValue(element,"AXFullScreen" as CFString,&full)
        guard (full as? Bool) != true else { return nil }
        var title:CFTypeRef?; AXUIElementCopyAttributeValue(element,kAXTitleAttribute as CFString,&title)
        return (ManagedWindow(id:"\(pid):\(CFHash(element))",owner:app,element:element,title:(app.localizedName ?? "App")+" · "+(title as? String ?? "Window")),bounds)
    }
    deinit { timer?.invalidate(); if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}
struct SnapSettings: View {
    @ObservedObject var model:DockModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Window snapping",systemImage:"rectangle.split.2x2").font(.headline)
            Toggle("Snap dragged windows to screen edges",isOn:$model.snappingEnabled)
            Toggle("Require Option while dragging",isOn:$model.snapRequiresOption)
            Text("Drag a window by its title bar. Hold at an edge for the preview, then release: sides for halves, corners for quarters, top for maximize. Escape cancels. Undo is in the Windows widget. Option avoids competing with macOS tiling.").font(.caption).foregroundStyle(.secondary)
            if !model.toolkit.windows.trusted { Button("Allow Accessibility",action:model.toolkit.windows.requestAccess) }
        }.padding(18).background(.quaternary,in:RoundedRectangle(cornerRadius:16))
    }
}
