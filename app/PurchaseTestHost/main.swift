import AppKit

// Isolated host for StoreKitTest. No Dock, user preferences, or real storefront.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.title = "DockGrove StoreKit Tests"
window.makeKeyAndOrderFront(nil)
app.run()
