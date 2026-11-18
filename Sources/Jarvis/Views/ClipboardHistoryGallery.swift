import SwiftUI

/// Shared clipboard gallery for the main window and F3 shelf.
struct ClipboardHistoryGallery: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [ClipboardItem]
    let gridZoom: HistoryGridZoomLevel
    @Binding var selection: GallerySelection<UUID>
    let availableWidth: CGFloat
    var columnCount: Int?
    let hasQuery: Bool
    var emptyStateHeight: CGFloat?
    let onDoubleClick: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onPreview: (ClipboardItem) -> Void
    let onPin: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                ClipboardEmptyState(hasQuery: hasQuery)
                    .frame(height: emptyStateHeight)
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            } else {
                FixedRatioGallery(
                    items: items, availableWidth: availableWidth, targetWidth: gridZoom.cardWidth,
                    columnCount: columnCount, card: card
                )
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(JarvisSecondaryButtonStyle())
        .toggleStyle(SettingsFlatToggleStyle())
        .environment(\.jarvisFlatControls, true)
        .environment(\.jarvisContentButtonShadows, true)
    }

    private func card(_ item: ClipboardItem, _ size: CGSize) -> some View {
        ClipboardCard(
            item: item, isSelected: selection.selectedID == item.id, cardSize: size,
            maxPixelSize: gridZoom.thumbnailPixelSize, enablesHoverZoom: gridZoom.enablesHoverZoom,
            onClick: { count, open in GallerySelection.handleClick(count, on: item.id, selection: $selection, open: open) },
            onSelect: { selection.toggle(item.id) },
            onDoubleClick: { onDoubleClick(item) },
            onCopy: { onCopy(item) },
            onPreview: { onPreview(item) },
            onPin: { onPin(item) },
            onDelete: { onDelete(item) }
        )
        .equatable()
    }
}
