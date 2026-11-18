import SwiftUI

/// Shared landscape ratio for history and game cards.
enum HistoryGridLayout {
    static let aspectRatio: CGFloat = 16.0 / 9.0

    static func cardHeight(forCardWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }
}

/// 宫格的列几何：贴着一行铺满，卡片按比例跟着长。给测试用，也是这条约定的成文版本。
enum HistoryGridColumns {
    /// 按可用宽度算这一行放几列：取最接近目标宽度的那个列数。
    static func columns(availableWidth: CGFloat, targetWidth: CGFloat, spacing: CGFloat) -> Int {
        guard availableWidth > 0, targetWidth > 0 else { return 1 }
        return max(1, Int(((availableWidth + spacing) / (targetWidth + spacing)).rounded()))
    }

    /// Distribute the available width equally across all columns.
    static func cardWidth(
        availableWidth: CGFloat, targetWidth: CGFloat, spacing: CGFloat, columnCount: Int? = nil
    ) -> CGFloat {
        guard availableWidth > 0, targetWidth > 0 else { return targetWidth }
        let count = CGFloat(columnCount ?? columns(
            availableWidth: availableWidth,
            targetWidth: targetWidth,
            spacing: spacing
        ))
        return max(1, (availableWidth - (count - 1) * spacing) / count)
    }
}

struct FixedRatioGallery<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let availableWidth: CGFloat
    let targetWidth: CGFloat
    var aspectRatio = HistoryGridLayout.aspectRatio
    var columnCount: Int?
    @ViewBuilder let card: (Item, CGSize) -> Card

    var body: some View {
        let spacing = HistoryGridMetrics.clipboardGridSpacing
        let count = columnCount ?? HistoryGridColumns.columns(
            availableWidth: availableWidth, targetWidth: targetWidth, spacing: spacing
        )
        let cardWidth = HistoryGridColumns.cardWidth(
            availableWidth: availableWidth, targetWidth: targetWidth, spacing: spacing, columnCount: count
        )
        let size = CGSize(width: cardWidth, height: cardWidth / aspectRatio)
        let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: count)

        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(items) { card($0, size) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
