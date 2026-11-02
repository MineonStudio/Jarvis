import AppKit
import Observation
import SwiftUI

/// Toolbar items live in a separate hosting hierarchy. Convert their actual
/// bounds into window coordinates instead of assuming symmetric content insets.
@MainActor
@Observable
final class HistoryToolbarAlignment {
    enum Edge { case leading, trailing, content }

    private(set) var leadingInset = JarvisMetrics.shellHorizontalPadding
    private(set) var trailingInset = JarvisMetrics.shellHorizontalPadding
    @ObservationIgnored private weak var leadingView: NSView?
    @ObservationIgnored private weak var trailingView: NSView?
    @ObservationIgnored private weak var contentView: NSView?
    @ObservationIgnored private var measurementScheduled = false

    func attach(_ view: NSView, at edge: Edge) {
        switch edge {
        case .leading: leadingView = view
        case .trailing: trailingView = view
        case .content: contentView = view
        }
        guard !measurementScheduled else { return }
        measurementScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            measurementScheduled = false
            measure()
        }
    }

    private func measure() {
        guard let contentView, let window = contentView.window,
              let leadingView, leadingView.window === window,
              let trailingView, trailingView.window === window else { return }
        let content = contentView.convert(contentView.bounds, to: nil)
        let leading = leadingView.convert(leadingView.bounds, to: nil)
        let trailing = trailingView.convert(trailingView.bounds, to: nil)
        guard content.width > 0, leading.width > 0, trailing.width > 0 else { return }
        let nextLeading = max(0, leading.minX - content.minX)
        let nextTrailing = max(0, content.maxX - trailing.maxX)
        // Ignore subpixel layout noise so measuring never feeds a redraw loop.
        let tolerance = 0.5 / window.backingScaleFactor
        if abs(leadingInset - nextLeading) > tolerance {
            leadingInset = nextLeading
        }
        if abs(trailingInset - nextTrailing) > tolerance {
            trailingInset = nextTrailing
        }
    }
}

struct HistoryToolbarFrameProbe: NSViewRepresentable {
    let alignment: HistoryToolbarAlignment
    let edge: HistoryToolbarAlignment.Edge

    func makeNSView(context _: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ view: ProbeView, context _: Context) {
        view.onLayout = { [weak alignment] view in alignment?.attach(view, at: edge) }
        view.onLayout?(view)
    }

    final class ProbeView: NSView {
        var onLayout: ((NSView) -> Void)?

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onLayout?(self)
        }

        override func layout() {
            super.layout()
            onLayout?(self)
        }
    }
}
