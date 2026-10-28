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
    var visibility = DockVisibility()
    var sessionActive = true
    var screenAwake = true
    var settlingUntil = Date.distantPast
    let testing = CommandLine.arguments.contains("--ui-test") || CommandLine.arguments.contains("--native-test")

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !testing, let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem)
        appMenu.addItem(withTitle: "Close Settings", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit WaveDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        model = DockModel(defaults: testing ? UserDefaults(suiteName: "WaveDockUITests")! : .standard)
        do { if !testing { try SystemDock.restore() } } catch { model.systemError = "Could not restore the original Dock setting. Use Restore Apple Dock to retry." }
        model.settingsAction = { [weak self] in self?.showSettings() }
        model.closeSettingsAction = { [weak self] in self?.settings.orderOut(nil) }
        model.changeDockAction = { [weak self] enabled in self?.setReplacement(enabled) }
        model.visibilityAction = { [weak self] in self?.updateVisibility() }
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        // Never join another application's native full-screen Space or Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
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
        model.toolkit.utilities.objectWillChange.debounce(for: .milliseconds(60), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.model.objectWillChange.send()
        }.store(in: &subscriptions)
        model.toolkit.github.objectWillChange.debounce(for: .milliseconds(60), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.model.objectWillChange.send()
        }.store(in: &subscriptions)
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.checkAutoHide() } }
        NotificationCenter.default.addObserver(self, selector: #selector(layoutDock), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        if !testing && model.defaults.object(forKey: "replacementEnabled") as? Bool != false { setReplacement(true) }
        layoutDock(); checkAutoHide()
        if !CommandLine.arguments.contains("--native-test") && !model.defaults.bool(forKey: "hasLaunched02") { showSettings(); model.defaults.set(true, forKey: "hasLaunched02") }
        if let i = CommandLine.arguments.firstIndex(of: "--native-test"), CommandLine.arguments.indices.contains(i + 1) {
            DispatchQueue.main.async { runNativeTests(self, output: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
        }
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
    @objc func spaceChanged() { settlingUntil = Date().addingTimeInterval(0.5); panel.orderOut(nil); visibility = DockVisibility() }
    @objc func sessionResigned() { sessionActive = false; checkAutoHide() }
    @objc func sessionBecameActive() { sessionActive = true; spaceChanged(); layoutDock() }
    @objc func screenSlept() { screenAwake = false; checkAutoHide() }
    @objc func screenWoke() { screenAwake = true; spaceChanged(); layoutDock() }
    func checkAutoHide() {
        guard let panel, let model, !NSScreen.screens.isEmpty else { return }
        let screen = NSScreen.screens[min(max(0, model.toolkit.screenIndex), NSScreen.screens.count - 1)]
        let mouse = NSEvent.mouseLocation
        let globalTop = NSScreen.screens.first?.frame.maxY ?? 0
        // CGWindow coordinates use a top-left origin, including on secondary displays.
        func cgRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: globalTop - r.maxY, width: r.width, height: r.height) }
        let bounds = cgRect(screen.frame), dock = cgRect(panel.frame)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var fullscreen = false, overlap = false
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = NSRunningApplication(processIdentifier: pid), owner.activationPolicy == .regular, !owner.isHidden,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let data = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: data) else { continue }
            fullscreen = fullscreen || DockVisibility.coversScreen(rect, bounds)
            overlap = overlap || rect.intersects(dock)
        }
        let show = visibility.visible(now: Date(), enabled: model.visible,
            suppressed: fullscreen || !sessionActive || !screenAwake || Date() < settlingUntil,
            autoHide: model.toolkit.autoHide,
            overlapping: model.toolkit.hideOnOverlap && overlap,
            pointerInside: panel.isVisible && panel.frame.contains(mouse),
            pointerAtEdge: DockVisibility.atEdge(mouse, screen: screen.frame, dock: panel.frame, top: model.toolkit.edge == "Top"),
            interacting: !(panel.childWindows ?? []).isEmpty)
        panel.ignoresMouseEvents = !show
        if show { if !panel.isVisible { panel.orderFrontRegardless() } }
        else if panel.isVisible { panel.orderOut(nil) }
    }
    @objc func showSettings() { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleVisibility() { model.visible.toggle(); updateVisibility() }
    func updateVisibility() { checkAutoHide() }
    @objc func refresh() { model.refreshUsage() }
    @objc func restore() { setReplacement(false) }
    @objc func quit() { NSApp.terminate(nil) }
    func setReplacement(_ enabled: Bool) {
        do {
            if !testing { if enabled { try SystemDock.hide() } else { try SystemDock.restore() } }
            model.replacingDock = enabled; model.systemError = nil
            model.defaults.set(enabled, forKey: "replacementEnabled")
            if enabled { model.toolkit.edge = "Bottom" }
            layoutDock(); checkAutoHide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.layoutDock() }
        } catch { model.systemError = "Could not change Apple's Dock setting. Your saved original setting is retained for recovery." }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        do { if !testing { try SystemDock.restore() }; return .terminateNow }
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
        if CommandLine.arguments.contains("--restore-dock") {
            do { try SystemDock.restore(); print("Apple Dock preferences restored.") } catch { print("Could not restore Apple Dock: \(error)"); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--live-test") {
            Task { @MainActor in
                var failed = false
                do {
                    let snapshot = try await GitHubClient.fetch("dylanlasensky/WaveDock", useCLI: false)
                    precondition(snapshot.repository.full_name.lowercased() == "dylanlasensky/wavedock")
                    print("PASS: live GitHub public repository, issues and Actions fetch (partial warning: \(snapshot.activityWarning ?? "none"))")
                } catch { print("FAIL: live GitHub: \(error.localizedDescription)"); failed = true }
                do {
                    let usage = try await Task.detached { try UsageClient.fetch(custom: "") }.value
                    precondition(!usage.buckets.isEmpty)
                    print("PASS: live Codex allowance read")
                } catch { print("UNVERIFIED: live Codex: \(error.localizedDescription)") }
                fflush(stdout); exit(failed ? 1 : 0)
            }
            NSApplication.shared.run(); return
        }
        if CommandLine.arguments.contains("--self-test") { runSelfTests(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
