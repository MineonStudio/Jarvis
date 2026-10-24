import AppKit
import ObjectiveC

/// SwiftUI animates `setFrame` to the content minimum a few seconds after
/// launch, and that animation also slides the window about a screen away.
/// Replacing the frame before AppKit starts the animation keeps it put.
/// `setContentSize` is included because the shrink keeps the top-left corner.
enum JarvisLaunchFrameBlock {
    nonisolated(unsafe) weak static var window: NSWindow?
    nonisolated(unsafe) static var frame: NSRect?
    nonisolated(unsafe) static var isApplyingPinnedFrame = false
    nonisolated(unsafe) static var isUserMoving = false

    static let install: Void = {
        exchange(
            #selector(NSWindow.setFrame(_:display:animate:)),
            #selector(NSWindow.jarvis_setFrame(_:display:animate:))
        )
        exchange(
            #selector(NSWindow.setFrameOrigin(_:)),
            #selector(NSWindow.jarvis_setFrameOrigin(_:))
        )
        exchange(
            #selector(NSWindow.setContentSize(_:)),
            #selector(NSWindow.jarvis_setContentSize(_:))
        )
        exchange(
            NSSelectorFromString("_reallySetFrame:"),
            #selector(NSWindow.jarvis_reallySetFrame(_:))
        )
        exchange(
            NSSelectorFromString("_setFrame:"),
            #selector(NSWindow.jarvis_setFrameIgnoringPublicAPI(_:))
        )
        exchange(
            NSSelectorFromString("_setFrame:display:allowImplicitAnimation:stashSize:"),
            #selector(NSWindow.jarvis_setFrameAllowingImplicitAnimation(_:display:allowImplicitAnimation:stashSize:))
        )
        exchange(
            NSSelectorFromString("_setFrame:fromAdjustmentToScreen:animate:"),
            #selector(NSWindow.jarvis_setFrameForScreenAdjustment(_:screen:animate:))
        )
        exchange(
            #selector(NSWindow.setFrameTopLeftPoint(_:)),
            #selector(NSWindow.jarvis_setFrameTopLeftPoint(_:))
        )
        exchange(
            NSSelectorFromString("_setFrameCommon:display:stashSize:"),
            #selector(NSWindow.jarvis_setFrameCommon(_:display:stashSize:))
        )
        exchange(
            NSSelectorFromString("_setFrameCommon:display:fromServer:"),
            #selector(NSWindow.jarvis_setFrameCommonFromServer(_:display:fromServer:))
        )
    }()

    static func performPinned(_ body: () -> Void) {
        let previous = isApplyingPinnedFrame
        isApplyingPinnedFrame = true
        defer { isApplyingPinnedFrame = previous }
        body()
    }

    private static func exchange(_ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(NSWindow.self, original),
              let replacementMethod = class_getInstanceMethod(NSWindow.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

private extension NSWindow {
    @objc func jarvis_setFrame(_ frame: NSRect, display: Bool, animate: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrame(pinned, display: display, animate: false)
            }
            return
        }
        jarvis_setFrame(frame, display: display, animate: animate)
    }

    @objc func jarvis_setFrameOrigin(_ point: NSPoint) {
        let proposed = NSRect(origin: point, size: frame.size)
        if let pinned = jarvisPinnedFrame(insteadOf: proposed) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameOrigin(pinned.origin)
            }
            return
        }
        jarvis_setFrameOrigin(point)
    }

    @objc func jarvis_setContentSize(_ size: NSSize) {
        let current = frame
        let proposedSize = frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let proposed = NSRect(
            x: current.origin.x,
            y: current.maxY - proposedSize.height,
            width: proposedSize.width,
            height: proposedSize.height
        )
        if let pinned = jarvisPinnedFrame(insteadOf: proposed) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrame(pinned, display: true, animate: false)
            }
            return
        }
        jarvis_setContentSize(size)
    }

    @objc func jarvis_reallySetFrame(_ frame: NSRect) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_reallySetFrame(pinned)
            }
            return
        }
        jarvis_reallySetFrame(frame)
    }

    /// `_setFrame:` is the private entry SwiftUI uses for implicit moves.
    /// The Swift name has to differ from `jarvis_setFrame(_:display:animate:)`.
    @objc(jarvis_setFrameIgnoringPublicAPI:)
    func jarvis_setFrameIgnoringPublicAPI(_ frame: NSRect) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameIgnoringPublicAPI(pinned)
            }
            return
        }
        jarvis_setFrameIgnoringPublicAPI(frame)
    }

    @objc(jarvis_setFrame:display:allowImplicitAnimation:stashSize:)
    func jarvis_setFrameAllowingImplicitAnimation(
        _ frame: NSRect,
        display: Bool,
        allowImplicitAnimation: Bool,
        stashSize: Bool
    ) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameAllowingImplicitAnimation(
                    pinned,
                    display: display,
                    allowImplicitAnimation: false,
                    stashSize: stashSize
                )
            }
            return
        }
        jarvis_setFrameAllowingImplicitAnimation(
            frame,
            display: display,
            allowImplicitAnimation: allowImplicitAnimation,
            stashSize: stashSize
        )
    }

    @objc(jarvis_setFrame:fromAdjustmentToScreen:animate:)
    func jarvis_setFrameForScreenAdjustment(_ frame: NSRect, screen: AnyObject?, animate: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameForScreenAdjustment(pinned, screen: screen, animate: false)
            }
            return
        }
        jarvis_setFrameForScreenAdjustment(frame, screen: screen, animate: animate)
    }

    @objc(jarvis_setFrameCommon:display:stashSize:)
    func jarvis_setFrameCommon(_ frame: NSRect, display: Bool, stashSize: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameCommon(pinned, display: display, stashSize: stashSize)
            }
            return
        }
        jarvis_setFrameCommon(frame, display: display, stashSize: stashSize)
    }

    @objc(jarvis_setFrameCommon:display:fromServer:)
    func jarvis_setFrameCommonFromServer(_ frame: NSRect, display: Bool, fromServer: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameCommonFromServer(pinned, display: display, fromServer: fromServer)
            }
            return
        }
        jarvis_setFrameCommonFromServer(frame, display: display, fromServer: fromServer)
    }

    @objc func jarvis_setFrameTopLeftPoint(_ point: NSPoint) {
        let userMoving = JarvisLaunchFrameBlock.isUserMoving
            || NSApp.currentEvent?.type == .leftMouseDragged
        guard let pinned = JarvisLaunchFrameBlock.frame,
              JarvisLaunchFrameBlock.window === self,
              !JarvisLaunchFrameBlock.isApplyingPinnedFrame,
              !inLiveResize,
              !userMoving
        else {
            jarvis_setFrameTopLeftPoint(point)
            return
        }
        let pinnedTopLeft = NSPoint(x: pinned.origin.x, y: pinned.origin.y + pinned.height)
        let moved = abs(point.x - pinnedTopLeft.x) > 1 || abs(point.y - pinnedTopLeft.y) > 1
        guard moved else {
            jarvis_setFrameTopLeftPoint(point)
            return
        }
        JarvisLaunchFrameBlock.performPinned {
            jarvis_setFrameTopLeftPoint(pinnedTopLeft)
        }
    }

    func jarvisPinnedFrame(insteadOf proposed: NSRect) -> NSRect? {
        guard !JarvisLaunchFrameBlock.isApplyingPinnedFrame else { return nil }
        guard let guarded = JarvisLaunchFrameBlock.window, guarded === self,
              let pinned = JarvisLaunchFrameBlock.frame
        else { return nil }
        let userMoving = JarvisLaunchFrameBlock.isUserMoving
            || NSApp.currentEvent?.type == .leftMouseDragged
        return JarvisMainWindowController.pinnedFrame(
            insteadOf: proposed,
            pinned: pinned,
            isLiveResizing: inLiveResize,
            isUserMoving: userMoving
        )
    }
}
