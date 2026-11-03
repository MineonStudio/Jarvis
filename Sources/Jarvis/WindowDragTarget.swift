import AppKit
import ApplicationServices

/// Retains the original AX identity, never re-resolves the frontmost window on drop.
@MainActor
final class WindowDragTarget {
    weak var nativeWindow: NSWindow?
    private(set) var accessibilityWindow: AXUIElement?
    private(set) var supportsResizing: Bool
    private let windowID: CGWindowID?
    private let application: NSRunningApplication?

    var processIdentifier: pid_t {
        application?.processIdentifier ?? ProcessInfo.processInfo.processIdentifier
    }

    private init(nativeWindow: NSWindow) {
        self.nativeWindow = nativeWindow
        accessibilityWindow = nil
        supportsResizing = true
        windowID = Self.matchingWindowID(
            processID: ProcessInfo.processInfo.processIdentifier,
            frame: WindowLayoutCoordinates.flipped(nativeWindow.frame, primaryDisplayTop: Self.primaryDisplayTop)
        )
        application = nil
    }

    private init(window: AXUIElement, application: NSRunningApplication, windowID: CGWindowID?, supportsResizing: Bool) {
        accessibilityWindow = window
        self.application = application
        self.windowID = windowID
        self.supportsResizing = supportsResizing
    }

    private init(server: ServerWindow, application: NSRunningApplication) {
        accessibilityWindow = nil
        supportsResizing = true
        self.application = application
        windowID = server.id
    }

    enum Resolution {
        case ready
        case permissionRequired
        case unavailable
    }

    /// Resolve AX only after the drag ends. Detection and the picker remain usable
    /// when permission is missing or an app is busy handling its native drag loop.
    func resolveAccessibilityWindow() -> Resolution {
        if nativeWindow != nil {
            return .ready
        }
        guard JarvisPrivacyPermissionAccess.isAccessibilityTrusted() else { return .permissionRequired }
        if accessibilityWindow != nil {
            return .ready
        }
        guard let windowID, let frame, application?.isTerminated == false else { return .unavailable }
        let pointer = CGPoint(x: frame.midX, y: frame.midY)
        guard let resolved = Self.captureAccessibilityTarget(at: pointer, hitNumber: Int(windowID)),
              resolved.application?.processIdentifier == application?.processIdentifier,
              let window = resolved.accessibilityWindow else { return .unavailable }
        accessibilityWindow = window
        supportsResizing = resolved.supportsResizing
        return .ready
    }

    var frame: CGRect? {
        if let window = nativeWindow {
            guard window.isVisible, !window.isMiniaturized, !window.styleMask.contains(.fullScreen) else { return nil }
            return serverFrame() ?? window.frame
        }
        guard application?.isTerminated == false else { return nil }
        // WindowServer geometry remains available while an app is in native title-bar tracking.
        if let frame = serverFrame() {
            return frame
        }
        guard let window = accessibilityWindow, JarvisPrivacyPermissionAccess.isAccessibilityTrusted() else { return nil }
        return Self.accessibilityFrame(window).map(Self.appKitRect)
    }

    static func capture(at pointer: CGPoint, eventWindow: NSWindow?) -> WindowDragTarget? {
        let hitNumber = NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0)
        if let window = eventWindow ?? NSApplication.shared.window(withWindowNumber: hitNumber) {
            guard window.isVisible, !window.isMiniaturized, !window.ignoresMouseEvents,
                  !window.styleMask.contains(.fullScreen), window.frame.insetBy(dx: 6, dy: 6).contains(pointer),
                  !(window.identifier?.rawValue.hasPrefix("Jarvis.WindowSnap") ?? false)
            else { return nil }
            return WindowDragTarget(nativeWindow: window)
        }
        guard let server = serverWindow(number: hitNumber),
              server.processID != ProcessInfo.processInfo.processIdentifier,
              appKitRect(server.frame).insetBy(dx: 6, dy: 6).contains(pointer),
              let application = NSRunningApplication(processIdentifier: server.processID)
        else { return nil }
        return WindowDragTarget(server: server, application: application)
    }

    /// Capture focus before showing the picker, independently of the pointer.
    static func captureFocusedWindow(
        of application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> WindowDragTarget? {
        guard let application else { return nil }
        if application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if let window = NSApplication.shared.keyWindow, let target = captureNativeWindow(window) {
                return target
            }
            guard let window = NSApplication.shared.mainWindow else { return nil }
            return captureNativeWindow(window)
        }
        guard JarvisPrivacyPermissionAccess.isAccessibilityTrusted(), !application.isTerminated else { return nil }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        guard let window = elementAttribute(kAXFocusedWindowAttribute, of: app) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.12)
        guard !boolAttribute("AXFullScreen", of: window), !boolAttribute(kAXMinimizedAttribute, of: window),
              isSettable(kAXPositionAttribute, of: window) != false,
              let frame = accessibilityFrame(window), frame.width > 0, frame.height > 0 else { return nil }
        return WindowDragTarget(
            window: window, application: application,
            windowID: matchingWindowID(processID: application.processIdentifier, frame: frame),
            supportsResizing: isSettable(kAXSizeAttribute, of: window) != false
        )
    }

    static func captureNativeWindow(_ window: NSWindow) -> WindowDragTarget? {
        guard window.isVisible, !window.isMiniaturized, !window.styleMask.contains(.fullScreen),
              !window.ignoresMouseEvents,
              !(window.identifier?.rawValue.hasPrefix("Jarvis.WindowSnap") ?? false) else { return nil }
        return WindowDragTarget(nativeWindow: window)
    }

    private struct ServerWindow {
        let id: CGWindowID
        let processID: pid_t
        let frame: CGRect
    }

    private static func captureAccessibilityTarget(at pointer: CGPoint, hitNumber: Int) -> WindowDragTarget? {
        let server = serverWindow(number: hitNumber)
        let point = CGPoint(x: pointer.x, y: primaryDisplayTop - pointer.y)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        var processID: pid_t = 0
        if let hit {
            AXUIElementGetPid(hit, &processID)
        }
        processID = server?.processID ?? (processID > 0 ? processID : NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        guard processID != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: processID)
        else { return nil }
        let applicationElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(applicationElement, 0.08)
        var candidates: [AXUIElement] = []
        if let hit, let window = windowAncestor(of: hit) {
            if let frame = candidateFrame(window, processID: processID, pointer: pointer),
               server == nil || frameDistance(frame, server?.frame ?? frame) < 8
            {
                return accessibilityTarget(window, frame: frame, application: application, server: server)
            }
            candidates.append(window)
        }
        candidates += attribute(kAXWindowsAttribute, of: applicationElement) as? [AXUIElement] ?? []
        if let focused = elementAttribute(kAXFocusedWindowAttribute, of: applicationElement) {
            candidates.append(focused)
        }
        let windows = candidates.compactMap { window -> (AXUIElement, CGRect)? in
            guard let frame = candidateFrame(window, processID: processID, pointer: pointer) else { return nil }
            return (window, frame)
        }.sorted { lhs, rhs in
            guard let server else { return false }
            return frameDistance(lhs.1, server.frame) < frameDistance(rhs.1, server.frame)
        }
        if let (window, frame) = windows.first {
            return accessibilityTarget(window, frame: frame, application: application, server: server)
        }
        return nil
    }

    private static func candidateFrame(_ window: AXUIElement, processID: pid_t, pointer: CGPoint) -> CGRect? {
        AXUIElementSetMessagingTimeout(window, 0.08)
        var owner: pid_t = 0
        AXUIElementGetPid(window, &owner)
        guard owner == processID, !boolAttribute("AXFullScreen", of: window),
              !boolAttribute(kAXMinimizedAttribute, of: window),
              isSettable(kAXPositionAttribute, of: window) != false,
              let frame = accessibilityFrame(window), appKitRect(frame).insetBy(dx: 6, dy: 6).contains(pointer)
        else { return nil }
        return frame
    }

    private static func accessibilityTarget(
        _ window: AXUIElement, frame: CGRect, application: NSRunningApplication, server: ServerWindow?
    ) -> WindowDragTarget {
        WindowDragTarget(
            window: window, application: application,
            windowID: server.flatMap { frameDistance($0.frame, frame) < 8 ? $0.id : nil }
                ?? matchingWindowID(processID: application.processIdentifier, frame: frame),
            supportsResizing: isSettable(kAXSizeAttribute, of: window) != false
        )
    }

    private func serverFrame() -> CGRect? {
        guard let windowID,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return Self.appKitRect(rect)
    }

    private static func serverWindow(number: Int) -> ServerWindow? {
        guard number > 0,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]])?.first,
              let processID = info[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return ServerWindow(id: CGWindowID(number), processID: processID, frame: frame)
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    private static func windowAncestor(of element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0 ..< 16 {
            let role = stringAttribute(kAXRoleAttribute, of: current)
            if role == kAXWindowRole || role == kAXSheetRole {
                return current
            }
            if let window = elementAttribute(kAXWindowAttribute, of: current) {
                return window
            }
            guard let parent = elementAttribute(kAXParentAttribute, of: current), !CFEqual(parent, current) else { return nil }
            current = parent
        }
        return nil
    }

    private static func isSettable(_ name: String, of element: AXUIElement) -> Bool? {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else { return nil }
        return settable.boolValue
    }

    private static var primaryDisplayTop: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private static func appKitRect(_ rect: CGRect) -> CGRect {
        WindowLayoutCoordinates.flipped(rect, primaryDisplayTop: primaryDisplayTop)
    }

    private static func matchingWindowID(processID: pid_t, frame: CGRect) -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.first { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(processID),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return abs(rect.minX - frame.minX) < 3 && abs(rect.minY - frame.minY) < 3
                && abs(rect.width - frame.width) < 3 && abs(rect.height - frame.height) < 3
        }?[kCGWindowNumber as String] as? CGWindowID
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    private static func boolAttribute(_ name: String, of element: AXUIElement) -> Bool {
        attribute(name, of: element) as? Bool ?? false
    }

    private static func accessibilityFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: window),
              let size = attribute(kAXSizeAttribute, of: window),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
