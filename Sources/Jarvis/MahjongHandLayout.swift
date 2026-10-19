import Foundation

/// The concealed row stays centered independently of a separately drawn tile.
enum MahjongHandLayout {
    // World dimensions shared by model placement and native pointer hit testing.
    static let tileWidth: Float = 0.78
    static let tileHeight: Float = 1.10
    static let tileGap: Float = 0.02
    static let cameraHalfHeight: Float = 8.4
    static let localRowDepth: Float = 6.1

    static func hoverTravel(tileHeight: Float) -> Float {
        tileHeight / 4
    }

    /// Convert native view coordinates to the overhead scene's X/Z plane.
    static func worldPoint(_ point: CGPoint, size: CGSize, isFlipped: Bool) -> CGPoint? {
        guard size.width > 0, size.height > 0,
              CGRect(origin: .zero, size: size).contains(point) else { return nil }
        let unit = size.height / CGFloat(cameraHalfHeight * 2)
        let topDownY = isFlipped ? point.y : size.height - point.y
        return CGPoint(x: (point.x - size.width / 2) / unit, y: (topDownY - size.height / 2) / unit)
    }

    static func centeredOffsets(count: Int, tileWidth: Float, gap: Float) -> [Float] {
        guard count > 0 else { return [] }
        let step = tileWidth + gap
        let halfSpan = Float(count - 1) * step / 2
        return (0 ..< count).map { Float($0) * step - halfSpan }
    }

    static func drawnOffset(after count: Int, tileWidth: Float, gap: Float) -> Float {
        guard count > 0 else { return 0 }
        let rightmost = Float(count - 1) * (tileWidth + gap) / 2
        // Two tile widths between centers leaves exactly one empty tile width.
        return rightmost + tileWidth * 2
    }
}
