import AppKit
import ImageIO

/// Both a reused selection panel and a new editing panel route color picking
/// through the same path, without intercepting events outside screenshot UI.
class ScreenshotColorProbePanel: NSPanel {
    var colorProbeCanvas: ScreenshotCanvasHostingView? {
        (contentView as? ScreenshotEditingSurface)?.canvas as? ScreenshotCanvasHostingView
            ?? contentView as? ScreenshotCanvasHostingView
    }

    var isPickingColor: Bool {
        colorProbeCanvas?.isPickingColor == true
    }

    func isCanvasEvent(_ event: NSEvent) -> Bool {
        guard let surface = contentView as? ScreenshotEditingSurface else { return true }
        let point = event.type == .keyDown ? mouseLocationOutsideOfEventStream : event.locationInWindow
        return surface.isCanvasLocation(point)
    }

    override func sendEvent(_ event: NSEvent) {
        let canvas = colorProbeCanvas
        if isCanvasEvent(event) {
            if canvas?.handleColorProbeEvent(event) == true {
                return
            }
        } else {
            canvas?.hideColorProbe()
        }
        super.sendEvent(event)
    }
}

@MainActor
final class ScreenshotColorProbe {
    private var sampler: ScreenshotColorSampler?
    private let preparation: Task<ScreenshotColorSampler?, Never>
    private let pasteboard: NSPasteboard
    private var hoverUpdate: Task<Void, Never>?
    private let badge = ScreenshotColorBadge(frame: .zero)
    private var copiedAt: CGPoint?
    private struct PendingCopy {
        weak var view: NSView?
        weak var editor: ScreenshotEditorModel?
        let point: CGPoint
        let canvasSize: CGSize
    }

    private var pendingCopy: PendingCopy?

    init(data: Data, pasteboard: NSPasteboard = .general, onReady: @escaping @MainActor () -> Void = {}) {
        self.pasteboard = pasteboard
        // Large PNG decoding and color conversion must not block mouse events.
        let preparation = Task.detached(priority: .userInitiated) { () -> ScreenshotColorSampler? in
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  !Task.isCancelled else { return nil }
            return ScreenshotColorSampler(image: image)
        }
        self.preparation = preparation
        badge.isHidden = true
        Task { [weak self] in
            let sampler = await preparation.value
            guard let self, !preparation.isCancelled else { return }
            self.sampler = sampler
            if let pending = pendingCopy,
               pending.view?.window != nil, pending.editor?.selectedTool == .eyedropper,
               let sample = sampler?.sample(at: pending.point, canvasSize: pending.canvasSize)
            {
                copySample(sample, at: pending.point)
            }
            pendingCopy = nil
            onReady()
        }
    }

    deinit {
        preparation.cancel()
        hoverUpdate?.cancel()
    }

    func scheduleUpdate(in view: NSView, editor: ScreenshotEditorModel, scale: CGFloat) {
        guard hoverUpdate == nil else { return }
        let framesPerSecond = max(60, view.window?.screen?.maximumFramesPerSecond ?? 60)
        let delay = UInt64(1_000_000_000 / framesPerSecond)
        // Coalesce high-polling-rate mouse events and sample the latest position
        // once per display frame instead of queuing stale glass/layout updates.
        hoverUpdate = Task { [weak self, weak view, weak editor] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self else { return }
            hoverUpdate = nil
            guard let view, let editor else { return }
            update(in: view, editor: editor, scale: scale)
        }
    }

    func hide() {
        hoverUpdate?.cancel()
        hoverUpdate = nil
        pendingCopy = nil
        badge.isHidden = true
    }

    @discardableResult
    private func copySample(_ sample: ScreenshotColorSample, at point: CGPoint) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setString(sample.hex, forType: .string) else { return false }
        copiedAt = point
        return true
    }

    @discardableResult
    func update(
        in view: NSView, editor: ScreenshotEditorModel, scale: CGFloat,
        copy: Bool = false, locationInWindow: CGPoint? = nil
    ) -> Bool {
        hoverUpdate?.cancel()
        hoverUpdate = nil
        guard let window = view.window, let overlayHost = view.superview,
              window.contentView !== view, scale > 0,
              editor.selectedTool == .eyedropper, editor.textInputAnchor == nil,
              !(window.firstResponder is NSTextView), let selection = editor.selectionRect
        else { hide(); return false }
        let location = locationInWindow ?? window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = view.convert(location, from: nil)
        let point = CGPoint(x: local.x / scale, y: local.y / scale)
        guard selection.contains(point), view.bounds.contains(local)
        else { hide(); return false }
        guard let sampler else {
            // A fast click/C during preparation still copies the requested pixel.
            if copy {
                pendingCopy = PendingCopy(view: view, editor: editor, point: point, canvasSize: editor.canvasSize)
            }
            return copy
        }
        guard let sample = sampler.sample(at: point, canvasSize: editor.canvasSize)
        else { hide(); return false }
        if copy {
            pendingCopy = nil
            guard copySample(sample, at: point) else { return false }
        } else if copiedAt != point {
            copiedAt = nil
        }
        presentBadge(sample, at: point, local: local, in: view, overlayHost: overlayHost)
        return true
    }

    private func presentBadge(
        _ sample: ScreenshotColorSample, at point: CGPoint, local: CGPoint,
        in view: NSView, overlayHost: NSView
    ) {
        if badge.superview !== overlayHost {
            overlayHost.addSubview(badge, positioned: .above, relativeTo: view)
        }
        badge.sample = sample
        badge.copied = copiedAt == point
        var origin = CGPoint(x: local.x + 18, y: local.y + 22)
        if origin.x + badge.frame.width > view.bounds.maxX {
            origin.x = local.x - badge.frame.width - 18
        }
        if origin.y + badge.frame.height > view.bounds.maxY {
            origin.y = local.y - badge.frame.height - 18
        }
        origin.x = max(view.bounds.minX, origin.x)
        origin.y = max(view.bounds.minY, origin.y)
        let frame = overlayHost.convert(CGRect(origin: origin, size: badge.frame.size), from: view)
        if badge.frame != frame {
            badge.frame = frame
        }
        if badge.isHidden {
            badge.isHidden = false
        }
    }
}

private final class ScreenshotColorBadge: NSView {
    private let glass = NSGlassEffectView(frame: .zero)
    private let swatch = NSView(frame: .zero)
    private let valueLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    var sample: ScreenshotColorSample? {
        didSet {
            guard sample != oldValue else { return }
            valueLabel.stringValue = sample?.hex ?? ""
            swatch.layer?.backgroundColor = sample?.color.cgColor
            setAccessibilityLabel(sample.map { "色值 \($0.hex)，按 C 复制" })
        }
    }

    var copied = false {
        didSet {
            if copied != oldValue {
                updateHint()
            }
        }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Moving a layer-backed overlay does not invalidate the screenshot
        // canvas underneath it. Keep native glass backdrop sampling intact.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        let panelHeight: CGFloat = 28
        valueLabel.stringValue = "#FFFFFF"
        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.sizeToFit()
        valueLabel.setFrameOrigin(CGPoint(x: 28, y: (panelHeight - valueLabel.frame.height) / 2))
        let panelWidth = valueLabel.frame.maxX + 8
        glass.frame = CGRect(x: 4, y: 4, width: panelWidth, height: panelHeight)
        glass.cornerRadius = 9
        glass.style = .regular
        let content = NSView(frame: CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        swatch.frame = CGRect(x: 8, y: 7, width: 14, height: 14)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 4
        swatch.layer?.borderWidth = 0.5
        swatch.layer?.borderColor = NSColor.gray.withAlphaComponent(0.4).cgColor
        content.addSubview(swatch)
        content.addSubview(valueLabel)
        glass.contentView = content
        addSubview(glass)

        // Center the background-free caption directly below the compact glass.
        hintLabel.stringValue = "按 C 复制"
        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        // Reserve the full panel width rather than measuring the plain string:
        // the attributed caption's font fallback and shadow need extra room.
        hintLabel.frame = CGRect(x: glass.frame.minX, y: glass.frame.maxY + 6, width: panelWidth, height: 20)
        hintLabel.maximumNumberOfLines = 1
        hintLabel.lineBreakMode = .byClipping
        hintLabel.alignment = .center
        addSubview(hintLabel)
        setFrameSize(CGSize(width: panelWidth + 8, height: hintLabel.frame.maxY + 4))
        updateHint()
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func updateHint() {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        hintLabel.attributedStringValue = NSAttributedString(
            string: copied ? "已复制" : "按 C 复制",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
                .shadow: shadow
            ]
        )
    }
}
