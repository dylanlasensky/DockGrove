import AppKit
final class Host: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 400), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DockGrove Full Screen Test"
        window.collectionBehavior = [.fullScreenPrimary]
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 24
        stack.addArrangedSubview(NSTextField(labelWithString: "DockGrove should disappear in full screen and return after leaving it."))
        let button = NSButton(title: "Toggle Full Screen", target: self, action: #selector(toggle)); stack.addArrangedSubview(button)
        let quit = NSButton(title: "Close test host", target: NSApp, action: #selector(NSApplication.terminate(_:))); stack.addArrangedSubview(quit)
        window.contentView = NSView(); window.contentView!.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor), stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggle() { window.toggleFullScreen(nil) }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let delegate = Host(); app.delegate = delegate; app.run()
