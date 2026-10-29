import AppKit
import SwiftUI

enum MusicReadFailure: Error {
    case automation(Int)
    var message: String {
        switch self {
        case .automation(-1743): return "macOS denied Automation access. Enable this player for WaveDock in Privacy & Security > Automation, then retry. Rebuilt copies may need a fresh permission grant."
        case .automation(-1712): return "The player took too long to respond. Open it, finish any welcome screens, then retry."
        case .automation(-1728): return "No current track is available. Select a track in the player and retry."
        case .automation(let code): return "The player could not complete the request (macOS error \(code)). Open it and retry."
        }
    }
}
struct TrackSnapshot: Equatable {
    let title: String
    let artist: String
    let playing: Bool
    var artworkReference = ""
    static func decode(_ data: Data) throws -> TrackSnapshot {
        let lines = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines).components(separatedBy: "\u{1e}")
        if lines.first == "error", lines.count > 1, let code = Int(lines[1]) { throw MusicReadFailure.automation(code) }
        guard [3,4].contains(lines.count), ["playing", "paused", "stopped"].contains(lines[0]) else { throw UsageError.service }
        return TrackSnapshot(title: lines[1], artist: lines[2], playing: lines[0] == "playing", artworkReference: lines.count == 4 ? lines[3] : "")
    }
}
enum MusicCommand: String, CaseIterable { case previous = "previous track", toggle = "playpause", next = "next track" }
@MainActor final class MusicPlayer: ObservableObject {
    let name: String
    let bundleID: String
    @Published var track: TrackSnapshot?
    @Published var artwork: NSImage?
    @Published var artworkTint = Color(white:0.12)
    private var artworkKey = ""
    private var artworkTask: Task<Void,Never>?
    @Published var connected = false
    @Published var busy = false
    @Published var status = "Connect to your running music player. macOS may ask for Automation permission."
    private var generation = 0
    private var timer: Timer?
    init(name: String, bundleID: String) {
        self.name = name; self.bundleID = bundleID
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in if self?.connected == true { self?.refresh() } } }
    }
    deinit { timer?.invalidate(); artworkTask?.cancel() }
    func openPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { status = "\(name) is not installed on this Mac."; return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }
    func disconnect() { generation += 1; connected = false; track = nil; clearArtwork(); busy = false; status = "Disconnected." }
    func refresh(command: MusicCommand? = nil) {
        guard !busy else { return }
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { connected = false; track = nil; clearArtwork(); status = "Open \(name), then Connect."; return }
        busy = true; let requestID = generation, bundle = bundleID
        // Only fixed application IDs and enumerated transport commands enter the script.
        let script = """
        try
          with timeout of 5 seconds
            tell application id "\(bundle)"
              \(command?.rawValue ?? "")
              set playback to player state as text
              if playback is "stopped" then return "stopped" & (ASCII character 30) & "Nothing playing" & (ASCII character 30) & " "
              \(bundle == "com.apple.Music" ? "if not (exists current track) then return \"stopped\" & (ASCII character 30) & \"Nothing playing\" & (ASCII character 30) & \" \"" : "")
              set imageReference to ""
              try
                \(bundle == "com.spotify.client" ? "set imageReference to artwork url of current track" : "set imageReference to persistent ID of current track")
              end try
              return playback & (ASCII character 30) & (name of current track) & (ASCII character 30) & (artist of current track) & (ASCII character 30) & imageReference
            end tell
          end timeout
        on error number errorNumber
          return "error" & (ASCII character 30) & (errorNumber as text) & (ASCII character 30) & " "
        end try
        """
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) { Result { try BoundedProcess.run("/usr/bin/osascript", arguments: ["-e", script], timeout: 8) } }.value
            guard requestID == generation else { return }; busy = false
            switch result {
            case .success(let data):
                do { track = try TrackSnapshot.decode(data); connected = true; status = "Connected to \(name)"; refreshArtwork() }
                catch let failure as MusicReadFailure { connected = false; track = nil; clearArtwork(); status = failure.message }
                catch { connected = false; track = nil; clearArtwork(); status = "No readable track. Open the player and select music, then reconnect." }
            case .failure:
                connected = false; track = nil; clearArtwork()
                status = "Could not read \(name). Allow WaveDock in Privacy & Security > Automation, or select a track and retry."
            }
        }
    }
    func clearArtwork() { artworkTask?.cancel(); artworkTask=nil; artworkKey=""; artwork=nil; artworkTint=Color(white:0.12) }
    private func refreshArtwork() {
        guard let track, !track.artworkReference.isEmpty else { clearArtwork(); return }
        let key=track.title + "\u{1f}" + track.artist + "\u{1f}" + track.artworkReference
        guard key != artworkKey else { return }
        clearArtwork(); artworkKey=key
        let reference=track.artworkReference, bundle=bundleID
        artworkTask=Task { @MainActor [weak self] in
            do {
                let data:Data
                if bundle == "com.spotify.client" {
                    guard let url=URL(string:reference) else { return }; data=try await AlbumArtwork.fetch(url)
                } else {
                    let output=try await Task.detached(priority:.utility) { try BoundedProcess.run("/usr/bin/osascript",arguments:["-e", "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"],timeout:6) }.value
                    guard let decoded=AlbumArtwork.appleData(output) else { return }; data=decoded
                }
                guard !Task.isCancelled, let self, self.artworkKey == key, let image=AlbumArtwork.decode(data) else { return }
                self.artwork=image; self.artworkTint=AlbumArtwork.tint(image)
            } catch { /* Missing artwork keeps the readable neutral fallback and transport controls. */ }
        }
    }

}
/// Bounded subprocess reads keep denied or hung Automation requests off the main thread.
enum BoundedProcess {
    static func run(_ path: String, arguments: [String], timeout: TimeInterval) throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            }
        }
        var data = Data(); let deadline = Date().addingTimeInterval(timeout)
        let fd = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&poller, 1, 100) > 0 {
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count == 0 {
                    // Do not block indefinitely if a child closes stdout before exiting.
                    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                    guard !process.isRunning, process.terminationStatus == 0 else { throw UsageError.service }
                    return data
                }
                guard count > 0 else { throw UsageError.service }; data.append(contentsOf: buffer.prefix(count))
                guard data.count < 2_000_000 else { throw UsageError.service }
            }
        }
        throw UsageError.timeout
    }
}
struct MusicPlayerView: View {
    @ObservedObject var player: MusicPlayer
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing:12) { MusicArtworkView(player:player,size:64); Text(player.track?.title ?? player.name).font(.headline).lineLimit(3) }
            if let track = player.track { Text(track.artist).foregroundStyle(.secondary); Text(track.playing ? "Playing" : "Paused / stopped").font(.caption) }
            Text(player.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open \(player.name)", action: player.openPlayer)
                Button(player.busy ? "Connecting…" : "Connect / refresh") { player.refresh() }.disabled(player.busy)
            }
            if player.connected {
                HStack {
                    Button("Previous") { player.refresh(command: .previous) }
                    Button(player.track?.playing == true ? "Pause" : "Play") { player.refresh(command: .toggle) }
                    Button("Next") { player.refresh(command: .next) }
                }.disabled(player.busy)
                Button("Disconnect", action: player.disconnect)
            }
        }
    }
}
