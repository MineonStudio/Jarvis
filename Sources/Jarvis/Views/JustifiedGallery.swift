import SwiftUI

enum JustifiedGalleryLayout {
    static let spacing = HistoryGridMetrics.clipboardGridSpacing

    struct Row: Identifiable {
        let indices: Range<Int>
        let widths: [CGFloat]
        let height: CGFloat

        var id: Int {
            indices.lowerBound
        }
    }

    static func aspectRatio(width: Int, height: Int) -> CGFloat {
        guard width > 0, height > 0 else { return HistoryGridLayout.aspectRatio }
        return max(0.1, CGFloat(width) / CGFloat(height))
    }

    static func rows(
        aspectRatios: [CGFloat],
        availableWidth: CGFloat,
        scale: CGFloat = 1
    ) -> [Row] {
        guard !aspectRatios.isEmpty else { return [] }

        let width = max(1, availableWidth)
        let minimumHeight = 128 * 1.20 * scale
        let idealHeight = 158 * 1.20 * scale
        let maximumHeight = 220 * 1.20 * scale
        var result: [Row] = []
        var start = 0
        var totalRatio: CGFloat = 0

        for (index, ratio) in aspectRatios.enumerated() {
            let candidate = start ..< index + 1
            let candidateHeight = fittedHeight(
                width: width, count: candidate.count, totalRatio: totalRatio + ratio
            )
            if candidate.count > 1, candidateHeight < minimumHeight {
                result.append(makeRow(
                    start ..< index, aspectRatios: aspectRatios,
                    width: width, totalRatio: totalRatio, heightLimit: maximumHeight
                ))
                start = index
                totalRatio = 0
            }
            totalRatio += ratio
        }
        result.append(makeRow(
            start ..< aspectRatios.count, aspectRatios: aspectRatios,
            width: width, totalRatio: totalRatio, heightLimit: idealHeight
        ))
        return result
    }

    private static func fittedHeight(width: CGFloat, count: Int, totalRatio: CGFloat) -> CGFloat {
        max(0, width - spacing * CGFloat(count - 1)) / totalRatio
    }

    private static func makeRow(
        _ indices: Range<Int>, aspectRatios: [CGFloat], width: CGFloat, totalRatio: CGFloat, heightLimit: CGFloat
    ) -> Row {
        let height = min(heightLimit, fittedHeight(width: width, count: indices.count, totalRatio: totalRatio))
        return Row(indices: indices, widths: aspectRatios[indices].map { $0 * height }, height: height)
    }
}

struct JustifiedGallery<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let availableWidth: CGFloat
    var scale: CGFloat = 1
    let aspectRatio: (Item) -> CGFloat
    @ViewBuilder let card: (Item, CGSize) -> Card

    var body: some View {
        let rows = JustifiedGalleryLayout.rows(
            aspectRatios: items.map(aspectRatio), availableWidth: availableWidth, scale: scale
        )
        LazyVStack(alignment: .leading, spacing: JustifiedGalleryLayout.spacing) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: JustifiedGalleryLayout.spacing) {
                    ForEach(Array(zip(items[row.indices], row.widths)), id: \.0.id) { item, width in
                        card(item, CGSize(width: width, height: row.height))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
