import AppKit
import ApplicationServices

@MainActor
enum WindowLayoutScreenArea {
    static func visibleFrame(for screen: NSScreen) -> NSRect {
        safeVisibleFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            dockFrame: dockFrame(on: screen)
        )
    }

    static func safeVisibleFrame(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        dockFrame: NSRect?
    ) -> NSRect {
        var safeFrame = visibleFrame.intersection(screenFrame)
        guard let dockFrame,
              !dockFrame.isNull,
              !dockFrame.isEmpty
        else {
            return safeFrame
        }

        let dock = dockFrame.intersection(screenFrame)
        guard !dock.isNull, !dock.isEmpty else { return safeFrame }

        let isBottomDock = dock.width >= screenFrame.width * 0.65
            && dock.height < screenFrame.height * 0.5
            && dock.minY <= screenFrame.minY + screenFrame.height * 0.25
        if isBottomDock {
            let safeMaxY = min(safeFrame.maxY, screenFrame.maxY)
            let safeMinY = max(safeFrame.minY, dock.maxY)
            safeFrame = NSRect(
                x: safeFrame.minX,
                y: safeMinY,
                width: safeFrame.width,
                height: max(0, safeMaxY - safeMinY)
            )
            return safeFrame
        }

        let isLeftDock = dock.height >= screenFrame.height * 0.65
            && dock.width < screenFrame.width * 0.5
            && dock.minX <= screenFrame.minX + screenFrame.width * 0.25
        if isLeftDock {
            let safeMaxX = min(safeFrame.maxX, screenFrame.maxX)
            let safeMinX = max(safeFrame.minX, dock.maxX)
            safeFrame = NSRect(
                x: safeMinX,
                y: safeFrame.minY,
                width: max(0, safeMaxX - safeMinX),
                height: safeFrame.height
            )
            return safeFrame
        }

        let isRightDock = dock.height >= screenFrame.height * 0.65
            && dock.width < screenFrame.width * 0.5
            && dock.maxX >= screenFrame.maxX - screenFrame.width * 0.25
        if isRightDock {
            let safeMinX = max(safeFrame.minX, screenFrame.minX)
            let safeMaxX = min(safeFrame.maxX, dock.minX)
            safeFrame = NSRect(
                x: safeMinX,
                y: safeFrame.minY,
                width: max(0, safeMaxX - safeMinX),
                height: safeFrame.height
            )
        }
        return safeFrame
    }

    private static func dockFrame(on screen: NSScreen) -> NSRect? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        var bestFrame: NSRect?
        var bestArea: CGFloat = 0

        for info in windowInfoList {
            let ownerName = (info[kCGWindowOwnerName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard ownerName == "dock" || ownerName == "程序坞",
                  let boundsValue = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(dictionaryRepresentation: boundsValue)
            else {
                continue
            }

            let appKitFrame = NSRect(
                x: quartzBounds.minX,
                y: desktopTop - quartzBounds.maxY,
                width: quartzBounds.width,
                height: quartzBounds.height
            )
            let intersection = appKitFrame.intersection(screen.frame)
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestFrame = intersection
            }
        }

        return bestFrame
    }
}

@MainActor
final class WindowLayoutController {
    private let statusHandler: (String) -> Void
    var onAccessibilityRequired: (() -> Void)?

    init(statusHandler: @escaping (String) -> Void) {
        self.statusHandler = statusHandler
    }

    var isAccessibilityTrusted: Bool {
        JarvisPrivacyPermissionAccess.isAccessibilityTrusted()
    }

    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        JarvisPrivacyPermissionAccess.requestAccessibilityAccess()
    }

    func apply(_ placement: WindowSnapPlacement, to target: WindowDragTarget, on screen: NSScreen) {
        guard let originalFrame = target.frame else { return }
        switch target.resolveAccessibilityWindow() {
        case .ready:
            break
        case .permissionRequired:
            statusHandler("请先开启辅助功能权限，以调整其他应用窗口")
            onAccessibilityRequired?()
            return
        case .unavailable:
            statusHandler(JarvisFeedbackCopy.noAdjustableWindow)
            return
        }
        let visibleFrame = WindowLayoutScreenArea.visibleFrame(for: screen)
        let frame = placement.frame(in: visibleFrame)
        if let window = target.nativeWindow {
            applyNative(placement, to: window, in: visibleFrame)
            return
        } else if let window = target.accessibilityWindow {
            guard isAccessibilityTrusted else { return }
            if !target.supportsResizing || !setFrame(frame, on: window, using: screen) {
                let fixedFrame = placement.frame(preserving: target.frame?.size ?? originalFrame.size, in: visibleFrame)
                if setPosition(fixedFrame, on: window, using: screen) {
                    statusHandler("窗口已移动，尺寸受应用限制")
                    return
                }
                statusHandler(JarvisFeedbackCopy.windowNotResizable)
                return
            }
        } else {
            return
        }
    }

    private func applyNative(_ placement: WindowSnapPlacement, to window: NSWindow, in visibleFrame: CGRect) {
        let frame = placement.frame(in: visibleFrame)
        if !JarvisMainWindowController.applyWindowLayoutFrame(frame, to: window) {
            window.setFrame(frame, display: true)
        }
        if abs(window.frame.width - frame.width) > 1 || abs(window.frame.height - frame.height) > 1 {
            window.setFrameOrigin(placement.frame(preserving: window.frame.size, in: visibleFrame).origin)
            statusHandler("窗口已移动，尺寸受应用限制")
        }
    }

    private func setFrame(_ frame: NSRect, on window: AXUIElement, using screen: NSScreen) -> Bool {
        let position = CGPoint(
            x: frame.minX,
            y: accessibilityY(for: frame, on: screen)
        )
        var positionValue = position
        var sizeValue = frame.size
        guard let axPosition = AXValueCreate(.cgPoint, &positionValue),
              let axSize = AXValueCreate(.cgSize, &sizeValue)
        else {
            return false
        }

        // Some applications clamp the size when the position is changed in
        // the same AX transaction. Apply the position, apply the exact target
        // size, then apply the position once more to stabilize both halves.
        let initialPositionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            axPosition
        )
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axSize)
        let finalPositionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            axPosition
        )
        return initialPositionResult == .success
            && sizeResult == .success
            && finalPositionResult == .success
    }

    private func setPosition(_ frame: NSRect, on window: AXUIElement, using screen: NSScreen) -> Bool {
        var point = CGPoint(x: frame.minX, y: accessibilityY(for: frame, on: screen))
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func accessibilityFrame(for screen: NSScreen) -> CGRect {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            return CGRect(
                x: screen.frame.minX,
                y: desktopTop - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
        return CGDisplayBounds(displayID)
    }

    private func accessibilityY(for frame: NSRect, on screen: NSScreen) -> CGFloat {
        let fullFrame = accessibilityFrame(for: screen)
        let relativeMaxY = frame.maxY - screen.frame.minY
        return fullFrame.minY + (screen.frame.height - relativeMaxY)
    }
}
