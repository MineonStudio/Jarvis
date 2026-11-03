import AppKit
import SwiftUI

/// Three passive panels keep fixed frames while their layout blocks highlight.
@MainActor
final class WindowSnapOptionView: NSView {
    private let surface: WindowSnapSurfaceView
    private(set) var selectedPlacement: WindowSnapPlacement?

    init(group: WindowSnapGroup, frame: NSRect) {
        surface = WindowSnapSurfaceView(group: group)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(surface)
        setAccessibilityElement(false)
        surface.frame = WindowSnapBarGeometry.surfaceRect(in: bounds)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        surface.frame = WindowSnapBarGeometry.surfaceRect(in: bounds)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    func setSelection(_ placement: WindowSnapPlacement?, animated: Bool) {
        guard placement != selectedPlacement else { return }
        selectedPlacement = placement
        surface.setSelection(placement, animated: animated)
    }

    func animateAppearance() {
        guard let layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 5
        animation.toValue = 0
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "windowSnap.appear")
    }

    func resetAnimations() {
        layer?.removeAllAnimations()
        setSelection(nil, animated: false)
    }
}

@MainActor
private final class WindowSnapSurfaceView: NSView {
    private let material = NSHostingView(rootView: WindowSnapGlassSurface())
    private var blocks: [WindowSnapPlacement: WindowSnapBlockView] = [:]

    init(group: WindowSnapGroup) {
        super.init(frame: .zero)
        wantsLayer = true
        material.sizingOptions = []
        material.setAccessibilityElement(false)
        addSubview(material)
        for placement in group.placements {
            let block = WindowSnapBlockView(frame: .zero)
            blocks[placement] = block
            addSubview(block)
        }
        setAccessibilityElement(false)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let panel = bounds
        let overflow = ScreenRecordingToolbarLayout.glassOverflow
        material.frame = panel.insetBy(dx: -overflow, dy: -overflow)
        for (placement, block) in blocks {
            block.frame = WindowSnapBarGeometry.blockRect(for: placement, in: panel)
        }
    }

    func setSelection(_ placement: WindowSnapPlacement?, animated: Bool) {
        for (item, block) in blocks {
            block.setSelected(item == placement, animated: animated)
        }
    }
}

@MainActor
private final class WindowSnapBlockView: NSView {
    private let accent = WindowSnapAccentView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        accent.alphaValue = 0
        accent.autoresizingMask = [.width, .height]
        addSubview(accent)
        setAccessibilityElement(false)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        accent.frame = bounds
    }

    override func draw(_: NSRect) {
        JarvisMotion.hoverPillNSColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.1 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            accent.animator().alphaValue = selected ? 1 : 0
        }
    }
}

@MainActor
private final class WindowSnapAccentView: NSView {
    override func draw(_: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
}

@MainActor
private struct WindowSnapGlassSurface: View {
    var body: some View {
        GlassEffectContainer {
            Color.clear
                .captureToolbarGlassSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(ScreenRecordingToolbarLayout.glassOverflow)
        // Active glass appearance without taking key focus from the target.
        #if compiler(>=6.4)
            .environment(\.appearsActive, true)
        #else
            .environment(\.controlActiveState, .key)
        #endif
            .materialActiveAppearance(.active)
    }
}
