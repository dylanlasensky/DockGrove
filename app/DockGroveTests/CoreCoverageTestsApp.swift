import XCTest
import AppKit
@testable import DockGrove

/// Another DockGrove instance that records activation instead of activating anything.
private final class CoreOtherInstance: NSRunningApplication {
    var activated = false
    override var processIdentifier: pid_t { 999_999 }
    override var activationPolicy: NSApplication.ActivationPolicy { .regular }
    override var isHidden: Bool { false }
    override func activate(options: NSApplication.ActivationOptions = []) -> Bool { activated = true; return true }
}

@MainActor private func coreSleep(_ seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

/// Waits for a condition (debounced Combine sinks and Tasks run on the main run loop) instead of a fixed sleep.
@MainActor @discardableResult private func coreAppWait(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= deadline { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

@MainActor final class CoreCoverageTestsApp: XCTestCase {
    private var suites: [String] = []
    private var delegates: [AppDelegate] = []
    private var dockFailures = false
    private var dockCalls: [[String]] = []
    private var terminated = 0
    private var savedRunner = SystemDock.runner
    private var savedStore = SystemDock.store
    private var savedPurchaseStore: StoreKitClient?

    override func setUp() async throws {
        savedRunner = SystemDock.runner; savedStore = SystemDock.store
        SystemDock.store = suite()
        // Never run `defaults` or `killall Dock`: every SystemDock call lands here.
        SystemDock.runner = { [unowned self] path, args in
            self.dockCalls.append([path] + args)
            if self.dockFailures { return (1, Data()) }
            if args.first == "export" { return (0, try PropertyListSerialization.data(fromPropertyList: ["autohide": false], format: .xml, options: 0)) }
            return (0, Data())
        }
        let purchases = PurchaseManager.shared
        savedPurchaseStore = purchases.store
        purchases.store = StoreKitClient(updates: { AsyncStream { $0.finish() } }, latest: { _ in nil }, products: { _ in [] }, sync: {})
    }

    override func tearDown() async throws {
        for delegate in delegates {
            delegate.visibilityTimer?.invalidate()
            delegate.snapper?.cancel()
            delegate.notch?.hide()
            delegate.settings?.close(); delegate.workspaceWindow?.close(); delegate.panel?.close()
            for dock in delegate.workspace?.docks ?? [] {
                dock.panel.close(); dock.settings.close()
                suites.append(delegate.workspace.prefix + dock.id)
            }
            if let status = delegate.status { NSStatusBar.system.removeStatusItem(status) }
            NotificationCenter.default.removeObserver(delegate)
            NSWorkspace.shared.notificationCenter.removeObserver(delegate)
        }
        delegates = []
        SystemDock.runner = savedRunner; SystemDock.store = savedStore
        if let savedPurchaseStore { PurchaseManager.shared.store = savedPurchaseStore }
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites = []
    }

    private func suite() -> UserDefaults {
        let name = "CoreCoverageTestsApp." + UUID().uuidString
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func delegate(_ arguments: [String] = ["DockGrove"], preferences: UserDefaults? = nil) -> AppDelegate {
        let delegate = AppDelegate(arguments: arguments, preferences: preferences ?? suite())
        delegate.runningApplications = { _ in [] }
        delegate.terminate = { [unowned self] _ in self.terminated += 1 }
        delegates.append(delegate)
        return delegate
    }

    private func launch(_ delegate: AppDelegate) {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    }

    func testUnlaunchedDelegateIsInert() {
        let delegate = AppDelegate()
        XCTAssertEqual(delegate.arguments, CommandLine.arguments, "default arguments")
        XCTAssertFalse(delegate.testing, "XCTest host is not a UI-test launch")
        XCTAssertTrue(DockPanel().canBecomeKey, "panel can become key")
        XCTAssertFalse(DockPanel().canBecomeMain, "panel never becomes main")
        delegate.layoutDock()
        delegate.checkAutoHide()
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow, "unlaunched delegate terminates")
        XCTAssertTrue(AppDelegate(arguments: ["x", "--ui-test"]).testing, "--ui-test")
        XCTAssertTrue(AppDelegate(arguments: ["x", "--native-test"]).testing, "--native-test")
        _ = delegate.windowList()
        XCTAssertEqual(primaryScreenTop([]), 0, "no screens")
        XCTAssertTrue(delegate.preferences === UserDefaults.standard, "production uses standard defaults")
        _ = AppDelegate(arguments: ["x", "--ui-test"]).preferences
    }

    func testSecondInstanceHandsOver() {
        let delegate = delegate()
        let other = CoreOtherInstance()
        delegate.runningApplications = { _ in [NSRunningApplication.current, other] }
        launch(delegate)
        XCTAssertTrue(other.activated, "the running instance is activated")
        XCTAssertEqual(terminated, 1, "the second instance terminates")
        XCTAssertNil(delegate.model, "the second instance stops before creating a model")
    }

    func testNativeTestLaunchMode() async {
        let delegate = delegate(["DockGrove", "--native-test", "/tmp/core-native.json"])
        var ran: URL?
        delegate.nativeTestRunner = { _, url in ran = url }
        launch(delegate)
        await coreAppWait { ran != nil }
        XCTAssertEqual(ran?.path, "/tmp/core-native.json", "native test runner receives the output path")
        XCTAssertTrue(dockCalls.isEmpty, "test modes never touch the Dock")
        XCTAssertFalse(delegate.settings.isVisible, "native tests don't open Settings")
        XCTAssertFalse(delegate.model.defaults.bool(forKey: "hasLaunched02"), "native tests don't record first launch")
    }

    func testLaunchLifecycleAndActions() async throws {
        let preferences = suite()
        preferences.set(true, forKey: "replacementEnabled")
        SystemDock.store.set(Data("corrupt".utf8), forKey: DockRestoration.key)
        let delegate = delegate(preferences: preferences)
        delegate.purchasesEnabled = true
        launch(delegate)
        let model = try XCTUnwrap(delegate.model, "launch creates the model")
        XCTAssertEqual(model.systemError, nil, "replacement is re-applied after the failed restore")
        XCTAssertTrue(model.replacingDock, "saved replacement preference is re-applied at launch")
        SystemDock.store.removeObject(forKey: DockRestoration.key)
        XCTAssertTrue(preferences.bool(forKey: "hasLaunched02"), "first launch records hasLaunched02")
        XCTAssertEqual(delegate.status.menu?.items.count, 5, "status menu items")
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false), "reopen is handled")
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        let loaded = await coreAppWait { PurchaseManager.shared.hasLoadedEntitlements }
        XCTAssertTrue(loaded, "becoming active refreshes entitlements")

        // Model callbacks wired at launch.
        model.settingsAction?(); model.closeSettingsAction?()
        model.manageDocksAction?(); model.manageDocksAction?()
        XCTAssertNotNil(delegate.workspaceWindow, "manage docks opens the workspace window")
        model.visibilityAction?()
        model.openNotchAction?()
        let screen = try XCTUnwrap(NSScreen.screens.first, "a display is attached")
        _ = model.toolkit.windows.usableFrameProvider?(screen)
        model.changeDockAction?(false)
        XCTAssertFalse(model.replacingDock, "changeDockAction(false) restores Apple's Dock")

        // Extra docks are configured by the workspace.
        delegate.workspace.add()
        let dock = try XCTUnwrap(delegate.workspace.docks.first, "workspace.add creates an extra dock")
        dock.model.manageDocksAction?()
        dock.model.visibilityAction?()
        _ = dock.model.toolkit.windows.usableFrameProvider?(screen)
        dock.model.objectWillChange.send()
        dock.model.toolkit.objectWillChange.send()
        model.objectWillChange.send()
        model.toolkit.objectWillChange.send(); model.toolkit.utilities.objectWillChange.send(); model.toolkit.github.objectWillChange.send()
        delegate.visibilityTimer?.fire()
        await coreSleep(0.25)
        XCTAssertGreaterThan(delegate.usableFrame(screen).width, 0, "usable frame has width")

        // Visibility: overlapping windows, hidden dock, sessions and spaces. Window owners,
        // the window list and the frontmost app are all fakes; no real window state is read.
        let pid: pid_t = 999_999
        let owner = CoreOtherInstance()
        delegate.windowOwner = { $0 == pid ? owner : nil }
        let rect = screen.frame
        delegate.windowList = { [
            [kCGWindowOwnerPID as String: getpid(), kCGWindowLayer as String: 0],
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1.0,
             kCGWindowBounds as String: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height).dictionaryRepresentation],
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: rect.minX, y: 0, width: 10, height: 10).dictionaryRepresentation],
        ] }
        delegate.frontmostPID = { pid }
        model.toolkit.autoHide = true
        delegate.checkAutoHide()
        model.toolkit.autoHide = false
        model.toolkit.hideOnOverlap = true
        delegate.checkAutoHide()
        model.toolkit.hideOnOverlap = false
        delegate.checkAutoHide()
        XCTAssertFalse(delegate.panel.isVisible, "a full-screen frontmost window suppresses the dock")
        delegate.frontmostPID = { nil }
        delegate.checkAutoHide()
        XCTAssertTrue(delegate.panel.isVisible, "dock shows once nothing is full screen")
        delegate.toggleVisibility()
        XCTAssertFalse(delegate.panel.isVisible, "toggling hides the dock")
        delegate.toggleVisibility()
        delegate.windowList = { [] }
        delegate.sessionResigned(); delegate.sessionBecameActive()
        delegate.screenSlept(); delegate.screenWoke()
        delegate.spaceChanged()
        delegate.refresh()

        // Paths taken before the workspace exists.
        let workspace = delegate.workspace
        delegate.workspace = nil
        delegate.layoutDock(); delegate.checkAutoHide(); delegate.spaceChanged()
        _ = delegate.usableFrame(screen)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        delegate.workspace = workspace

        // Replacement: success, failure and the licensing kill switch.
        delegate.setReplacement(true)
        XCTAssertTrue(model.replacingDock, "setReplacement(true) replaces the Dock")
        XCTAssertEqual(model.toolkit.edge, "Bottom", "replacement pins the dock to the bottom")
        await coreSleep(0.9) // lets the delayed re-layout run; nothing asserts on it
        dockFailures = true
        delegate.setReplacement(false)
        XCTAssertEqual(model.systemError, "Could not change Apple's Dock setting. Your saved original setting is retained for recovery.", "restore failure is reported")
        dockFailures = false
        delegate.featuresAllowed = { _ in false }
        delegate.setReplacement(true)
        XCTAssertEqual(model.systemError, "Activate DockGrove before using Dock replacement.", "replacement requires activation")
        delegate.showDocks()
        delegate.setReplacement(false)
        delegate.featuresAllowed = { _ in true }
        delegate.setReplacement(true)
        XCTAssertTrue(model.replacingDock, "replacement re-enabled before the license kill switch")
        delegate.featuresAllowed = { _ in false }
        LicenseManager.shared.objectWillChange.send()
        let released = await coreAppWait { !model.replacingDock }
        XCTAssertTrue(released, "losing the license restores Apple's Dock")
        // Second change while already restored: exercises the not-replacing path of the sink.
        let restores = dockCalls.count
        LicenseManager.shared.objectWillChange.send()
        await coreAppWait(2) { false }
        XCTAssertEqual(dockCalls.count, restores, "no Dock change when already restored")
        delegate.restore()
        delegate.quit()
        XCTAssertEqual(terminated, 1, "quit terminates through the seam")

        // Termination restores Apple's Dock, retrying through an alert when it fails.
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow, "clean restore terminates")
        let journal = try JSONEncoder().encode(["autohide": DockPreference(type: "missing", value: ""), "autohide-delay": DockPreference(type: "missing", value: "")])
        SystemDock.store.set(journal, forKey: DockRestoration.key)
        dockFailures = true
        delegate.runAlert = { _ in .alertSecondButtonReturn }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow, "Quit anyway terminates")
        delegate.runAlert = { _ in .alertFirstButtonReturn }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel, "failed retry cancels")
        delegate.runAlert = { [unowned self] _ in self.dockFailures = false; return .alertFirstButtonReturn }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow, "successful retry terminates")
        let testingDelegate = self.delegate(["DockGrove", "--ui-test"])
        launch(testingDelegate)
        XCTAssertEqual(testingDelegate.applicationShouldTerminate(NSApplication.shared), .terminateNow, "UI-test mode skips Dock restore")
    }

    func testDefaultAlertRunsModally() {
        let alert = NSAlert()
        alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "Quit anyway")
        RunLoop.main.perform(inModes: [.modalPanel, .default, .common]) { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
        XCTAssertEqual(AppDelegate().runAlert(alert), .alertSecondButtonReturn, "default alert runner returns the modal response")
    }

    func testFrameProvidersOutliveTheDelegate() async throws {
        var delegate: AppDelegate? = AppDelegate(arguments: ["DockGrove", "--native-test"], preferences: suite())
        delegate?.nativeTestRunner = { _, _ in }
        delegate.map(launch)
        delegate?.workspace.add()
        let model = try XCTUnwrap(delegate?.model, "launch creates the model")
        let dock = try XCTUnwrap(delegate?.workspace.docks.first, "extra dock created")
        await coreSleep(0.1)
        if let delegate {
            delegate.visibilityTimer?.invalidate(); delegate.snapper?.cancel(); delegate.notch?.hide()
            delegate.settings.close(); delegate.panel.close(); dock.panel.close(); dock.settings.close()
            suites.append(delegate.workspace.prefix + dock.id)
            NSStatusBar.system.removeStatusItem(delegate.status)
        }
        weak var released = delegate
        delegate = nil
        await coreAppWait { released == nil }
        let screen = try XCTUnwrap(NSScreen.screens.first, "a display is attached")
        if released == nil {
            XCTAssertGreaterThan(model.toolkit.windows.usableFrameProvider?(screen).width ?? 0, 0, "main provider falls back without the delegate")
            XCTAssertGreaterThan(dock.model.toolkit.windows.usableFrameProvider?(screen).width ?? 0, 0, "extra dock provider falls back without the delegate")
        } else {
            XCTFail("AppDelegate leaked after launch")
        }
    }
}
