import AppKit

enum WindowSnapPlacement: String, CaseIterable, Sendable {
    case halfLeft, halfRight, halfTop, halfBottom
    case upperLeft, upperRight, lowerLeft, lowerRight

    var group: WindowSnapGroup {
        switch self {
        case .halfLeft, .halfRight: .leftRight
        case .halfTop, .halfBottom: .topBottom
        case .upperLeft, .upperRight, .lowerLeft, .lowerRight: .corners
        }
    }

    var title: String {
        switch self {
        case .halfLeft: "左半屏"
        case .halfRight: "右半屏"
        case .halfTop: "上半屏"
        case .halfBottom: "下半屏"
        case .upperLeft: "左上角"
        case .upperRight: "右上角"
        case .lowerLeft: "左下角"
        case .lowerRight: "右下角"
        }
    }

    /// Space between adjacent snapped windows, in points. On a 1x display this is 1px.
    static let windowGap: CGFloat = 1

    /// Unit rectangle in AppKit's bottom-left coordinates, also used for icons.
    var unitRect: CGRect {
        switch self {
        case .halfLeft: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .halfRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .halfTop: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .halfBottom: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .upperLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .upperRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .lowerLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .lowerRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        }
    }

    func frame(in bounds: CGRect, gap: CGFloat = windowGap) -> CGRect {
        let unit = unitRect
        var rect = CGRect(
            x: bounds.minX + bounds.width * unit.minX,
            y: bounds.minY + bounds.height * unit.minY,
            width: bounds.width * unit.width, height: bounds.height * unit.height
        )
        guard gap > 0 else { return rect }
        // Keep the whole seam on the leading tile. A half-point split is rounded
        // away by the window server, so the two frames end up touching.
        if unit.minX + unit.width < 1 {
            rect.size.width -= gap
            rect.size.width = floor(rect.maxX) - rect.minX
        }
        if unit.minX > 0 {
            let minX = ceil(rect.minX)
            rect.size.width -= minX - rect.minX
            rect.origin.x = minX
        }
        if unit.minY + unit.height < 1 {
            rect.size.height -= gap
            rect.size.height = floor(rect.maxY) - rect.minY
        }
        if unit.minY > 0 {
            let minY = ceil(rect.minY)
            rect.size.height -= minY - rect.minY
            rect.origin.y = minY
        }
        return rect
    }

    func frame(preserving size: CGSize, in bounds: CGRect) -> CGRect {
        let region = frame(in: bounds)
        let unit = unitRect
        // AX may return a size up to 1pt larger than requested. Keep that extra
        // pixel on the outer side of a partial tile so it does not cover the
        // neighbor. A larger overflow is a real minimum size and stays on screen.
        let slack = Self.windowGap + 1
        return CGRect(
            x: Self.preservedOrigin(
                region: Span(origin: region.minX, length: region.width), size: size.width,
                bounds: Span(origin: bounds.minX, length: bounds.width),
                unit: Span(origin: unit.minX, length: unit.width), slack: slack
            ),
            y: Self.preservedOrigin(
                region: Span(origin: region.minY, length: region.height), size: size.height,
                bounds: Span(origin: bounds.minY, length: bounds.height),
                unit: Span(origin: unit.minY, length: unit.height), slack: slack
            ),
            width: size.width, height: size.height
        )
    }

    private struct Span {
        var origin: CGFloat
        var length: CGFloat
    }

    private static func preservedOrigin(
        region: Span, size: CGFloat, bounds: Span, unit: Span, slack: CGFloat
    ) -> CGFloat {
        let overflow = size - region.length
        let withinSlack = overflow > 0 && overflow <= slack
        let raw: CGFloat = if unit.length == 1 {
            region.origin + (region.length - size) / 2
        } else if unit.origin == 0 {
            withinSlack ? region.origin + region.length - size : region.origin
        } else {
            withinSlack ? region.origin : region.origin + region.length - size
        }
        guard unit.length < 1, withinSlack else {
            let limit = bounds.origin + bounds.length - size
            return min(max(raw, bounds.origin), max(bounds.origin, limit))
        }
        return raw
    }
}

enum WindowSnapGroup: String, CaseIterable {
    case leftRight, topBottom, corners

    var placements: [WindowSnapPlacement] {
        WindowSnapPlacement.allCases.filter { $0.group == self }
    }
}

struct WindowSnapBarGeometry {
    let frame: CGRect
    static let height: CGFloat = 124

    static func surfaceRect(in bounds: CGRect) -> CGRect {
        guard bounds.width > 16, bounds.height > 16 else { return .zero }
        return bounds.insetBy(dx: 8, dy: 8)
    }

    static func blockRect(for placement: WindowSnapPlacement, in panel: CGRect) -> CGRect {
        guard panel.width > 16, panel.height > 16 else { return .zero }
        let inner = panel.insetBy(dx: 8, dy: 8)
        var rect = placement.frame(in: inner, gap: 0)
        let unit = placement.unitRect
        if unit.width < 1 {
            rect.size.width -= 2
            if unit.minX > 0 {
                rect.origin.x += 2
            }
        }
        if unit.height < 1 {
            rect.size.height -= 2
            if unit.minY > 0 {
                rect.origin.y += 2
            }
        }
        return rect
    }

    init(visibleFrame: CGRect) {
        let availableWidth = min(560, max(200, visibleFrame.width - 24))
        let gap: CGFloat = 12
        let count = CGFloat(WindowSnapGroup.allCases.count)
        let optionWidth = floor((availableWidth - gap * (count - 1)) / count)
        let width = optionWidth * count + gap * (count - 1)
        frame = CGRect(
            x: floor(visibleFrame.midX - width / 2), y: floor(visibleFrame.maxY - Self.height - 12),
            width: width, height: Self.height
        )
    }

    func localRect(for group: WindowSnapGroup) -> CGRect {
        let items = WindowSnapGroup.allCases
        let index = items.firstIndex(of: group) ?? 0
        let gap: CGFloat = 12
        let width = (frame.width - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
        return CGRect(
            x: CGFloat(index) * (width + gap),
            y: 0, width: width, height: Self.height
        )
    }

    func localRect(for placement: WindowSnapPlacement) -> CGRect {
        Self.blockRect(for: placement, in: Self.surfaceRect(in: localRect(for: placement.group)))
    }

    func group(at screenPoint: CGPoint) -> WindowSnapGroup? {
        guard frame.contains(screenPoint) else { return nil }
        let point = CGPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
        return WindowSnapGroup.allCases.first {
            Self.surfaceRect(in: localRect(for: $0)).contains(point)
        }
    }

    func placement(at screenPoint: CGPoint) -> WindowSnapPlacement? {
        guard let group = group(at: screenPoint) else { return nil }
        let point = CGPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
        return group.placements.first { localRect(for: $0).contains(point) }
    }
}

/// Only genuine window motion following the pointer can arm a drop.
struct WindowDragMotion {
    private var initialPointer: CGPoint
    private var initialFrame: CGRect
    private let allowsInitialResize: Bool
    private var rebased = false
    private(set) var isMoving = false
    private(set) var isRejected = false

    init(pointer: CGPoint, frame: CGRect) {
        initialPointer = pointer
        initialFrame = frame
        allowsInitialResize = pointer.y >= frame.maxY - 64
    }

    mutating func observe(pointer: CGPoint, frame: CGRect) {
        guard !isRejected else { return }
        if abs(frame.width - initialFrame.width) > 3 || abs(frame.height - initialFrame.height) > 3 {
            // macOS restores a tiled window's original size when its title bar is dragged.
            if !isMoving, allowsInitialResize, !rebased {
                initialPointer = pointer
                initialFrame = frame
                rebased = true
            } else {
                isRejected = true
            }
            return
        }
        let pointerDelta = CGPoint(x: pointer.x - initialPointer.x, y: pointer.y - initialPointer.y)
        let frameDelta = CGPoint(x: frame.minX - initialFrame.minX, y: frame.minY - initialFrame.minY)
        if hypot(pointerDelta.x, pointerDelta.y) >= 6,
           hypot(frameDelta.x, frameDelta.y) >= 4,
           hypot(pointerDelta.x - frameDelta.x, pointerDelta.y - frameDelta.y) <= 32
        {
            isMoving = true
        }
    }
}

enum WindowLayoutCoordinates {
    /// Quartz and AX use the primary display's top-left, including on vertically stacked displays.
    static func flipped(_ rect: CGRect, primaryDisplayTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayTop - rect.maxY, width: rect.width, height: rect.height)
    }
}
