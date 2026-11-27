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
            // A real minimum can be much larger than the tile and has to move
            // inside the screen. A character row is only a few points off, and
            // shrinking it drops the whole row.
            if let actual = readSize(), !Self.characterGrid(actual, requestedFrame.size) {
                pullInside(requestedFrame, in: visibleFrame)
            }
        }
        guard let actualSize = readSize(), actualSize.width > 0, actualSize.height > 0 else {
            return .failed
        }

        // A character row keeps the requested top-left, the same sequence the
        // first layout used. The extra points extend down from that top.
        // Anything further off is placed by its real size so a tall minimum
        // stays above the Dock.
        let actualFrame = Self.characterGrid(actualSize, requestedFrame.size)
            ? requestedFrame
            : placement.frame(preserving: actualSize, in: visibleFrame)
        guard setPosition(actualFrame) else { return .failed }
        let matchesSize = Self.matches(actualSize, requestedFrame.size)
        let keptGrid = Self.characterGrid(actualSize, requestedFrame.size)
        return resized && (matchesSize || keptGrid) ? .applied : .constrained
    }

    /// Terminal's height lands on a character row, about 15pt. The nearest row
    /// can be a little taller or shorter than the tile. That is the size to keep.
    private static func characterGrid(_ actual: CGSize, _ requested: CGSize) -> Bool {
        let widthGap = abs(actual.width - requested.width)
        let heightGap = abs(actual.height - requested.height)
        let largest = max(widthGap, heightGap)
        return largest > 1 && largest <= 16
    }

    /// Shrinks an app that snapped larger than `requested` until it fits.
    /// Width and height search separately: a column change must not ask a
    /// fitted row to grow back, or the window covers its neighbor again.
    private func pullInside(_ requested: CGRect, in visibleFrame: CGRect) {
        var width = AxisSearch()
        var height = AxisSearch()
        for _ in 0 ..< 6 {
            guard let actual = readSize() else { return }
            width.observe(actual.width)
            height.observe(actual.height)
            if Self.fits(actual, inside: requested.size) {
                return
            }
            let ask = CGSize(
                width: width.propose(requested: requested.width, actual: actual.width),
                height: height.propose(requested: requested.height, actual: actual.height)
            )
            if Self.matches(ask, actual) {
                return
            }
            let frame = CGRect(
                x: requested.minX,
                y: requested.maxY - ask.height,
                width: ask.width,
                height: ask.height
            )
            guard resize(to: frame, in: visibleFrame), let next = readSize() else { return }
            width.noteMove(from: actual.width, to: next.width)
            height.noteMove(from: actual.height, to: next.height)
        }
    }

    private struct AxisSearch {
        var step: CGFloat = 0
        var misses = 0
        var smallest: CGFloat = .greatestFiniteMagnitude
        var gaveUp = false

        mutating func observe(_ actual: CGFloat) {
            smallest = min(smallest, actual)
        }

        mutating func propose(requested: CGFloat, actual: CGFloat) -> CGFloat {
            let extra = actual - requested
            guard !gaveUp, extra > 1 else { return smallest }
            if step == 0 {
                step = extra
            } else {
                misses += 1
                guard misses < 6 else {
                    gaveUp = true
                    return smallest
                }
                step *= 2
            }
            let ask = requested - step
            guard ask > 1 else {
                gaveUp = true
                return smallest
            }
            return min(ask, smallest)
        }

        mutating func noteMove(from previous: CGFloat, to next: CGFloat) {
            guard abs(next - previous) > 1 else { return }
            misses = 0
            step = 0
        }
    }

    private static func fits(_ actual: CGSize, inside requested: CGSize) -> Bool {
        actual.width <= requested.width + 1 && actual.height <= requested.height + 1
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
