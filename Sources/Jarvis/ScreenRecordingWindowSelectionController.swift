import AppKit

/// Uses screenshot selection's front-to-back window detection and coordinate mapping.
@MainActor
final class ScreenRecordingWindowSelectionController {
    private var panels: [NSPanel] = []
    private var completion: ((CGWindowID?) -> Void)?

    func select(windowIDs: Set<CGWindowID>, completion: @escaping (CGWindowID?) -> Void) {
        finish(nil)
        self.completion = completion
        // Read every display's candidates before any full-screen overlay is shown.
        let screens = NSScreen.screens.map { screen in
            (screen, WindowSelectionDetector.candidates(for: screen.frame).filter { windowIDs.contains($0.windowID) })
        }
        for (screen, candidates) in screens {
            let panel = ScreenRecordingSelectionPanel(
                contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
            )
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            let canvas = ScreenRecordingWindowSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size), candidates: candidates
            )
            canvas.onSelect = { [weak self] id in self?.finish(id) }
            panel.contentView = canvas
            panels.append(panel)
            panel.orderFrontRegardless()
            if NSMouseInRect(NSEvent.mouseLocation, screen.frame, false) {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(canvas)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ id: CGWindowID?) {
        let callback = completion
        completion = nil
        for panel in panels {
            panel.orderOut(nil); panel.close()
        }
        panels.removeAll()
        callback?(id)
    }
}

@MainActor
private final class ScreenRecordingWindowSelectionView: NSView {
    let candidates: [WindowSelectionCandidate]
    var onSelect: ((CGWindowID?) -> Void)?
    private var hovered: WindowSelectionCandidate?
    private var tracking: NSTrackingArea?

    init(frame: CGRect, candidates: [WindowSelectionCandidate]) {
        self.candidates = candidates
        super.init(frame: frame)
        setAccessibilityLabel("选择录制窗口：移动鼠标高亮，点击选择，Esc 取消")
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHover()
    }

    private func updateHover() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        hovered = candidates.first { $0.localRect.contains(point) }
        needsDisplay = true
    }

    override func mouseEntered(with _: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        updateHover()
    }

    override func mouseExited(with _: NSEvent) {
        hovered = nil; needsDisplay = true
    }

    override func mouseMoved(with _: NSEvent) {
        updateHover()
    }

    override func mouseDown(with _: NSEvent) {
        updateHover()
        if let hovered {
            onSelect?(hovered.windowID)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == JarvisKeyCode.escape {
            onSelect?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if let hovered {
            shade.append(NSBezierPath(rect: hovered.localRect))
        }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill()
        shade.fill()
        if let hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(rect: hovered.localRect).fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: hovered.localRect.insetBy(dx: 1.5, dy: 1.5))
            outline.lineWidth = 3
            outline.stroke()
        }
        let text = hovered.map { "\($0.ownerName) · \($0.title) · 点击选择窗口 · Esc 取消" }
            ?? "移动鼠标选择录制窗口 · 点击确认 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14, weight: .medium)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: max(12, (bounds.width - size.width) / 2), y: bounds.height - 60), withAttributes: attributes)
    }
}
