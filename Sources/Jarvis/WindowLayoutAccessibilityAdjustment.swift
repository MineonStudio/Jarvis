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
            // Move onto the destination display before resizing, but keep the
            // current window inside the visible frame. Placing a still-tall
            // window on a lower quadrant's top edge drops its bottom through
            // the Dock; the screen clamps that height, and apps then ignore
            // the resize. Anchoring the clamped height above the Dock makes
            // the lower window overlap the upper one by about the Dock height.
            if let currentSize = readSize(), currentSize.width > 0, currentSize.height > 0 {
                _ = setPosition(placement.frame(preserving: currentSize, in: visibleFrame))
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

    private static func matches(_ actual: CGSize, _ requested: CGSize) -> Bool {
        abs(actual.width - requested.width) <= 1 && abs(actual.height - requested.height) <= 1
    }
}
