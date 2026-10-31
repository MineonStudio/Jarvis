import SwiftUI

/// Non-interactive selection markers remain visible after confirming the region.
struct ScreenRecordingRegionOutline: View {
    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 2, dy: 2)
            let length = min(20, min(bounds.width, bounds.height) / 3)
            Rectangle().strokeBorder(.white.opacity(0.45), lineWidth: 1)
            Path { path in
                for (point, dx, dy) in [
                    (CGPoint(x: bounds.minX, y: bounds.minY), 1.0, 1.0),
                    (CGPoint(x: bounds.maxX, y: bounds.minY), -1.0, 1.0),
                    (CGPoint(x: bounds.minX, y: bounds.maxY), 1.0, -1.0),
                    (CGPoint(x: bounds.maxX, y: bounds.maxY), -1.0, -1.0)
                ] {
                    path.move(to: CGPoint(x: point.x + dx * length, y: point.y))
                    path.addLine(to: point)
                    path.addLine(to: CGPoint(x: point.x, y: point.y + dy * length))
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
            .shadow(color: .black.opacity(0.6), radius: 1)
        }
        .allowsHitTesting(false)
    }
}
