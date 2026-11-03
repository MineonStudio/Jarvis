import AppKit

@MainActor
final class WindowSnapOverlayController {
    private(set) var geometry: WindowSnapBarGeometry?
    private(set) var screen: NSScreen?
    private(set) var selection: WindowSnapPlacement?
    private(set) var optionPanels: [WindowSnapGroup: NSPanel] = [:]
    private var optionViews: [WindowSnapGroup: WindowSnapOptionView] = [:]
    private let animationsEnabled: Bool
    private let onSelection: ((WindowSnapPlacement) -> Void)?
    private var dismissalTask: Task<Void, Never>?
    private var acceptsClicks = false

    init(animationsEnabled: Bool = true, onSelection: ((WindowSnapPlacement) -> Void)? = nil) {
        self.animationsEnabled = animationsEnabled
        self.onSelection = onSelection
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    isolated deinit {
        dismissalTask?.cancel()
        optionPanels.values.forEach { $0.close() }
    }

    func update(pointer: CGPoint, on screen: NSScreen) {
        guard screen.frame.contains(pointer) else { hide(); return }
        if self.screen !== screen {
            hide()
            show(on: screen)
        }
        updateSelection(at: pointer)
    }

    func present(on screen: NSScreen, acceptsClicks: Bool) {
        hide()
        self.acceptsClicks = acceptsClicks
        show(on: screen)
    }

    func updateSelection(at pointer: CGPoint) {
        guard let geometry else { return }
        let placement = geometry.placement(at: pointer)
        guard placement != selection else { return }
        if let selection {
            optionViews[selection.group]?.setSelection(nil, animated: shouldAnimate)
        }
        selection = placement
        if let placement {
            optionViews[placement.group]?.setSelection(placement, animated: shouldAnimate)
            onSelection?(placement)
        }
    }

    func drop(at pointer: CGPoint) -> (WindowSnapPlacement, NSScreen)? {
        guard let screen, screen.frame.contains(pointer), let geometry,
              let placement = geometry.placement(at: pointer) else { return nil }
        return (placement, screen)
    }

    func hide(animated: Bool = false) {
        dismissalTask?.cancel()
        dismissalTask = nil
        optionPanels.values.forEach { $0.ignoresMouseEvents = true }
        let wasVisible = geometry != nil
        geometry = nil
        screen = nil
        selection = nil
        guard animated, shouldAnimate, wasVisible else {
            finishHiding()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            optionPanels.values.forEach { $0.animator().alphaValue = 0 }
        }
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            self?.finishHiding()
            self?.dismissalTask = nil
        }
    }

    private func finishHiding() {
        for value in optionPanels.values {
            value.orderOut(nil)
            value.alphaValue = 1
            value.ignoresMouseEvents = true
        }
        acceptsClicks = false
        optionViews.values.forEach { $0.resetAnimations() }
    }

    private func show(on screen: NSScreen) {
        JarvisLog.info(category: .window, event: "windowDrag.bar.shown")
        let geometry = WindowSnapBarGeometry(visibleFrame: screen.visibleFrame)
        self.geometry = geometry
        self.screen = screen
        let appearance = NSApplication.shared.windows.first {
            $0.identifier?.rawValue == JarvisAppIdentity.mainWindowSceneID
        }?.effectiveAppearance
        for group in WindowSnapGroup.allCases {
            let rect = geometry.localRect(for: group)
                .offsetBy(dx: geometry.frame.minX, dy: geometry.frame.minY)
            let panel: NSPanel
            if let existing = optionPanels[group] {
                panel = existing
            } else {
                panel = Self.makePanel(group: group)
                let view = WindowSnapOptionView(group: group, frame: CGRect(origin: .zero, size: rect.size))
                panel.contentView = view
                optionPanels[group] = panel
                optionViews[group] = view
            }
            panel.appearance = appearance
            panel.ignoresMouseEvents = !acceptsClicks
            optionViews[group]?.resetAnimations()
            panel.setFrame(rect, display: true)
            panel.alphaValue = shouldAnimate ? 0 : 1
            panel.orderFrontRegardless()
            if shouldAnimate {
                optionViews[group]?.animateAppearance()
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = shouldAnimate ? 0.14 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            optionPanels.values.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private static func makePanel(group: WindowSnapGroup) -> NSPanel {
        let panel = WindowSnapPassivePanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("Jarvis.WindowSnapOption.\(group.rawValue)")
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private final class WindowSnapPassivePanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
