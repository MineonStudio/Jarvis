import SceneKit

/// Observe this window before SwiftUI HUD views route its mouse events.
/// The tiles and their animation remain entirely in SceneKit.
@MainActor
final class MahjongSceneInteractionView: SCNView {
    var onPointer: ((CGPoint?) -> Void)?
    var onTileClick: ((CGPoint) -> Void)?
    var containsTile: ((CGPoint) -> Bool)?
    private var eventMonitor: Any?
    private var pointerTracking: NSTrackingArea?
    private var pressedTile = false
    private static let activityNotifications: [Notification.Name] = [
        NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
        NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification
    ]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        preferredFramesPerSecond = window.screen?.maximumFramesPerSecond ?? 60
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.observe(event) == nil
            }
            return consumed ? nil : event
        }
        for name in Self.activityNotifications {
            let object: Any? = (name == NSWindow.didBecomeKeyNotification || name == NSWindow.didResignKeyNotification) ? window : nil
            NotificationCenter.default.addObserver(self, selector: #selector(refreshActivity), name: name, object: object)
        }
        refreshActivity()
    }

    override func layout() {
        super.layout()
        refreshActivity()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking {
            removeTrackingArea(pointerTracking)
        }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        pointerTracking = tracking
    }

    override func mouseExited(with _: NSEvent) {
        clearPointer()
    }

    override func mouseEntered(with _: NSEvent) {
        refreshPointer()
    }

    func refreshPointer() {
        guard let window, window.isKeyWindow, NSApp.isActive else {
            onPointer?(nil)
            return
        }
        onPointer?(worldPoint(window.mouseLocationOutsideOfEventStream))
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        for name in Self.activityNotifications {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        clearPointer()
        isPlaying = false
        rendersContinuously = false
    }

    @objc private func refreshActivity() {
        // Keep the foreground game's frame clock running through dealing and hovering.
        // Restarting it on each hover delays the first animated frame.
        let active = window?.isKeyWindow == true && NSApp.isActive
        if isPlaying != active {
            isPlaying = active
        }
        if rendersContinuously != active {
            rendersContinuously = active
        }
        needsDisplay = true
        refreshPointer()
    }

    @objc private func clearPointer() {
        pressedTile = false
        onPointer?(nil)
    }

    private func worldPoint(_ point: NSPoint) -> CGPoint? {
        MahjongHandLayout.worldPoint(convert(point, from: nil), size: bounds.size, isFlipped: isFlipped)
    }

    private func observe(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, window.isKeyWindow,
              window.attachedSheet == nil
        else {
            clearPointer()
            return event
        }
        let point = worldPoint(event.locationInWindow)
        onPointer?(point)
        switch event.type {
        case .leftMouseDown:
            pressedTile = point.map { containsTile?($0) == true } ?? false
            return pressedTile ? nil : event
        case .leftMouseUp:
            guard pressedTile else { return event }
            pressedTile = false
            if let point {
                onTileClick?(point)
            }
            return nil
        default:
            return event
        }
    }
}
