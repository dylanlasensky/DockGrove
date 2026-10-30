import AppKit
import SwiftUI

enum NotchFileIntake {
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    static func existingURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            guard url.isFileURL, url.host.map({ $0.isEmpty || $0 == "localhost" }) != false else { return nil }
            let normalized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: normalized.path), seen.insert(normalized.path).inserted else { return nil }
            return normalized
        }
    }
}

/// A stable native drop destination remains attached while the compact notch expands.
final class NotchDropHostingView: NSHostingView<NotchShelfView> {
    weak var controller: NotchController?
    required init(rootView: NotchShelfView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard controller?.canAcceptFiles == true, sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        controller?.beginFileDrag()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { controller?.canAcceptFiles == true ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.fileDragActive = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.canAcceptFiles == true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = NotchFileIntake.urls(from: sender.draggingPasteboard)
        return controller?.acceptFiles(urls) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { controller?.fileDragActive = false }
}

enum NotchNavigationStyle: String, CaseIterable {
    case tabs = "Tabs", pills = "Rounded pills"
}

struct NotchNavigationLabel: View {
    let title: String
    let icon: String
    let selected: Bool
    let style: NotchNavigationStyle
    var body: some View {
        Label(title, systemImage: icon).font(.caption.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(selected && style == .pills ? Color.primary.opacity(0.14) : .clear, in: Capsule())
            .overlay(alignment: .bottom) {
                if style == .tabs {
                    Rectangle().fill(selected ? Color.primary : Color.primary.opacity(0.12)).frame(height: selected ? 2 : 1)
                }
            }
    }
}

enum NotchSection: String, CaseIterable {
    case home = "Home", tray = "Tray"
    var icon: String { switch self { case .home: return "square.grid.2x2"; case .tray: return "tray" } }
}

struct NotchHomeView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var controller: NotchController
    var body: some View {
        HStack(spacing: 12) {
            if model.canAccess(.music) { NotchMusicCard(player: kit.spotify.connected ? kit.spotify : kit.appleMusic) }
            else {
                HStack(spacing: 12) {
                    Image(systemName: "sun.max").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little space to focus").font(.headline)
                        Text("Your essentials, right at the top.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.frame(height: 64).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Focus", systemImage: "timer").font(.caption).foregroundStyle(.secondary)
                    Text(kit.timerText).font(.system(size: 25, weight: .light, design: .rounded)).monospacedDigit()
                }
                Button(action: kit.toggleTimer) { Image(systemName: kit.focusEnd == nil ? "play.fill" : "pause.fill").padding(10) }
                    .buttonStyle(.bordered).accessibilityLabel(kit.focusEnd == nil ? "Start focus" : "Pause focus")
            }.frame(width: 166, height: 64).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct NotchMusicCard: View {
    @ObservedObject var player: MusicPlayer
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = player.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                else { Image(systemName: "music.note").font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.08)) }
            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(player.track?.title ?? "Your music").font(.callout.weight(.semibold)).lineLimit(1)
                Text(player.track?.artist ?? player.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if player.connected {
                HStack(spacing: 18) {
                    Button { player.refresh(command: .previous) } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { player.refresh(command: .toggle) } label: { Image(systemName: player.track?.playing == true ? "pause.fill" : "play.fill") }.accessibilityLabel("Play or pause music")
                    Button { player.refresh(command: .next) } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.disabled(player.busy)
            } else {
                Button("Connect") { player.refresh() }.buttonStyle(.bordered).disabled(player.busy)
                    .accessibilityLabel("Connect " + player.name)
            }
        }.frame(height: 64).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct NotchTrayView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var controller: NotchController
    var body: some View {
        if !model.canAccess(.files) {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.title)
                Text("File tray is included with Plus").font(.headline)
                Text("Keep files nearby and drag them into other apps.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 210)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(kit.files.count) file\(kit.files.count == 1 ? "" : "s")", systemImage: "tray.fill").font(.caption.weight(.semibold))
                    Spacer()
                    Button("Add files…") { controller.addFiles() }
                    Button("Clear tray") { kit.files.removeAll(); controller.trayMessage = "Tray cleared. Original files are unchanged." }.disabled(kit.files.isEmpty)
                }.font(.caption)
                if kit.files.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 30, weight: .light))
                        Text(controller.fileDragActive ? "Release to add files" : "Drop files here").font(.headline)
                        Text("A temporary home for file shortcuts. Drag them back into any app.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 150)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5])))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 8) {
                            ForEach(kit.files, id: \.self) { path in trayItem(path) }
                        }
                    }.frame(height: 172)
                }
                Text(controller.trayMessage ?? "Removing a shortcut leaves the original file in place.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
    private func trayItem(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        return VStack(spacing: 7) {
            Button { NSWorkspace.shared.open(url) } label: {
                VStack(spacing: 5) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 34, height: 34)
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    if !exists { Text("File unavailable").font(.system(size: 9)).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity)
            }.disabled(!exists).onDrag { NSItemProvider(object: url as NSURL) }
            HStack(spacing: 18) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }.help("Reveal in Finder").disabled(!exists)
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.help("Share file").disabled(!exists)
                Button { kit.files.removeAll { $0 == path }; controller.trayMessage = "Shortcut removed. Original file is unchanged." } label: { Image(systemName: "xmark") }.help("Remove shortcut")
            }.font(.system(size: 10))
        }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
