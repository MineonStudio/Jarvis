import Foundation

/// Keep all nine panels visible. Very small windows use a proportionally
/// scaled canvas rather than hiding panels or adding a page scroll view.
/// Monitoring cards use content-sized heights, independent of window height.
/// The overview and ranking rows share the remaining vertical space.
struct HomeDashboardLayout {
    let scale: CGFloat
    let canvas: CGSize

    static let headerHeight: CGFloat = 60
    static let topPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 10
    /// Vertical space taken by the three 10pt gaps between the four bands.
    static let bandSpacing: CGFloat = rowSpacing * 3
    /// 28pt insets + 16pt title + 10pt gap + 48pt readings, rounded up.
    static let metricsHeight: CGFloat = 104
    // Only a visible thermal advisory needs another gap and two text lines.
    static let metricsGuidanceHeight: CGFloat = 136
    static let rankingShare: CGFloat = 0.19
    /// A date cell is about 39pt. Taller week rows only open empty gaps.
    static let calendarPreferredRowHeight: CGFloat = 52

    init(size: CGSize) {
        scale = max(0.01, min(1, size.width / 900, size.height / 620))
        canvas = CGSize(width: max(0, size.width) / scale, height: max(0, size.height) / scale)
    }

    static func bands(contentHeight: CGFloat, showsThermalGuidance: Bool = false) -> HomeDashboardBands {
        let metrics = showsThermalGuidance ? metricsGuidanceHeight : metricsHeight
        let ranking = max(0, contentHeight * rankingShare)
        let overview = max(0, contentHeight - headerHeight - metrics - ranking - bandSpacing)
        return HomeDashboardBands(header: headerHeight, metrics: metrics, overview: overview, ranking: ranking)
    }

    static func calendarRowHeight(availableHeight: CGFloat, weeks: Int) -> CGFloat {
        let count = CGFloat(max(weeks, 1))
        return min(calendarPreferredRowHeight, max(1, availableHeight / count))
    }
}

struct HomeDashboardBands: Equatable {
    let header: CGFloat
    let metrics: CGFloat
    let overview: CGFloat
    let ranking: CGFloat
}
