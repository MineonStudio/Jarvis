import AppKit
import SwiftUI

/// Owns the main window's AppKit lifecycle independently from SwiftUI's view
/// redraws. The window frame is restored once when the NSWindow is attached and
/// persisted from window lifecycle notifications afterward.
@MainActor
final class JarvisMainWindowController: NSObject, ObservableObject {
    static let frameAutosaveName = "Jarvis.MainWindow"
    static var defaultWindowSize: CGSize {
        CGSize(
            width: max(1380, JarvisWindowLayoutMetrics.mainWindowMinimumWidth),
            height: max(760, JarvisWindowLayoutMetrics.mainWindowMinimumHeight)
        )
    }

    /// The minimum frame is derived from the intrinsic controls used by the
    /// navigation, clipboard, window-layout, and AI conversation surfaces.
    static var minimumWindowSize: CGSize {
        CGSize(
            width: JarvisWindowLayoutMetrics.mainWindowMinimumWidth,
            height: JarvisWindowLayoutMetrics.mainWindowMinimumHeight
        )
    }

    /// Initial content size for the SwiftUI scene. The saved origin is applied
    /// later, on the AppKit window, without animating from this size.
    static var launchWindowSize: CGSize {
        launchWindowSize(savedFrame: JarvisWindowFrameStore().load())
    }

    static func launchWindowSize(savedFrame: NSRect?) -> CGSize {
        resolvedLaunchFrame(
            savedFrame: savedFrame,
            fallbackOrigin: .zero,
            visibleFrames: []
        ).size
    }

    /// Full frame to show on launch. A saved frame that misses every visible
    /// screen keeps its size and takes `fallbackOrigin`. A missing or too-small
    /// frame uses the default size at that same origin.
    static func resolvedLaunchFrame(
        savedFrame: NSRect?,
        fallbackOrigin: CGPoint,
        visibleFrames: [NSRect]
    ) -> NSRect {
        guard let savedFrame, isUsable(savedFrame) else {
            return NSRect(origin: fallbackOrigin, size: defaultWindowSize)
        }
        let isOnScreen = visibleFrames.contains { $0.intersects(savedFrame) }
        let origin = isOnScreen ? savedFrame.origin : fallbackOrigin
        return NSRect(origin: origin, size: savedFrame.size)
    }

    static func applyLaunchFrame(_ frame: NSRect, to window: NSWindow) {
        window.animationBehavior = .none
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        window.setFrame(frame, display: false, animate: false)
        NSAnimationContext.endGrouping()
    }

    private let frameStore = JarvisWindowFrameStore()
    private weak static var activeController: JarvisMainWindowController?
    private weak var window: NSWindow?
    private var frameObservers: [NSObjectProtocol] = []
    private var pendingFrameSave: Task<Void, Never>?
    private var isInFullScreenTransition = false

    isolated deinit {
        pendingFrameSave?.cancel()
        frameObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func attach(to window: NSWindow?) {
        guard let window, self.window !== window else { return }
        detach()
        self.window = window
        Self.activeController = self
        JarvisWindowAppearance.configure(for: window)
        JarvisWindowAppearance.configureStandardControls(for: window)
        window.level = .normal
        window.minSize = Self.minimumWindowSize

        // Restore once before presentation. Subsequent changes belong to
        // AppKit: zoom, tiling and full-screen transitions must never be pinned.
        let target = Self.resolvedLaunchFrame(
            savedFrame: frameStore.load(),
            fallbackOrigin: window.frame.origin,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.styleMask.contains(.fullScreen) {
            Self.applyLaunchFrame(target, to: window)
        }
        window.animationBehavior = .default
        observeFrameChanges(of: window)
        if NSApp.isActive {
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func applyWindowLayoutFrame(_ frame: NSRect, to window: NSWindow) -> Bool {
        guard let controller = activeController, controller.window === window else { return false }
        controller.applyWindowLayoutFrame(frame)
        return true
    }

    private func applyWindowLayoutFrame(_ frame: NSRect) {
        guard let window else { return }
        // Allow an explicitly requested half/quadrant layout, without making
        // its entire size the permanent minimum for future system operations.
        window.minSize = NSSize(
            width: min(Self.minimumWindowSize.width, frame.width),
            height: min(Self.minimumWindowSize.height, frame.height)
        )
        window.contentMinSize = .zero
        window.setFrame(frame, display: true, animate: false)
        window.level = .normal
        window.orderFront(nil)
        saveFrameImmediately()
    }

    private func detach() {
        pendingFrameSave?.cancel()
        pendingFrameSave = nil
        frameObservers.forEach(NotificationCenter.default.removeObserver)
        frameObservers.removeAll()
        isInFullScreenTransition = false
        window = nil
    }

    private static func isUsable(_ frame: NSRect) -> Bool {
        frame.width >= minimumWindowSize.width && frame.height >= minimumWindowSize.height
    }

    private static func observe(
        _ name: Notification.Name,
        of window: NSWindow,
        perform: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { _ in
            MainActor.assumeIsolated(perform)
        }
    }

    private func observeFrameChanges(of window: NSWindow) {
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didDeminiaturizeNotification] {
            frameObservers.append(Self.observe(name, of: window) { [weak self] in
                self?.scheduleFrameSave()
            })
        }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            frameObservers.append(Self.observe(name, of: window) { [weak self] in
                self?.isInFullScreenTransition = true
                self?.pendingFrameSave?.cancel()
            })
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            frameObservers.append(Self.observe(name, of: window) { [weak self] in
                self?.isInFullScreenTransition = false
                self?.scheduleFrameSave()
            })
        }
        frameObservers.append(Self.observe(NSWindow.willCloseNotification, of: window) { [weak self] in
            self?.saveFrameImmediately()
        })
    }

    private func scheduleFrameSave() {
        pendingFrameSave?.cancel()
        pendingFrameSave = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.saveFrameImmediately()
        }
    }

    private func saveFrameImmediately() {
        guard let window, !isInFullScreenTransition,
              !window.styleMask.contains(.fullScreen), !window.isMiniaturized else { return }
        pendingFrameSave?.cancel()
        pendingFrameSave = nil
        frameStore.save(window.frame)
    }
}

struct JarvisMainWindowAccessor: NSViewRepresentable {
    let controller: JarvisMainWindowController

    func makeNSView(context _: Context) -> NSView {
        let view = JarvisMainWindowAnchorView(frame: .zero)
        view.onResolveWindow = { [weak controller] window in
            controller?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        MainActor.assumeIsolated {
            controller.attach(to: nsView.window)
        }
    }
}

/// Receives the NSWindow while it is being attached, before SwiftUI has a
/// chance to show the default size and animate it to the saved frame.
private final class JarvisMainWindowAnchorView: NSView {
    var onResolveWindow: ((NSWindow) -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        MainActor.assumeIsolated {
            onResolveWindow?(newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        MainActor.assumeIsolated {
            onResolveWindow?(window)
        }
    }
}
