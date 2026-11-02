import SwiftUI

/// Shared bottom overlay for screenshot, recording, and clipboard cards.
/// It stays fixed while the preview underneath keeps its hover animation.
private struct HistoryCardMetadataModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: HistoryGridMetrics.clipboardMetadataHeight)
            .padding(.horizontal, JarvisSpacing.rowInset)
            .padding(.top, 24)
            .padding(.bottom, JarvisSpacing.controlGap)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func historyCardMetadata() -> some View {
        modifier(HistoryCardMetadataModifier())
    }
}
