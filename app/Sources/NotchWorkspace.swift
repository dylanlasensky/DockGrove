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
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, controller.canAccept(controller.defaultDropDestination) else { return [] }
        controller.activeDropDestination = controller.defaultDropDestination
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.fileDragActive = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.canAcceptFiles == true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = NotchFileIntake.urls(from: sender.draggingPasteboard)
        guard let controller else { return false }
        return controller.acceptDrop(urls, to: controller.defaultDropDestination)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { controller?.fileDragActive = false }
}

enum NotchDropDestination { case tray, airDrop }

/// Native destinations distinguish the two zones while the parent handles the resting notch.
struct NotchDropTarget: NSViewRepresentable {
    let destination: NotchDropDestination
    let controller: NotchController
    func makeNSView(context: Context) -> NotchDropTargetView {
        let view = NotchDropTargetView()
        view.destination = destination; view.controller = controller
        return view
    }
    func updateNSView(_ view: NotchDropTargetView, context: Context) {
        view.destination = destination; view.controller = controller
    }
}

final class NotchDropTargetView: NSView {
    var destination: NotchDropDestination = .tray
    weak var controller: NotchController?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { controller?.activateDropZone(destination) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard controller?.canAccept(destination) == true,
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        controller?.beginFileDrag(); controller?.activeDropDestination = destination
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard controller?.canAccept(destination) == true else { return [] }
        controller?.fileDragActive = true; controller?.activeDropDestination = destination
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearHighlight() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.canAccept(destination) == true }
    func accept(_ pasteboard: NSPasteboard) -> Bool {
        controller?.acceptDrop(NotchFileIntake.urls(from: pasteboard), to: destination) ?? false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { accept(sender.draggingPasteboard) }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { clearHighlight() }
    private func clearHighlight() {
        if controller?.activeDropDestination == destination {
            controller?.fileDragActive = false; controller?.activeDropDestination = nil
        }
    }
}

struct NotchDropZone: View {
    let destination: NotchDropDestination
    @ObservedObject var controller: NotchController
    var width: CGFloat = 280
    private var isTray: Bool { destination == .tray }
    private var highlighted: Bool { controller.fileDragActive && controller.activeDropDestination == destination }
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isTray ? "tray.and.arrow.down" : "airplayaudio").font(.system(size: 27, weight: .light))
            VStack(alignment: .leading, spacing: 5) {
                Text(isTray ? "File tray" : "AirDrop").font(.headline)
                Text(highlighted ? (isTray ? "Release to keep files" : "Release to review files") : (isTray ? "Drop files to keep them here" : controller.airDropMessage))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(isTray || controller.airDropReview ? "or click to choose files" : "or click to open AirDrop").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).frame(width: width, height: 84)
            .background(highlighted ? Color.accentColor.opacity(0.18) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(highlighted ? Color.accentColor : .white.opacity(0.2), style: StrokeStyle(lineWidth: highlighted ? 2 : 1, dash: [5])))
            .overlay(NotchDropTarget(destination: destination, controller: controller))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isTray ? "File tray drop zone" : "AirDrop drop zone")
            .accessibilityHint(isTray ? "Drop files to keep shortcuts, or activate to choose files" : "Drop files to review for AirDrop, or activate to open the custom AirDrop panel")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { controller.activateDropZone(destination) }
    }
}

struct NotchHomeView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var controller: NotchController
    var body: some View {
        HStack(spacing: 12) {
            if model.canAccess(.music) { NotchMusicCard(player: kit.spotify.connected ? kit.spotify : kit.appleMusic, openSettings: { model.openConnectionSettings(kit.spotify.connected ? .spotify : .appleMusic) }).frame(width: 320) }
            else {
                HStack(spacing: 12) {
                    Image(systemName: "sun.max").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little space to focus").font(.headline)
                        Text("Scroll for your widgets.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.frame(width: 300, height: 64).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Focus", systemImage: "timer").font(.caption).foregroundStyle(.secondary)
                    Text(kit.timerText).font(.system(size: 21, weight: .light, design: .rounded)).monospacedDigit()
                }
                Button(action: kit.toggleTimer) { Image(systemName: kit.focusEnd == nil ? "play.fill" : "pause.fill").padding(4) }
                    .buttonStyle(.plain).accessibilityLabel(kit.focusEnd == nil ? "Start focus" : "Pause focus")
            }.frame(width: 188, height: 64).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct NotchMusicCard: View {
    @ObservedObject var player: MusicPlayer
    let openSettings: () -> Void
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
                Button(action: openSettings) { Image(systemName: "gearshape").padding(5) }.buttonStyle(.plain)
                    .accessibilityLabel("Open " + player.name + " connection settings")
            }
        }.frame(height: 64).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

enum NotchFileLayout {
    static func halfWidth(_ viewport: CGFloat) -> CGFloat { max(1, (viewport - 32 - 10) / 2) }
}

struct NotchAirDropReview: View {
    @ObservedObject var controller: NotchController
    let width: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("AirDrop", systemImage: "airplayaudio").font(.headline)
                Spacer()
                Text("\(controller.airDropFiles.count) selected").font(.caption).foregroundStyle(.secondary)
                    .contextMenu { Button("Clear selection") { controller.clearAirDropFiles() }.disabled(controller.airDropBusy) }
                    .accessibilityAction(named: Text("Clear selection")) { controller.clearAirDropFiles() }
            }
            if controller.airDropFiles.isEmpty {
                Text("Drop files here or add them below").font(.caption).foregroundStyle(.secondary).frame(height: 22)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(controller.airDropFiles, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "doc").font(.caption).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                                .contextMenu { Button("Remove from AirDrop") { controller.removeAirDropFile(url) }.disabled(controller.airDropBusy) }
                                .accessibilityAction(named: Text("Remove from AirDrop")) { controller.removeAirDropFile(url) }
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: 22)
            }
            HStack(spacing: 10) {
                Button { controller.airDropReview = false } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }.help("Close AirDrop review").accessibilityLabel("Close AirDrop review")
                Button { controller.addFiles(to: .airDrop) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }.disabled(controller.airDropBusy).help("Add files").accessibilityLabel("Add files to AirDrop")
                Spacer(minLength: 0)
                Button { controller.startAirDrop() } label: {
                    Label(controller.airDropBusy ? "Choosing…" : "Choose device", systemImage: "airplayaudio").padding(.vertical, 4)
                }.buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(controller.airDropBusy || controller.airDropFiles.isEmpty)
            }.font(.caption)
        }.padding(.horizontal, 12).frame(width: width, height: 84)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            .help(controller.airDropMessage)
    }
}

struct NotchTrayView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var kit: Toolkit
    @ObservedObject var controller: NotchController
    var body: some View {
        HStack(spacing: 10) {
            if !model.canAccess(.files) {
                Label("File tray · Plus", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 220, height: 84)
            } else {
                NotchDropZone(destination: .tray, controller: controller, width: NotchFileLayout.halfWidth(controller.expandedWidth))
                if controller.airDropReview {
                    NotchAirDropReview(controller: controller, width: NotchFileLayout.halfWidth(controller.expandedWidth))
                } else {
                    NotchDropZone(destination: .airDrop, controller: controller, width: NotchFileLayout.halfWidth(controller.expandedWidth))
                }
                if !kit.files.isEmpty {
                    VStack(spacing: 8) {
                        Text("\(kit.files.count) file\(kit.files.count == 1 ? "" : "s")").font(.caption)
                    }.frame(width: 70)
                        .contextMenu { Button("Clear tray") { kit.files.removeAll(); controller.trayMessage = "Original files are unchanged." } }
                        .accessibilityAction(named: Text("Clear tray")) { kit.files.removeAll(); controller.trayMessage = "Original files are unchanged." }
                    ForEach(kit.files, id: \.self) { path in trayItem(path).frame(width: NotchFileLayout.halfWidth(controller.expandedWidth)) }
                }
            }
        }.frame(height: 84).help(controller.trayMessage ?? "File shortcuts: removing them leaves the originals unchanged.")
    }
    private func trayItem(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        return Button { if exists { NSWorkspace.shared.open(url) } } label: {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                    Text(exists ? "Drag to use · right-click for actions" : "File unavailable")
                        .font(.system(size: 10)).foregroundStyle(exists ? Color.secondary : .orange)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 84)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).onDrag { exists ? NSItemProvider(object: url as NSURL) : NSItemProvider() }
            .contextMenu {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(!exists)
                ShareLink(item: url) { Label("Share file", systemImage: "square.and.arrow.up") }.disabled(!exists)
                Button("Remove shortcut") { kit.files.removeAll { $0 == path }; controller.trayMessage = "Shortcut removed. Original file is unchanged." }
            }
            .accessibilityAction(named: Text("Remove shortcut")) { kit.files.removeAll { $0 == path } }

    }
}
