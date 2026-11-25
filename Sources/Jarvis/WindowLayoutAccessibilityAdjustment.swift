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
