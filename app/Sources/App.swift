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
    var workspace: DockWorkspace!
    var workspaceWindow: NSWindow?
    var notch: NotchController?
    var snapper: WindowSnapper?
    var subscriptions = Set<AnyCancellable>()
    var visibilityTimer: Timer?
    var visibility = DockVisibility()
    var sessionActive = true
    var screenAwake = true
    var settlingUntil = Date.distantPast
    let testing = CommandLine.arguments.contains("--ui-test") || CommandLine.arguments.contains("--native-test")

    func applicationDidBecomeActive(_ notification: Notification) {
        if PurchaseConfiguration.enabled { Task { await PurchaseManager.shared.refreshEntitlements() } }
    }
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
        appMenu.addItem(withTitle: "Quit DockGrove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(), editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; editMenu.addItem(redo)
        editMenu.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        if PurchaseConfiguration.enabled { Task { await PurchaseManager.shared.load() } }
        model = DockModel(defaults: testing ? UserDefaults(suiteName: "DockGroveUITests")! : .standard)
        do { if !testing { try SystemDock.restore() } } catch { model.systemError = "Could not restore the original Dock setting. Use Restore Apple Dock to retry." }
        workspace = DockWorkspace(defaults: model.defaults, testing: testing)
        workspace.configure = { [weak self] dock in self?.configureExtra(dock) }
        model.manageDocksAction = { [weak self] in self?.showDocks() }
        model.toolkit.windows.usableFrameProvider = { [weak self] screen in self?.usableFrame(screen) ?? WindowManager.usableFrame(screen:screen,dockHeight:0) }
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
        settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        settings.title = "DockGrove"; settings.isReleasedWhenClosed = false
        settings.contentView = NSHostingView(rootView: SettingsView(model: model))
        settings.center()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = BrandIcon.menuImage
        let menu = NSMenu()
        for (title, action, key) in [("Settings…", #selector(showSettings), ","), ("Show / hide DockGrove", #selector(toggleVisibility), "d"), ("Refresh usage", #selector(refresh), "r"), ("Restore Apple Dock", #selector(restore), ""), ("Quit DockGrove", #selector(quit), "q")] {
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
        if !testing && model.defaults.bool(forKey: "replacementEnabled") { setReplacement(true) }
        LicenseManager.shared.objectWillChange.debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { [weak self] _ in
            guard let self, !self.model.canUseFeatures else { return }
            if self.model.replacingDock { self.setReplacement(false) }
            self.snapper?.cancel()
            self.model.appPickerWindow?.close(); self.workspaceWindow?.close()
            for dock in self.workspace.docks { dock.model.appPickerWindow?.close() }
        }.store(in: &subscriptions)
        self.workspace.restore()
        snapper = WindowSnapper(model: model)
        if !CommandLine.arguments.contains("--native-test") { snapper?.start() }
        notch = NotchController(model: model)
        model.openNotchAction = { [weak self] in self?.checkAutoHide(); self?.notch?.setExpanded(true) }
        layoutDock(); checkAutoHide()
        if !CommandLine.arguments.contains("--native-test") && !model.defaults.bool(forKey: "hasLaunched02") { showSettings(); model.defaults.set(true, forKey: "hasLaunched02") }
        if let i = CommandLine.arguments.firstIndex(of: "--native-test"), CommandLine.arguments.indices.contains(i + 1) {
            DispatchQueue.main.async { runNativeTests(self, output: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
        }
    }
    func configureExtra(_ dock: ExtraDock) {
        dock.model.manageDocksAction = { [weak self] in self?.showDocks() }
        dock.model.visibilityAction = { [weak self] in self?.checkAutoHide() }
        dock.model.toolkit.windows.usableFrameProvider = { [weak self] screen in self?.usableFrame(screen) ?? WindowManager.usableFrame(screen:screen,dockHeight:0) }
        dock.model.objectWillChange.debounce(for:.milliseconds(60),scheduler:RunLoop.main).sink { [weak self, weak dock] _ in guard let dock else { return }; self?.layout(dock.panel, model:dock.model); self?.checkAutoHide() }.store(in:&dock.subscriptions)
        for publisher in [dock.model.toolkit.objectWillChange,dock.model.toolkit.utilities.objectWillChange,dock.model.toolkit.github.objectWillChange] {
            publisher.receive(on:RunLoop.main).sink { [weak dock] _ in dock?.model.objectWillChange.send() }.store(in:&dock.subscriptions)
        }
        layout(dock.panel,model:dock.model)
    }
    func showDocks() {
        guard model.canUseFeatures else { showSettings(); return }
        if workspaceWindow == nil {
            workspaceWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:350),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            workspaceWindow?.isReleasedWhenClosed=false; workspaceWindow?.title="Your Docks"
            workspaceWindow?.contentView=NSHostingView(rootView:DockWorkspaceView(workspace:workspace,primary:model)); workspaceWindow?.center()
        }
        workspaceWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func layoutDock() {
        guard model != nil, panel != nil else { return }
        layout(panel,model:model)
        for dock in workspace?.docks ?? [] { layout(dock.panel,model:dock.model) }
        notch?.update(suppressed: !sessionActive || !screenAwake || Date() < settlingUntil)
    }
    func layout(_ panel: DockPanel, model: DockModel) {
        guard let screen=model.selectedScreen, let view=panel.contentView else { return }
        view.invalidateIntrinsicContentSize()
        panel.setFrame(DockGeometry.frame(size:view.fittingSize,screen:screen.frame,visible:screen.visibleFrame,edge:model.replacingDock ? "Bottom" : model.toolkit.edge,alignment:model.alignment,elevation:model.elevation,replacing:model.replacingDock),display:true)
    }
    func usableFrame(_ screen:NSScreen) -> CGRect {
        var rects:[CGRect]=[]
        if let panel, let model, model.visible && !model.toolkit.autoHide && model.toolkit.edge != "Floating" { rects.append(panel.frame) }
        for dock in workspace?.docks ?? [] where dock.model.visible && !dock.model.toolkit.autoHide && dock.model.toolkit.edge != "Floating" { rects.append(dock.panel.frame) }
        let usable=DockGeometry.reserve(screen.visibleFrame,docks:rects)
        return CGRect(x:usable.minX,y:(NSScreen.screens.first?.frame.maxY ?? 0)-usable.maxY,width:usable.width,height:usable.height)
    }
    @objc func spaceChanged() { notch?.hide(); settlingUntil = Date().addingTimeInterval(0.5); panel.orderOut(nil); visibility = DockVisibility(); snapper?.cancel(); for dock in workspace?.docks ?? [] { dock.panel.orderOut(nil); dock.visibility=DockVisibility() } }
    @objc func sessionResigned() { sessionActive = false; checkAutoHide() }
    @objc func sessionBecameActive() { sessionActive = true; spaceChanged(); layoutDock() }
    @objc func screenSlept() { screenAwake = false; checkAutoHide() }
    @objc func screenWoke() { screenAwake = true; spaceChanged(); layoutDock() }
    func checkAutoHide() {
        guard let panel, let model else { return }
        check(panel,model:model,visibility:&visibility)
        for dock in workspace?.docks ?? [] { check(dock.panel,model:dock.model,visibility:&dock.visibility) }
        notch?.update(suppressed: !sessionActive || !screenAwake || Date() < settlingUntil)
        if !sessionActive || !screenAwake { snapper?.cancel() }
    }
    func check(_ panel:DockPanel,model:DockModel,visibility:inout DockVisibility) {
        guard let screen=model.selectedScreen else { panel.orderOut(nil); return }
        let mouse = NSEvent.mouseLocation
        let globalTop = NSScreen.screens.first?.frame.maxY ?? 0
        // CGWindow coordinates use a top-left origin, including on secondary displays.
        func cgRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: globalTop - r.maxY, width: r.width, height: r.height) }
        let bounds = cgRect(screen.frame), dock = cgRect(panel.frame)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var fullscreen = false, overlap = false
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = NSRunningApplication(processIdentifier: pid), owner.activationPolicy == .regular, !owner.isHidden,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let data = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: data) else { continue }
            fullscreen = fullscreen || (pid == activePID && DockVisibility.coversScreen(rect, bounds))
            overlap = overlap || rect.intersects(dock)
        }
        let show = visibility.visible(now: Date(), enabled: model.visible,
            suppressed: fullscreen || !sessionActive || !screenAwake || Date() < settlingUntil,
            autoHide: model.toolkit.autoHide && model.toolkit.edge != "Floating",
            overlapping: model.toolkit.hideOnOverlap && model.toolkit.edge != "Floating" && overlap,
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
        guard !enabled || model.canUseFeatures else { model.systemError = "Activate DockGrove before using Dock replacement."; return }
        do {
            if !testing { if enabled { try SystemDock.hide() } else { try SystemDock.restore() } }
            model.replacingDock = enabled; model.systemError = nil
            model.defaults.set(enabled, forKey: "replacementEnabled")
            if enabled { model.toolkit.edge = "Bottom" }
            layoutDock(); checkAutoHide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.layoutDock() }
        } catch { model.systemError = "Could not change Apple's Dock setting. Your saved original setting is retained for recovery." }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.codexSignIn.cancel()
        model?.toolkit.claudeCodeUsage.signIn.cancel()
        for dock in workspace?.docks ?? [] {
            dock.model.codexSignIn.cancel()
            dock.model.toolkit.claudeCodeUsage.signIn.cancel()
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        do { if !testing { try SystemDock.restore() }; return .terminateNow }
        catch {
            let alert = NSAlert(); alert.messageText = "Apple Dock could not be restored"
            alert.informativeText = "You can retry, or quit and turn off auto-hide in System Settings > Desktop & Dock. The original setting stays saved for the next DockGrove launch."
            alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "Quit anyway")
            if alert.runModal() == .alertFirstButtonReturn { do { try SystemDock.restore(); return .terminateNow } catch { return .terminateCancel } }; return .terminateNow
        }
    }
}

@main struct DockGroveMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--notch-test") {
            let output = CommandLine.arguments.indices.contains(index + 1) ? URL(fileURLWithPath: CommandLine.arguments[index + 1]) : nil
            do { try runNotchTests(output: output) } catch { print("FAIL: notch: \(error)"); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--assets-test") {
            let output = CommandLine.arguments.indices.contains(index + 1) ? URL(fileURLWithPath: CommandLine.arguments[index + 1]) : nil
            do { try runAssetCatalogTests(output: output) } catch { print("FAIL: asset catalog: \(error)"); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--studio-test") {
            do { try runDockStudioTests() } catch { print("FAIL: studio: \(error)"); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--studio-render"), CommandLine.arguments.indices.contains(index + 1) {
            do { try renderDockStudio(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { print("FAIL: studio render: \(error)"); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--weather-test") {
            guard CommandLine.arguments.indices.contains(index + 1) else {
                print("Usage: DockGrove --weather-test CITY"); exit(2)
            }
            let city = CommandLine.arguments[index + 1]
            Task { @MainActor in
                do {
                    let weather = try await AppleWeatherClient.fetch(city: city)
                    print("PASS: Apple Weather · \(weather.city) · \(WeatherSnapshot.fahrenheit(weather.temperature)) · \(weather.condition)")
                    print("Attribution: \(weather.attributionURL.absoluteString)")
                    fflush(stdout); exit(0)
                } catch {
                    print("FAIL: Apple Weather: \(error)"); fflush(stdout); exit(1)
                }
            }
            NSApplication.shared.run(); return
        }
        if CommandLine.arguments.contains("--claude-statusline") { exit(LocalAIStore.capture(.claude)) }
        if CommandLine.arguments.contains("--gemini-report") { exit(LocalAIStore.capture(.gemini)) }
        if CommandLine.arguments.contains("--restore-dock") {
            do { try SystemDock.restore(); print("Apple Dock preferences restored.") } catch { print("Could not restore Apple Dock: \(error)"); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--live-test") {
            Task { @MainActor in
                var failed = false
                do {
                    let snapshot = try await GitHubClient.fetch("dylanlasensky/DockGrove", useCLI: false)
                    precondition(snapshot.repository.full_name.lowercased() == "dylanlasensky/dockgrove")
                    print("PASS: live GitHub public repository, issues and Actions fetch (partial warning: \(snapshot.activityWarning ?? "none"))")
                } catch { print("FAIL: live GitHub: \(error.localizedDescription)"); failed = true }
                do {
                    let usage = try await Task.detached { try UsageClient.fetch(custom: "") }.value
                    precondition(!usage.buckets.isEmpty)
                    print("PASS: live Codex allowance read")
                } catch { print("UNVERIFIED: live Codex: \(error.localizedDescription)") }
                let currency = CurrencyWidget(); currency.refresh()
                while currency.loading { try? await Task.sleep(nanoseconds: 100_000_000) }
                if currency.report != nil { print("PASS: live currency reference rate through widget client") }
                else { print("FAIL: live currency: " + currency.status); failed = true }
                // Match the widget cadence: cached host statistics may not advance in 250 ms.
                let monitor = SystemMonitor(); monitor.sample(); try? await Task.sleep(nanoseconds: 2_000_000_000); monitor.sample()
                if monitor.available && monitor.memory >= 0 && monitor.memory <= 100 { print("PASS: live CPU, memory and network sampling") }
                else { print("FAIL: live system sampling"); failed = true }
                let audio = AudioControl(); audio.refresh()
                print(audio.outputs.isEmpty ? "UNVERIFIED: no audio outputs available" : "PASS: live audio output discovery")
                fflush(stdout); exit(failed ? 1 : 0)
            }
            NSApplication.shared.run(); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--ai-signin-test"), CommandLine.arguments.indices.contains(index + 1) {
            let fixture = CommandLine.arguments[index + 1]
            Task { @MainActor in
                do { try await runAISignInTests(fixture: fixture); fflush(stdout); exit(0) }
                catch { print("FAIL: AI sign-in tests: \(error)"); fflush(stdout); exit(1) }
            }
            NSApplication.shared.run(); return
        }
        if CommandLine.arguments.contains("--self-test") {
            runSelfTests()
            Task { @MainActor in
                do { try await runIntegrationTests(); fflush(stdout); exit(0) }
                catch { print("FAIL: integration tests: \(error)"); fflush(stdout); exit(1) }
            }
            NSApplication.shared.run(); return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
