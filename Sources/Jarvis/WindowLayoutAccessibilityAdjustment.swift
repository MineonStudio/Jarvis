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
            // AX keeps the top-left corner and grows right and down. Start on
            // the target's top-left so that growth stays inside the screen.
            // Centering a half layout first makes one edge hit the screen, and
            // the clamped size then leaves gaps on both sides of that axis.
            // A window whose current height would hang through the Dock is
            // lifted above it; apps ignore a resize while that overlap remains.
            if let currentSize = readSize(), currentSize.width > 0, currentSize.height > 0 {
                _ = setPosition(Self.parkedFrame(currentSize, beforeResizingInto: requestedFrame, in: visibleFrame))
            } else {
                _ = setPosition(requestedFrame)
            }
            resized = setSize(requestedFrame.size)
            if let actual = readSize(), !Self.matches(actual, requestedFrame.size) {
                resized = setSize(requestedFrame.size) || resized
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
        if top - currentSize.height < visibleFrame.minY {
            top = visibleFrame.minY + currentSize.height
        }
        return CGRect(x: x, y: top - currentSize.height, width: currentSize.width, height: currentSize.height)
    }

    private static func matches(_ actual: CGSize, _ requested: CGSize) -> Bool {
        abs(actual.width - requested.width) <= 1 && abs(actual.height - requested.height) <= 1
    }
}
