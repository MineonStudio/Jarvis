import Foundation

/// Keep all eight panels visible. Very small windows use a proportionally
/// scaled canvas rather than hiding panels or adding a page scroll view.
/// Large windows keep the same band shares in real points. Scaling above 1
/// would blur the text, so extra height stays in the cards.
struct HomeDashboardLayout {
    let scale: CGFloat
    let canvas: CGSize

    static let headerHeight: CGFloat = 64
    /// Vertical space taken by the three 10pt gaps between the four bands.
    static let bandSpacing: CGFloat = 30
    static let metricsMinimumHeight: CGFloat = 134
    static let metricsShare: CGFloat = 0.215
    static let rankingShare: CGFloat = 0.19
    /// A date cell is about 39pt. Taller week rows only open empty gaps.
    static let calendarPreferredRowHeight: CGFloat = 52

    init(size: CGSize) {
        scale = max(0.01, min(1, size.width / 900, size.height / 620))
        canvas = CGSize(width: max(0, size.width) / scale, height: max(0, size.height) / scale)
    }

    static func bands(contentHeight: CGFloat) -> HomeDashboardBands {
        let metrics = max(metricsMinimumHeight, contentHeight * metricsShare)
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
