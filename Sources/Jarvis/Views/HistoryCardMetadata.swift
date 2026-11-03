import SwiftUI

/// Shared bottom overlay for screenshot, recording, clipboard, and resume cards.
/// It stays fixed while the preview underneath keeps its hover animation.
private struct HistoryCardMetadataModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: HistoryGridMetrics.clipboardMetadataHeight)
            .padding(.horizontal, JarvisSpacing.rowInset)
            .padding(.top, 56)
            .padding(.bottom, JarvisSpacing.controlGap)
            .background {
                LinearGradient(
                    // Ease into the scrim over a wider area so its upper edge
                    // blends into bright previews without a visible band.
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.015), location: 0.15),
                        .init(color: .black.opacity(0.06), location: 0.30),
                        .init(color: .black.opacity(0.16), location: 0.45),
                        .init(color: .black.opacity(0.31), location: 0.60),
                        .init(color: .black.opacity(0.49), location: 0.75),
                        .init(color: .black.opacity(0.65), location: 0.90),
                        .init(color: .black.opacity(0.72), location: 1)
                    ],
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
