import AppKit
import ImageIO

/// Both a reused selection panel and a new editing panel route hover and C
/// through the same path, without intercepting events outside screenshot UI.
class ScreenshotColorProbePanel: NSPanel {
    func isCanvasEvent(_ event: NSEvent) -> Bool {
        guard let surface = contentView as? ScreenshotEditingSurface else { return true }
        let point = event.type == .keyDown ? mouseLocationOutsideOfEventStream : event.locationInWindow
        return surface.isCanvasLocation(point)
    }

    override func sendEvent(_ event: NSEvent) {
        let canvas = (contentView as? ScreenshotEditingSurface)?.canvas as? ScreenshotCanvasHostingView
            ?? contentView as? ScreenshotCanvasHostingView
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

/// Samples the frozen image in top-left canvas coordinates, independently of
/// the selection dimming, annotations and the display's Retina scale.
struct ScreenshotColorSample: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var color: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

struct ScreenshotColorSampler {
    let image: CGImage

    func sample(at point: CGPoint, canvasSize: CGSize) -> ScreenshotColorSample? {
        guard canvasSize.width > 0, canvasSize.height > 0,
              point.x.isFinite, point.y.isFinite,
              CGRect(origin: .zero, size: canvasSize).contains(point)
        else { return nil }
        let x = min(image.width - 1, Int(point.x / canvasSize.width * CGFloat(image.width)))
        let y = min(image.height - 1, Int(point.y / canvasSize.height * CGFloat(image.height)))
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }
        return ScreenshotColorSample(red: rgba[0], green: rgba[1], blue: rgba[2])
    }
}

@MainActor
final class ScreenshotColorProbe {
    private let sampler: ScreenshotColorSampler?
    private let badge = ScreenshotColorBadge(frame: .zero)
    private var copiedAt: CGPoint?

    init(data: Data) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        sampler = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            .map { ScreenshotColorSampler(image: $0) }
        badge.isHidden = true
    }

    func hide() {
        badge.isHidden = true
    }

    @discardableResult
    func update(in view: NSView, editor: ScreenshotEditorModel, scale: CGFloat, copy: Bool = false) -> Bool {
        guard let window = view.window, let overlayHost = view.superview,
              window.contentView !== view, scale > 0, editor.textInputAnchor == nil,
              !(window.firstResponder is NSTextView), let selection = editor.selectionRect
        else { hide(); return false }
        let local = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let point = CGPoint(x: local.x / scale, y: local.y / scale)
        guard selection.contains(point), view.bounds.contains(local),
              let sample = sampler?.sample(at: point, canvasSize: editor.canvasSize)
        else { hide(); return false }
        if copy {
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(sample.hex, forType: .string) else { return false }
            copiedAt = point
        } else if copiedAt != point {
            copiedAt = nil
        }
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
        badge.frame = overlayHost.convert(CGRect(origin: origin, size: badge.frame.size), from: view)
        badge.isHidden = false
        return true
    }
}

private final class ScreenshotColorBadge: NSView {
    private let glass = NSGlassEffectView(frame: .zero)
    private let swatch = NSView(frame: .zero)
    private let valueLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    var sample: ScreenshotColorSample? {
        didSet {
            valueLabel.stringValue = sample?.hex ?? ""
            swatch.layer?.backgroundColor = sample?.color.cgColor
            setAccessibilityLabel(sample.map { "色值 \($0.hex)，按 C 复制" })
        }
    }

    var copied = false {
        didSet { updateHint() }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Only the swatch has a backing layer. The system glass samples the
        // screenshot beneath it, without an opaque custom background.
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
