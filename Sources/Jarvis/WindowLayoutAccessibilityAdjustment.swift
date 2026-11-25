import AppKit

/// AX success acknowledges a request; applications can still enforce a minimum size.
@MainActor
struct WindowLayoutAccessibilityAdjustment {
    enum Result {
        case applied, constrained, failed
    }

    let readSize: () -> CGSize?
    let setSize: (CGSize) -> Bool
    let setPosition: (CGRect) -> Bool

    func apply(
        _ placement: WindowSnapPlacement,
        in visibleFrame: CGRect,
        supportsResizing: Bool
    ) -> Result {
        let requestedFrame = placement.frame(in: visibleFrame)
        var resized = false
        if supportsResizing {
            // AX keeps the top-left corner and grows right and down. Park on
            // the target's top-left so that growth stays inside the screen.
            // A move that does not land must not be followed by a resize:
            // growing from the old origin stops at the screen edge, and the
            // short size is then centered on a half layout.
            resized = resize(to: requestedFrame, in: visibleFrame)
            if let actual = readSize(), !Self.matches(actual, requestedFrame.size) {
                // The first growth may have been clamped. Park the size we
                // have now, which can sit on the target corner, and try once more.
                resized = resize(to: requestedFrame, in: visibleFrame) || resized
            }
            // A text row can come back a few points too tall. The window server
            // will not leave that surplus under the Dock, so it would cover the
            // neighbor. Ask for a shorter size until the snap fits.
            pullInside(requestedFrame, in: visibleFrame)
        }
        guard let actualSize = readSize(), actualSize.width > 0, actualSize.height > 0 else {
            return .failed
        }

        // AX positions use the top-left corner. Reusing the requested top-left
        // with a taller actual size would push a lower layout into the Dock.
        let actualFrame = placement.frame(preserving: actualSize, in: visibleFrame)
        guard setPosition(actualFrame) else { return .failed }
        let matchesSize = Self.matches(actualSize, requestedFrame.size)
        return resized && matchesSize ? .applied : .constrained
    }

    /// Shrinks an app that snapped larger than `requested` until it fits, or until
    /// the size stops changing. Each miss steps further down so a round-up grid
    /// can fall into the previous cell.
    private func pullInside(_ requested: CGRect, in visibleFrame: CGRect) {
        var step = CGSize.zero
        var stuck = 0
        for _ in 0..<4 {
            guard let actual = readSize() else { return }
            let extra = CGSize(width: actual.width - requested.width, height: actual.height - requested.height)
            if Self.fits(actual, inside: requested.size) { return }
            let ask = Self.nextSmallerSize(requested.size, extra: extra, step: &step, stuck: &stuck)
            guard let ask else { return }
            let frame = CGRect(
                x: requested.minX,
                y: requested.maxY - ask.height,
                width: ask.width,
                height: ask.height
            )
            guard resize(to: frame, in: visibleFrame), let next = readSize() else { return }
            let moved = abs(next.width - actual.width) > 1 || abs(next.height - actual.height) > 1
            if moved {
                stuck = 0
                step = .zero
            }
        }
    }

    private static func fits(_ actual: CGSize, inside requested: CGSize) -> Bool {
        actual.width <= requested.width + 1 && actual.height <= requested.height + 1
    }

    private static func nextSmallerSize(
        _ requested: CGSize, extra: CGSize, step: inout CGSize, stuck: inout Int
    ) -> CGSize? {
        if step == .zero {
            step = CGSize(width: max(extra.width, 0), height: max(extra.height, 0))
        } else {
            stuck += 1
            if stuck == 3 { return nil }
            step = CGSize(width: step.width * 2, height: step.height * 2)
        }
        let ask = CGSize(
            width: requested.width - (extra.width > 1 ? step.width : 0),
            height: requested.height - (extra.height > 1 ? step.height : 0)
        )
        guard ask.width > 1, ask.height > 1 else { return nil }
        return ask
    }

    /// Parks, then requests `requested.size`. Returns whether the resize was accepted.
    /// A failed park skips the resize so the window is not grown from the wrong origin.
    private func resize(to requested: CGRect, in visibleFrame: CGRect) -> Bool {
        guard park(beforeResizingInto: requested, in: visibleFrame) else { return false }
        return setSize(requested.size)
    }

    private func park(beforeResizingInto requested: CGRect, in visibleFrame: CGRect) -> Bool {
        if let currentSize = readSize(), currentSize.width > 0, currentSize.height > 0 {
            return setPosition(Self.parkedFrame(currentSize, beforeResizingInto: requested, in: visibleFrame))
        }
        return setPosition(requested)
    }

    /// Position that keeps the current size on screen while leaving room to grow
    /// into `requested`. The returned rect still has the current size.
    private static func parkedFrame(
        _ currentSize: CGSize,
        beforeResizingInto requested: CGRect,
        in visibleFrame: CGRect
    ) -> CGRect {
        var x = requested.minX
        if x + currentSize.width > visibleFrame.maxX {
            x = visibleFrame.maxX - currentSize.width
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        var top = requested.maxY
        // A window taller than the screen is lifted so its bottom stays above
        // the Dock. Apps ignore a resize while that overlap remains.
        if top - currentSize.height < visibleFrame.minY {
            top = visibleFrame.minY + currentSize.height
        }
        return CGRect(x: x, y: top - currentSize.height, width: currentSize.width, height: currentSize.height)
    }

    private static func matches(_ actual: CGSize, _ requested: CGSize) -> Bool {
        abs(actual.width - requested.width) <= 1 && abs(actual.height - requested.height) <= 1
    }
}
