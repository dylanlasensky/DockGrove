import AppKit
import Carbon.HIToolbox

/// Pure visibility policy shared by the live window and regression tests.
struct DockVisibility {
    var revealStarted: Date?
    var lastInside = Date.distantPast
    mutating func visible(now: Date, enabled: Bool, suppressed: Bool, autoHide: Bool,
                          overlapping: Bool, pointerInside: Bool, pointerAtEdge: Bool,
                          interacting: Bool) -> Bool {
        guard enabled, !suppressed else { revealStarted = nil; lastInside = .distantPast; return false }
        if !autoHide && !overlapping { return true }
        if interacting { lastInside = now; return true }
        // A hidden dock can only be revealed by the physical screen edge, not its old rectangle.
        if pointerAtEdge {
            if revealStarted == nil { revealStarted = now }
            if now.timeIntervalSince(revealStarted!) >= 0.25 { lastInside = now; return true }
        } else { revealStarted = nil }
        if pointerInside && now.timeIntervalSince(lastInside) < 0.7 { lastInside = now }
        return now.timeIntervalSince(lastInside) < 0.7
    }
    static func atEdge(_ point: NSPoint, screen: NSRect, dock: NSRect, top: Bool) -> Bool {
        point.x >= dock.minX && point.x <= dock.maxX &&
        (top ? point.y >= screen.maxY - 3 && point.y <= screen.maxY : point.y >= screen.minY && point.y <= screen.minY + 3)
    }
    /// The physical screen edge that reveals an auto-hidden dock: the top for Top docks, the
    /// bottom for Bottom docks (always, while replacing Apple's Dock), and the nearer one for
    /// Floating docks.
    static func revealsAtTop(edge: String, elevation: Double, replacing: Bool) -> Bool {
        if replacing { return false }
        if edge == "Floating" { return elevation > 0.5 }
        return edge == "Top"
    }
    /// Where the pointer keeps a revealed dock open: the dock plus the strip between it and its
    /// reveal edge, so travelling from the edge to a Floating (or inset) dock doesn't hide it.
    static func hoverRegion(dock: NSRect, screen: NSRect, top: Bool) -> NSRect {
        top ? NSRect(x: dock.minX, y: dock.minY, width: dock.width, height: screen.maxY - dock.minY + 1)
            : NSRect(x: dock.minX, y: screen.minY, width: dock.width, height: dock.maxY - screen.minY)
    }
    static func coversScreen(_ window: CGRect, _ screen: CGRect) -> Bool {
        window.minX <= screen.minX + 2 && window.maxX >= screen.maxX - 2 &&
        window.minY <= screen.minY + 2 && window.maxY >= screen.maxY - 2
    }
}

extension DockModel {
    /// "Turn Hiding On/Off" (⌥⌘D, the bar menu, the status menu and Settings), like the Mac Dock.
    /// A dock that was switched off entirely comes back with hiding off, so the shortcut always
    /// recovers it.
    func toggleHiding() {
        if visible { toolkit.autoHide.toggle() } else { visible = true; toolkit.autoHide = false }
        visibilityAction?()
    }
    /// "Show DockGrove" (Settings, the status menu and Your Docks). While DockGrove replaces
    /// Apple's Dock, switching it off would leave no Dock at all, so it auto-hides instead.
    func setShown(_ shown: Bool) {
        if !shown && replacingDock { toolkit.autoHide = true; visible = true } else { visible = shown }
        visibilityAction?()
    }
    var hidingMenuTitle: String { toolkit.autoHide ? "Turn Hiding Off" : "Turn Hiding On" }
    var visibilityMenuTitle: String { visible ? "Hide DockGrove" : "Show DockGrove" }
}

/// A system-wide shortcut in Carbon terms (virtual key code plus Carbon modifier flags).
struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// ⌥⌘D, the Mac Dock's "Turn Dock Hiding On/Off".
    static let toggleHiding = HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | optionKey))
}

/// Registers system-wide shortcuts. The app uses Carbon hot keys, which need no Accessibility
/// permission; tests inject a fake so no real shortcut is ever registered.
@MainActor protocol HotKeyRegistrar: AnyObject {
    @discardableResult func register(_ key: HotKey, handler: @escaping @MainActor () -> Void) -> Bool
    func unregisterAll()
}

/// Registers nothing: UI-test, native-test and XCTest launches.
@MainActor final class InertHotKeyRegistrar: HotKeyRegistrar {
    func register(_ key: HotKey, handler: @escaping @MainActor () -> Void) -> Bool { false }
    func unregisterAll() {}
}

/// Live Carbon `RegisterEventHotKey` registrar (no Accessibility permission needed).
@MainActor final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    func register(_ key: HotKey, handler: @escaping @MainActor () -> Void) -> Bool {
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr else { return status }
                let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { registrar.fire(id.id) } ? noErr : OSStatus(eventNotHandledErr)
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { return false }
        }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4447_5256), id: nextID) // 'DGRV'
        guard RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr, let reference else { return false }
        references.append(reference); handlers[nextID] = handler; nextID += 1
        return true
    }
    private func fire(_ id: UInt32) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler(); return true
    }
    func unregisterAll() {
        for reference in references { UnregisterEventHotKey(reference) }
        references = []; handlers = [:]
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
}

struct DockPreference: Codable, Equatable {
    var type: String
    var value: String
}

/// Writes a durable journal before changing macOS preferences. Injectable I/O makes
/// partial failures and crash recovery testable without changing the user's Dock.
/// DockGrove changes only `autohide` and `autohide-delay`; tile size, magnification,
/// orientation and the Dock's apps are never written.
struct DockRestoration {
    let store: UserDefaults
    var read: (String) throws -> DockPreference?
    var write: (String, DockPreference?) throws -> Void
    var restart: () throws -> Void
    static let key = "dockReplacementJournalV3"
    static let keys = ["autohide", "autohide-delay"]
    /// The reveal delay DockGrove writes. Nobody chooses a one-day delay, so seeing it means
    /// DockGrove's change is still live even when the journal was lost.
    static let hiddenDelay = "86400"
    private static var appleDefaults: [String: DockPreference] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, DockPreference(type: "missing", value: "")) })
    }
    /// The user's original values, when a complete, readable journal exists.
    var savedOriginal: [String: DockPreference]? {
        guard let data = store.data(forKey: Self.key),
              let original = try? JSONDecoder().decode([String: DockPreference].self, from: data),
              Self.keys.allSatisfy({ original[$0] != nil }) else { return nil }
        return original
    }
    /// True while Apple's Dock still carries DockGrove's hidden-Dock delay.
    var dockLooksHidden: Bool {
        guard let delay = try? read("autohide-delay"), delay.type == "float" else { return false }
        return Double(delay.value) == Double(Self.hiddenDelay)
    }
    /// Whether Restore Apple Dock has anything to put back.
    var needsRestore: Bool { store.data(forKey: Self.key) != nil || dockLooksHidden }
    func hide() throws {
        // Capture originals once: re-enabling, relaunching or hiding again must never
        // overwrite the journal with DockGrove's own values.
        if savedOriginal == nil {
            var original = Self.appleDefaults
            // A Dock already hidden by DockGrove (journal lost or corrupt) holds DockGrove's
            // values, so the best known original is Apple's default: both keys absent.
            if !dockLooksHidden {
                for key in Self.keys { original[key] = try read(key) ?? DockPreference(type: "missing", value: "") }
            }
            store.set(try JSONEncoder().encode(original), forKey: Self.key)
            guard store.synchronize() else { throw UsageError.service }
        }
        do {
            try write("autohide", DockPreference(type: "boolean", value: "true"))
            // Keep the native Dock from competing for the same bottom-edge gesture.
            try write("autohide-delay", DockPreference(type: "float", value: Self.hiddenDelay))
            try restart()
        } catch {
            try? restore()
            throw error
        }
    }
    /// Puts back exactly the journaled originals and relaunches the Dock. Without a usable
    /// journal it still undoes a DockGrove-hidden Dock (to Apple's defaults); otherwise it
    /// changes nothing, so calling it again is harmless.
    func restore() throws {
        let original: [String: DockPreference]
        if let saved = savedOriginal { original = saved }
        else if dockLooksHidden { original = Self.appleDefaults }
        else {
            // Nothing of DockGrove's is live; a corrupt journal has nothing left to protect.
            if store.data(forKey: Self.key) != nil { store.removeObject(forKey: Self.key); store.synchronize() }
            return
        }
        for key in Self.keys {
            let value = original[key]!
            try write(key, value.type == "missing" ? nil : value)
        }
        try restart()
        store.removeObject(forKey: Self.key)
        store.synchronize()
    }
}

enum SystemDock {
    /// Process execution and preference storage; tests replace both so com.apple.dock is never touched.
    static var runner: (String, [String]) throws -> (Int32, Data) = SystemDock.run
    static var store: UserDefaults = .standard
    static var manager: DockRestoration {
        DockRestoration(store: store, read: { key in
            // Read the complete domain so an I/O failure cannot be mistaken for an absent key.
            let (code, data) = try runner("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
            guard code == 0, let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw UsageError.service }
            guard let value = domain[key] as? NSNumber else {
                if domain[key] != nil { throw UsageError.service }; return nil
            }
            return DockPreference(type: CFGetTypeID(value) == CFBooleanGetTypeID() ? "boolean" : "float", value: value.stringValue)
        }, write: { key, value in
            if let value {
                guard ["boolean", "float"].contains(value.type) else { throw UsageError.service }
                guard try runner("/usr/bin/defaults", ["write", "com.apple.dock", key, value.type == "boolean" ? "-bool" : "-float", try cliValue(value)]).0 == 0 else { throw UsageError.service }
            } else {
                let (code, _) = try runner("/usr/bin/defaults", ["delete", "com.apple.dock", key])
                if code != 0 {
                    let (_, data) = try runner("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
                    guard let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], domain[key] == nil else { throw UsageError.service }
                }
            }
        }, restart: { _ = try runner("/usr/bin/killall", ["Dock"]) })
    }
    static func cliValue(_ preference: DockPreference) throws -> String {
        if preference.type == "boolean" {
            switch preference.value.lowercased() {
            case "1", "true", "yes": return "true"
            case "0", "false", "no": return "false"
            default: throw UsageError.service
            }
        }
        guard preference.type == "float", let value = Double(preference.value), value.isFinite else { throw UsageError.service }
        return preference.value
    }
    static func hide() throws { try manager.hide() }
    /// Saved originals (current or v0.2 journal) exist, or the Dock is still hidden by DockGrove.
    static func needsRestore() -> Bool { store.string(forKey: "originalDockAutohide") != nil || manager.needsRestore }
    static func restore() throws {
        try manager.restore()
        // Upgrade recovery for v0.2, which only recorded autohide.
        if let old = store.string(forKey: "originalDockAutohide") {
            try manager.write("autohide", old == "missing" ? nil : DockPreference(type: "boolean", value: old))
            try manager.restart()
            store.removeObject(forKey: "originalDockAutohide"); store.synchronize()
        }
    }
    @discardableResult static func run(_ path: String, _ args: [String]) throws -> (Int32, Data) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
