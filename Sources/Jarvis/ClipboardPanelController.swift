import AppKit
import QuartzCore
import SwiftUI

/// A keyboard-driven shelf anchored below the menu bar on the active display.
@MainActor
final class ClipboardPanelController {
    private(set) var panel: NSPanel?
    private var presentationScreen: NSScreen?
    private var screenObserver: NSObjectProtocol?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private let animationsEnabled: Bool
    private var preferredHeight: CGFloat?
    private var dismissalTask: Task<Void, Never>?
    private(set) var isPresented = false

    init(animationsEnabled: Bool = true) {
        self.animationsEnabled = animationsEnabled
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    isolated deinit {
        dismissalTask?.cancel()
        removeClickMonitors()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func toggle(app: AppModel) {
        if isPresented {
            hide()
        } else {
            show(app: app)
        }
    }

    func show(app: AppModel) {
        show {
            AnyView(ClipboardPanelView(onHeightChange: { [weak self] height in
                self?.updateHeight(height)
            })
            .environment(app)
            .jarvisAccentAware())
        }
    }

    func show(makeContent: () -> AnyView) {
        dismissalTask?.cancel()
        dismissalTask = nil
        let wasPresented = isPresented
        isPresented = true
        presentationScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if panel == nil {
            makePanel(content: makeContent())
        }
        guard let panel, let frame = resolvedFrame() else { isPresented = false; return }
        if !panel.isVisible, shouldAnimate {
            panel.alphaValue = 0
            panel.setFrame(resolvedFrame(height: frame.height - ClipboardPanelMotion.revealDistance) ?? frame, display: false)
        } else if !shouldAnimate || wasPresented {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
        }
        panel.ignoresMouseEvents = false
        // Keep the current app in the foreground, including in full-screen Spaces.
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickMonitors()
        animate(to: frame, alpha: 1, duration: ClipboardPanelMotion.showDuration)
    }

    func hide() {
        guard isPresented else { return }
        isPresented = false
        removeClickMonitors()
        guard let panel, panel.isVisible, shouldAnimate else { finishHiding(); return }
        panel.ignoresMouseEvents = true
        let frame = resolvedFrame(height: panel.frame.height - ClipboardPanelMotion.revealDistance) ?? panel.frame
        animate(to: frame, alpha: 0, duration: ClipboardPanelMotion.hideDuration)
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(ClipboardPanelMotion.hideDuration + 0.02))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !self.isPresented else { return }
            self.finishHiding()
            self.dismissalTask = nil
        }
    }

    private func finishHiding() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        positionPanel()
        JarvisLog.info(category: .window, event: "clipboard.panel.hidden")
    }

    private func animate(to frame: NSRect, alpha: CGFloat? = nil, duration: TimeInterval) {
        guard let panel else { return }
        guard shouldAnimate else {
            panel.setFrame(frame, display: true)
            if let alpha {
                panel.alphaValue = alpha
            }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
            if let alpha {
                panel.animator().alphaValue = alpha
            }
        }
    }

    func dismissIfClickOutside(at point: CGPoint, in window: NSWindow? = nil) {
        guard isPresented, let panel, panel.isVisible else { return }
        // Dropdowns and confirmation sheets belong to the shelf even when
        // their windows extend beyond its frame.
        if let window, isShelfWindow(window, panel: panel) {
            return
        }
        if containsClick(point, window: panel) {
            return
        }
        hide()
    }

    private func isShelfWindow(_ window: NSWindow, panel: NSWindow) -> Bool {
        if window === panel {
            return true
        }
        if let parent = window.parent ?? window.sheetParent {
            return isShelfWindow(parent, panel: panel)
        }
        return false
    }

    private func containsClick(_ point: CGPoint, window: NSWindow) -> Bool {
        guard window.isVisible else { return false }
        if NSMouseInRect(point, window.frame, false) {
            return true
        }
        return (window.childWindows ?? []).contains { containsClick(point, window: $0) }
            || window.attachedSheet.map { containsClick(point, window: $0) } == true
    }

    private func installClickMonitors() {
        removeClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickOutside(at: Self.screenPoint(for: event), in: event.window)
            }
            // The original click still reaches the app or window the user chose.
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickOutside(at: Self.screenPoint(for: event))
            }
        }
    }

    private static func screenPoint(for event: NSEvent) -> CGPoint {
        // Use the click's own coordinates; the pointer may already have moved
        // by the time a global monitor delivers the event.
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        if let point = event.cgEvent?.location, let primaryScreen = NSScreen.screens.first {
            return CGPoint(x: point.x, y: primaryScreen.frame.maxY - point.y)
        }
        return NSEvent.mouseLocation
    }

    private func removeClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    func updateHeight(_ height: CGFloat) {
        guard let panel, height.isFinite, height > 0 else { return }
        let height = ceil(height)
        guard preferredHeight != height else { return }
        preferredHeight = height
        guard let frame = resolvedFrame() else { return }
        if isPresented, panel.isVisible {
            animate(to: frame, duration: ClipboardPanelMotion.resizeDuration)
        } else if !panel.isVisible {
            panel.setFrame(frame, display: false)
        }
    }

    private func resolvedFrame(height: CGFloat? = nil) -> NSRect? {
        guard let panel, let screen = presentationScreen ?? NSScreen.main else { return nil }
        let height = max(1, height ?? preferredHeight ?? panel.frame.height)
        return NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.maxY - height,
            width: screen.frame.width,
            height: height
        )
    }

    private func positionPanel() {
        guard let frame = resolvedFrame() else { return }
        panel?.setFrame(frame, display: true)
    }

    private func makePanel(content: AnyView) {
        let width = (presentationScreen ?? NSScreen.main)?.frame.width ?? 1040
        preferredHeight = ClipboardPanelLayout.initialHeight(for: width)
        let panel = ClipboardShelfPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(
                width: width,
                height: ClipboardPanelLayout.initialHeight(for: width)
            )),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onCancel = { [weak self] in self?.hide() }
        panel.identifier = NSUserInterfaceItemIdentifier("Jarvis.ClipboardPanel")
        panel.title = "剪贴板"
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Liquid Glass supplies its own edge and shadow.
        panel.hasShadow = false
        let hostingView = ClipboardShelfHostingView(rootView: content)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let displayID = self.presentationScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                self.presentationScreen = NSScreen.screens.first {
                    $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == displayID
                } ?? NSScreen.main
                self.positionPanel()
            }
        }
    }
}

private final class ClipboardShelfPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}

/// Keep the window silhouette rounded synchronously with AppKit resizing,
/// including the frame before SwiftUI has redrawn its Liquid Glass surface.
private final class ClipboardShelfHostingView: NSHostingView<AnyView> {
    private let cornerMask = CAShapeLayer()

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        wantsLayer = true
        updateCornerMask()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateCornerMask()
    }

    private func updateCornerMask() {
        guard let layer else { return }
        var path = ClipboardPanelLayout.shape.path(in: bounds).cgPath
        if !isFlipped {
            var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.minY + bounds.maxY)
            path = path.copy(using: &flip) ?? path
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cornerMask.frame = bounds
        cornerMask.path = path
        layer.mask = cornerMask
        CATransaction.commit()
    }
}

extension AppModel {
    func toggleClipboardPanel() {
        clipboardPanelController.toggle(app: self)
    }
}
