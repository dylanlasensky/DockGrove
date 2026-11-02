import AppKit

extension DockModel {
    /// Opens the full-screen Applications launcher; adding or replacing tiles needs an active licence.
    func showAppLauncher(_ mode: AppsLauncher.Mode = .launch, query: String = "") {
        guard mode == .launch || canUseFeatures else { settingsAction?(); return }
        systemError = nil
        AppsLauncher.shared.show(model: self, mode: mode, query: query)
    }
    func showAppPicker(replacing: DockApp? = nil) { showAppLauncher(replacing.map { .replace($0) } ?? .add) }
    func rememberApps() { appHistory.append((apps, entryOrder)); if appHistory.count > 20 { appHistory.removeFirst() } }
    func undoAppChange() {
        guard let previous = appHistory.popLast() else { return }
        apps = previous.0; entryOrder = previous.1; persistApps()
    }
    @discardableResult func chooseApp(_ app: DockApp, replacing old: DockApp?) -> Bool {
        guard canUseFeatures else { systemError = "Activate DockGrove to change apps."; return false }
        guard FileManager.default.fileExists(atPath: app.id), app.url.pathExtension == "app" else { systemError = "This application is no longer installed."; return false }
        guard !apps.contains(app) else { systemError = "That application is already in the Dock."; return false }
        if let old {
            guard let index = apps.firstIndex(of: old) else { systemError = "The original tile changed. Close and try again."; return false }
            rememberApps()
            let order = orderedEntries.map(\.id)
            apps[index] = app
            entryOrder = order.map { $0 == "app:" + old.id ? "app:" + app.id : $0 }
        } else { rememberApps(); apps.append(app) }
        persistApps(); systemError = nil; return true
    }
}
