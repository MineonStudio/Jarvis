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
            // Moving first lets applications resize within the destination display.
            _ = setPosition(requestedFrame)
            resized = setSize(requestedFrame.size)
        }
        guard let actualSize = readSize(), actualSize.width > 0, actualSize.height > 0 else {
            return .failed
        }

        // AX positions use the top-left corner. Reusing the requested top-left
        // with a taller actual size would push a lower layout into the Dock.
        let actualFrame = placement.frame(preserving: actualSize, in: visibleFrame)
        guard setPosition(actualFrame) else { return .failed }
        let matchesSize = abs(actualSize.width - requestedFrame.width) <= 1
            && abs(actualSize.height - requestedFrame.height) <= 1
        return resized && matchesSize ? .applied : .constrained
    }
}
