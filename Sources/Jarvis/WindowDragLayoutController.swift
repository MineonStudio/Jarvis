import AppKit

struct WindowDragLayoutDelay {
    static let duration: TimeInterval = 1
    private var movementBeganAt: TimeInterval?

    mutating func observe(isMoving: Bool, at time: TimeInterval) {
        if isMoving, movementBeganAt == nil {
            movementBeganAt = time
        }
    }

    func isReady(at time: TimeInterval) -> Bool {
        guard let movementBeganAt else { return false }
        return time - movementBeganAt >= Self.duration
    }

    mutating func reset() {
        movementBeganAt = nil
    }
}

/// Event monitors preserve the original events; common-mode polling also covers
/// native window tracking loops that consume mouse-dragged or mouse-up events.
@MainActor
final class WindowDragLayoutController {
    private let layoutController: WindowLayoutController
    private let overlay = WindowSnapOverlayController { _ in
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var watchdog: Timer?
    private var trackingTimer: Timer?
    private var target: WindowDragTarget?
    private var motion: WindowDragMotion?
    private var presentationDelay = WindowDragLayoutDelay()
    private var buttonWasDown = false
    private var lastSampleTime: TimeInterval = 0
    private var pendingDrop: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var workspaceAvailable = true

    init(layoutController: WindowLayoutController) {
        self.layoutController = layoutController
    }

    isolated deinit { stop() }

    func start() {
        guard watchdog == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.workspaceAvailable = false
                    self?.cancel()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.workspaceAvailable = true }
            })
        }
        buttonWasDown = NSEvent.pressedMouseButtons & 1 != 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollButton() }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        JarvisLog.info(category: .window, event: "windowDrag.monitor.started")
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        watchdog?.invalidate()
        watchdog = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        cancel()
    }

    func cancel() {
        pendingDrop?.cancel()
        pendingDrop = nil
        clearTracking()
    }

    private func clearTracking(animated: Bool = false) {
        target = nil
        motion = nil
        presentationDelay.reset()
        trackingTimer?.invalidate()
        trackingTimer = nil
        overlay.hide(animated: animated)
    }

    private func handle(_ event: NSEvent) {
        guard workspaceAvailable else { return }
        switch event.type {
        case .leftMouseDown:
            if !buttonWasDown {
                begin(at: NSEvent.mouseLocation, eventWindow: event.window)
            }
            buttonWasDown = true
        case .leftMouseDragged:
            sample()
        case .leftMouseUp:
            finish(at: NSEvent.mouseLocation)
            buttonWasDown = false
        case .keyDown where event.keyCode == 53:
            cancel()
        default:
            break
        }
    }

    private func pollButton() {
        guard workspaceAvailable else { return }
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if down, !buttonWasDown {
            begin(at: NSEvent.mouseLocation, eventWindow: nil)
        } else if !down, buttonWasDown {
            finish(at: NSEvent.mouseLocation)
        }
        buttonWasDown = down
    }

    private func begin(at pointer: CGPoint, eventWindow: NSWindow?) {
        pendingDrop?.cancel()
        pendingDrop = nil
        cancel()
        guard let target = WindowDragTarget.capture(at: pointer, eventWindow: eventWindow),
              let frame = target.frame else { return }
        self.target = target
        JarvisLog.debug(category: .window, event: "windowDrag.candidate", fields: ["native": String(target.nativeWindow != nil)])
        motion = WindowDragMotion(pointer: pointer, frame: frame)
        lastSampleTime = 0
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func sample() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            finish(at: NSEvent.mouseLocation)
            buttonWasDown = false
            return
        }
        // Hit-test at pointer cadence; WindowServer reads stay throttled.
        // A busy native window drag must not delay the highlighted drop target.
        let pointer = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        if motion?.isMoving == true, presentationDelay.isReady(at: now) {
            updateOverlay(at: pointer)
        }
        guard now - lastSampleTime >= 1.0 / 35 else { return }
        lastSampleTime = now
        guard let target, let frame = target.frame else {
            cancel()
            return
        }
        let wasMoving = motion?.isMoving == true
        motion?.observe(pointer: pointer, frame: frame)
        if motion?.isRejected == true {
            cancel()
            return
        }
        guard motion?.isMoving == true else { return }
        if !wasMoving {
            JarvisLog.info(category: .window, event: "windowDrag.movement.confirmed")
        }
        presentationDelay.observe(isMoving: true, at: now)
        if presentationDelay.isReady(at: now) {
            updateOverlay(at: pointer)
        }
    }

    private func updateOverlay(at pointer: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else {
            overlay.hide()
            return
        }
        overlay.update(pointer: pointer, on: screen)
    }

    private func finish(at pointer: CGPoint) {
        // Mouse-up can arrive through both the event monitor and the timer.
        // The second notification must not cut off the dismissal animation.
        guard target != nil else { return }
        // Validate the final position, but never reveal a picker on mouse-up.
        // Short drags must not apply an unseen layout beneath the pointer.
        if let frame = target?.frame {
            motion?.observe(pointer: pointer, frame: frame)
        }
        let delayElapsed = presentationDelay.isReady(at: ProcessInfo.processInfo.systemUptime)
        if delayElapsed, overlay.geometry != nil, motion?.isMoving == true, motion?.isRejected != true,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
        {
            overlay.update(pointer: pointer, on: screen)
        }
        let originalTarget = target
        let drop = delayElapsed && motion?.isMoving == true && motion?.isRejected != true ? overlay.drop(at: pointer) : nil
        if motion?.isMoving == true {
            JarvisLog.info(category: .window, event: "windowDrag.ended", fields: ["placement": drop?.0.rawValue ?? "cancelled"])
        }
        clearTracking(animated: true)
        guard let originalTarget, let (placement, screen) = drop else { return }
        // Let the application's native move operation finish before setting its final frame.
        pendingDrop = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.layoutController.apply(placement, to: originalTarget, on: screen)
            self?.pendingDrop = nil
        }
    }
}
