import AppKit

@MainActor
private final class FixtureDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

/// Independent process for testing WindowServer discovery without AX permission.
@main
@MainActor
struct WindowLayoutFixture {
    static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: CGRect(x: 260, y: 160, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Jarvis 布局验证窗口"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = CGSize(width: 200, height: 160)
        let label = NSTextField(labelWithString: "拖动此窗口，验证其他应用的窗口布局")
        label.font = .systemFont(ofSize: 20)
        label.alignment = .center
        label.frame = CGRect(x: 40, y: 210, width: 560, height: 40)
        window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(delegate) { app.run() }
    }
}
