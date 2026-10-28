import AppKit
import SwiftUI
import Combine

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: DockModel!
    var panel: DockPanel!
    var settings: NSWindow!
    var status: NSStatusItem!
    var subscriptions = Set<AnyCancellable>()
    var visibilityTimer: Timer?
    var lastInside = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Settings", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit WaveDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        model = DockModel()
        do { try SystemDock.restore() } catch { model.systemError = "Could not restore the original Dock setting. Use Restore Apple Dock to retry." }
        model.settingsAction = { [weak self] in self?.showSettings() }
        model.closeSettingsAction = { [weak self] in self?.settings.orderOut(nil) }
        model.changeDockAction = { [weak self] enabled in self?.setReplacement(enabled) }
        model.visibilityAction = { [weak self] in self?.updateVisibility() }
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DockView(model: model))
        settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        settings.title = "WaveDock"; settings.isReleasedWhenClosed = false
        settings.contentView = NSHostingView(rootView: SettingsView(model: model))
        settings.center()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "WaveDock")
        let menu = NSMenu()
        for (title, action, key) in [("Settings…", #selector(showSettings), ","), ("Show / hide WaveDock", #selector(toggleVisibility), "d"), ("Refresh usage", #selector(refresh), "r"), ("Restore Apple Dock", #selector(restore), ""), ("Quit WaveDock", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        model.objectWillChange.debounce(for: .milliseconds(60), scheduler: RunLoop.main).sink { [weak self] _ in self?.layoutDock() }.store(in: &subscriptions)
        model.toolkit.objectWillChange.debounce(for: .milliseconds(60), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.model.objectWillChange.send()
        }.store(in: &subscriptions)
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkAutoHide() } }
        NotificationCenter.default.addObserver(self, selector: #selector(layoutDock), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        layoutDock(); panel.orderFrontRegardless()
        if !model.defaults.bool(forKey: "hasLaunched02") { showSettings(); model.defaults.set(true, forKey: "hasLaunched02") }
    }
    @objc func layoutDock() {
        guard !NSScreen.screens.isEmpty, let view = panel?.contentView else { return }
        let screen = NSScreen.screens[min(max(0, model.toolkit.screenIndex), NSScreen.screens.count - 1)]
        view.invalidateIntrinsicContentSize()
        let fitted = view.fittingSize
        let width = min(fitted.width, screen.frame.width - 20)
        let height = fitted.height
        // Above the Apple Dock in preview mode; along the bottom in replacement mode.
        let bottom = model.replacingDock ? screen.frame.minY : screen.visibleFrame.minY
        let y = model.toolkit.edge == "Top" ? screen.visibleFrame.maxY - height : bottom
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: y, width: width, height: height), display: true)
    }
    func checkAutoHide() {
        guard let panel = panel, model.visible else { return }
        if !model.toolkit.autoHide || settings.isVisible || !(panel.childWindows ?? []).isEmpty {
            panel.alphaValue = 1; panel.ignoresMouseEvents = false; lastInside = Date(); return
        }
        let mouse = NSEvent.mouseLocation
        if panel.frame.contains(mouse) { lastInside = Date() }
        let show = Date().timeIntervalSince(lastInside) < 1.0
        panel.ignoresMouseEvents = !show
        NSAnimationContext.runAnimationGroup { context in context.duration = 0.16; panel.animator().alphaValue = show ? 1 : 0.03 }
    }
    @objc func showSettings() { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleVisibility() { model.visible.toggle(); updateVisibility() }
    func updateVisibility() { if model.visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) } }
    @objc func refresh() { model.refreshUsage() }
    @objc func restore() { setReplacement(false) }
    @objc func quit() { NSApp.terminate(nil) }
    func setReplacement(_ enabled: Bool) {
        do {
            if enabled { try SystemDock.hide() } else { try SystemDock.restore() }
            model.replacingDock = enabled; model.systemError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.layoutDock() }
        } catch { model.systemError = "Could not change Apple's Dock setting. Your saved original setting is retained for recovery." }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try SystemDock.restore(); return .terminateNow }
        catch {
            let alert = NSAlert(); alert.messageText = "Apple Dock could not be restored"
            alert.informativeText = "You can retry, or quit and turn off auto-hide in System Settings > Desktop & Dock. The original setting stays saved for the next WaveDock launch."
            alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "Quit anyway")
            if alert.runModal() == .alertFirstButtonReturn { do { try SystemDock.restore(); return .terminateNow } catch { return .terminateCancel } }; return .terminateNow
        }
    }
}

@main struct WaveDockMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { runSelfTests(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
