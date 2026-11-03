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

    func frame(in bounds: CGRect) -> CGRect {
        let unit = unitRect
        return CGRect(
            x: bounds.minX + bounds.width * unit.minX,
            y: bounds.minY + bounds.height * unit.minY,
            width: bounds.width * unit.width, height: bounds.height * unit.height
        )
    }

    func frame(preserving size: CGSize, in bounds: CGRect) -> CGRect {
        let region = frame(in: bounds)
        let unit = unitRect
        let x = unit.width == 1 ? region.midX - size.width / 2
            : (unit.minX == 0 ? region.minX : region.maxX - size.width)
        let y = unit.height == 1 ? region.midY - size.height / 2
            : (unit.minY == 0 ? region.minY : region.maxY - size.height)
        return CGRect(
            x: min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)),
            width: size.width, height: size.height
        )
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
        var rect = placement.frame(in: inner)
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
