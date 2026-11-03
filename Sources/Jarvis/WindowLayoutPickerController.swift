import AppKit

/// F5 and dragging use the same surfaces, but a picker click never changes focus.
@MainActor
final class WindowLayoutPickerController {
    let overlay: WindowSnapOverlayController
    private let layoutController: WindowLayoutController
    private var target: WindowDragTarget?
    private var pressedPlacement: WindowSnapPlacement?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pointerTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    var isPresented: Bool {
        target != nil
    }

    init(layoutController: WindowLayoutController, overlay: WindowSnapOverlayController = WindowSnapOverlayController()) {
        self.layoutController = layoutController
        self.overlay = overlay
    }

    isolated deinit { cancel() }

    func present(target: WindowDragTarget, on screen: NSScreen) {
        cancel()
        self.target = target
        JarvisLog.info(category: .window, event: "windowLayout.picker.shown", fields: ["native": String(target.nativeWindow != nil)])
        overlay.present(on: screen, acceptsClicks: true)
        overlay.updateSelection(at: NSEvent.mouseLocation)
        installMonitors()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.target?.frame != nil else { self.cancel(); return }
                self.overlay.updateSelection(at: NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let processID, processID != self.target?.processIdentifier else { return }
                self.cancel()
            }
        })
    }

    func cancel(animated: Bool = false) {
        target = nil
        pressedPlacement = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        overlay.hide(animated: animated)
    }

    func mouseDown(at pointer: CGPoint) {
        guard isPresented else { return }
        pressedPlacement = overlay.drop(at: pointer)?.0
        if pressedPlacement == nil {
            cancel(animated: true)
        }
    }

    func mouseUp(at pointer: CGPoint) {
        guard let target, let pressedPlacement else { return }
        guard let (placement, screen) = overlay.drop(at: pointer), placement == pressedPlacement else {
            cancel(animated: true)
            return
        }
        cancel(animated: true)
        JarvisLog.info(category: .window, event: "windowLayout.picker.selected", fields: ["placement": placement.rawValue])
        layoutController.apply(placement, to: target, on: screen)
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isPresented else { return false }
                let isPanel = self.overlay.optionPanels.values.contains { $0 === event.window }
                let isEscape = event.type == .keyDown && event.keyCode == JarvisKeyCode.escape
                self.handle(event)
                return isPanel || isEscape
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown(at: NSEvent.mouseLocation)
        case .leftMouseUp: mouseUp(at: NSEvent.mouseLocation)
        case .rightMouseDown, .otherMouseDown: cancel(animated: true)
        case .keyDown where event.keyCode == JarvisKeyCode.escape: cancel(animated: true)
        default: break
        }
    }
}

enum WindowLayoutShortcutMigration {
    static func apply(to defaults: UserDefaults = .standard) {
        for layout in ["halfLeft", "halfRight", "upperLeft", "upperRight", "lowerLeft", "lowerRight"] {
            defaults.removeObject(forKey: "jarvis.window-layout.shortcut." + layout)
        }
    }
}
