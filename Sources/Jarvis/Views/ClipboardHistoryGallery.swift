import SwiftUI

/// Shared gallery content for the main window and the full-width F3 shelf.
struct ClipboardHistoryGallery: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [ClipboardItem]
    let gridZoom: HistoryGridZoomLevel
    let selectedItemID: UUID?
    let hasQuery: Bool
    var emptyStateHeight: CGFloat?
    let onSelect: (ClipboardItem) -> Void
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
                ClipboardGrid(
                    items: items, gridZoom: gridZoom, selectedItemID: selectedItemID,
                    onSelect: onSelect, onDoubleClick: onDoubleClick, onCopy: onCopy,
                    onPreview: onPreview, onPin: onPin, onDelete: onDelete
                )
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Apply the main window's content styling without changing toolbar glass.
        .buttonStyle(JarvisSecondaryButtonStyle())
        .toggleStyle(SettingsFlatToggleStyle())
        .environment(\.jarvisFlatControls, true)
        .environment(\.jarvisContentButtonShadows, true)
    }
}
