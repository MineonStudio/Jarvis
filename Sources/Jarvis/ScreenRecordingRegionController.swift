import AppKit

@MainActor
final class ScreenRecordingRegionController {
    private var window: ScreenRecordingSelectionPanel?
    private var completion: ((CGRect?) -> Void)?

    func select(on screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        cancel()
        self.completion = completion
        let panel = ScreenRecordingSelectionPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let canvas = ScreenRecordingRegionCanvas(frame: CGRect(origin: .zero, size: screen.frame.size))
        canvas.onFinish = { [weak self] rect in self?.finish(rect) }
        panel.contentView = canvas
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(canvas)
        window = panel
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ rect: CGRect?) {
        let callback = completion
        completion = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        callback?(rect)
    }
}

final class ScreenRecordingSelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
private final class ScreenRecordingRegionCanvas: NSView {
    var selection = CGRect.zero {
        didSet { needsDisplay = true }
    }

    var onFinish: ((CGRect?) -> Void)?
    private var anchor = CGPoint.zero
    private var original = CGRect.zero
    private var dragMode = -2 // -2 new selection, -1 move, 0...7 resize handles
    override var acceptsFirstResponder: Bool {
        true
    }

    private var handles: [CGPoint] {
        [
            CGPoint(x: selection.minX, y: selection.minY),
            CGPoint(x: selection.midX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.midY),
            CGPoint(x: selection.maxX, y: selection.maxY),
            CGPoint(x: selection.midX, y: selection.maxY),
            CGPoint(x: selection.minX, y: selection.maxY),
            CGPoint(x: selection.minX, y: selection.midY)
        ]
    }

    override func draw(_: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if selection.width > 0 {
            shade.append(NSBezierPath(rect: selection))
        }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        shade.fill()
        if selection.width > 0 {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 2
            outline.stroke()
            NSColor.white.setFill()
            for point in handles {
                NSBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
            }
        }
        let scale = window?.screen?.backingScaleFactor ?? 1
        let text = selection.width >= 24
            ? "\(Int(selection.width * scale)) × \(Int(selection.height * scale)) 像素 · 松开鼠标确认"
            : "拖拽选择录制区域 · 按住 Shift 保持 16:9 · 松开鼠标确认 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 16, weight: .medium)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: max(12, (bounds.width - size.width) / 2), y: bounds.height - 60),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        anchor = convert(event.locationInWindow, from: nil)
        original = selection
        dragMode = handles.firstIndex { hypot($0.x - anchor.x, $0.y - anchor.y) < 12 }
            ?? (selection.contains(anchor) ? -1 : -2)
    }

    override func mouseDragged(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        point.x = min(max(0, point.x), bounds.width)
        point.y = min(max(0, point.y), bounds.height)
        if dragMode == -1 {
            var moved = original.offsetBy(dx: point.x - anchor.x, dy: point.y - anchor.y)
            moved.origin.x = min(max(0, moved.minX), bounds.width - moved.width)
            moved.origin.y = min(max(0, moved.minY), bounds.height - moved.height)
            selection = moved
        } else if dragMode >= 0 {
            var x1 = original.minX, x2 = original.maxX, y1 = original.minY, y2 = original.maxY
            if [0, 6, 7].contains(dragMode) {
                x1 = point.x
            }
            if [2, 3, 4].contains(dragMode) {
                x2 = point.x
            }
            if [0, 1, 2].contains(dragMode) {
                y1 = point.y
            }
            if [4, 5, 6].contains(dragMode) {
                y2 = point.y
            }
            selection = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        } else {
            var width = abs(point.x - anchor.x), height = abs(point.y - anchor.y)
            if event.modifierFlags.contains(.shift) {
                width = min(width, height * 16 / 9)
                height = width * 9 / 16
            }
            selection = CGRect(
                x: point.x < anchor.x ? anchor.x - width : anchor.x,
                y: point.y < anchor.y ? anchor.y - height : anchor.y,
                width: width,
                height: height
            )
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == JarvisKeyCode.escape {
            cancelSelection()
        } else if event.keyCode == JarvisKeyCode.returnKey {
            confirmSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseUp(with _: NSEvent) {
        confirmSelection()
    }

    @objc private func confirmSelection() {
        guard let rect = ScreenRecordingGeometry.validRegion(selection, in: bounds) else { NSSound.beep(); return }
        onFinish?(rect)
    }

    @objc private func cancelSelection() {
        onFinish?(nil)
    }
}
