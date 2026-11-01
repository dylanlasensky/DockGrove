import AppKit

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
    static func coversScreen(_ window: CGRect, _ screen: CGRect) -> Bool {
        window.minX <= screen.minX + 2 && window.maxX >= screen.maxX - 2 &&
        window.minY <= screen.minY + 2 && window.maxY >= screen.maxY - 2
    }
}

struct DockPreference: Codable, Equatable {
    var type: String
    var value: String
}

/// Writes a durable journal before changing macOS preferences. Injectable I/O makes
/// partial failures and crash recovery testable without changing the user's Dock.
struct DockRestoration {
    let store: UserDefaults
    var read: (String) throws -> DockPreference?
    var write: (String, DockPreference?) throws -> Void
    var restart: () throws -> Void
    static let key = "dockReplacementJournalV3"
    static let keys = ["autohide", "autohide-delay"]
    func hide() throws {
        if store.data(forKey: Self.key) == nil {
            var original: [String: DockPreference] = [:]
            for key in Self.keys { original[key] = try read(key) ?? DockPreference(type: "missing", value: "") }
            store.set(try JSONEncoder().encode(original), forKey: Self.key)
            guard store.synchronize() else { throw UsageError.service }
        }
        do {
            try write("autohide", DockPreference(type: "boolean", value: "true"))
            // Keep the native Dock from competing for the same bottom-edge gesture.
            try write("autohide-delay", DockPreference(type: "float", value: "86400"))
            try restart()
        } catch {
            try? restore()
            throw error
        }
    }
    func restore() throws {
        guard let data = store.data(forKey: Self.key) else { return }
        let original = try JSONDecoder().decode([String: DockPreference].self, from: data)
        guard Self.keys.allSatisfy({ original[$0] != nil }) else { throw UsageError.service }
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
