import Foundation

/// Keep all eight panels visible. Very small windows use a proportionally
/// scaled canvas rather than hiding panels or adding a page scroll view.
struct HomeDashboardLayout {
    let scale: CGFloat
    let canvas: CGSize

    init(size: CGSize) {
        scale = max(0.01, min(1, size.width / 900, size.height / 620))
        canvas = CGSize(width: max(0, size.width) / scale, height: max(0, size.height) / scale)
    }
}
