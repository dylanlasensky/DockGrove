import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An AppKit drag source keeps a preview card's click action separate from its
/// mouse drag, including drags out of Settings into a nonactivating Dock panel.
struct NativeStudioDragSource: NSViewRepresentable {
    let item: DockStudioItem
    var clicked: () -> Void
    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.item = item
        view.clicked = clicked
    }

    final class SourceView: NSView, NSDraggingSource {
        var item: DockStudioItem?
        var clicked: (() -> Void)?
        private var down: CGPoint?
        private var started = false
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            down = convert(event.locationInWindow, from: nil)
            started = false
        }
        override func mouseDragged(with event: NSEvent) {
            guard !started, let down, let item else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - down.x, point.y - down.y) >= 4,
                  let data = try? JSONEncoder().encode(item) else { return }
            started = true
            let pasteboard = NSPasteboardItem()
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.dockStudioItem.identifier))
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboard)
            let image = NSImage(size: bounds.size)
            if let source = superview {
                let rect = convert(bounds, to: source)
                if let bitmap = source.bitmapImageRepForCachingDisplay(in: rect) {
                    source.cacheDisplay(in: rect, to: bitmap)
                    image.addRepresentation(bitmap)
                }
            }
            draggingItem.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }
        override func mouseUp(with event: NSEvent) {
            if !started, down != nil, bounds.contains(convert(event.locationInWindow, from: nil)) { clicked?() }
            down = nil
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            down = nil
            started = false
        }
    }
}
