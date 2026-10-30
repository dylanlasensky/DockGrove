import Foundation

/// Preserve an existing local library rather than orphaning recordings or AI reports on rebrand.
enum BrandStorage {
    static func supportDirectory(in base: URL) -> URL {
        let legacy = base.appendingPathComponent("WaveDock", isDirectory: true)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : base.appendingPathComponent("DockGrove", isDirectory: true)
    }
    static var supportDirectory: URL {
        supportDirectory(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
}
