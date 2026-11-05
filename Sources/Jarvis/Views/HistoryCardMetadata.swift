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
                    // Keep a soft fade for every grid's metadata. The bottom
                    // caps at 48% black so the preview remains visible.
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.01), location: 0.15),
                        .init(color: .black.opacity(0.04), location: 0.30),
                        .init(color: .black.opacity(0.10), location: 0.45),
                        .init(color: .black.opacity(0.20), location: 0.60),
                        .init(color: .black.opacity(0.32), location: 0.75),
                        .init(color: .black.opacity(0.43), location: 0.90),
                        .init(color: .black.opacity(0.48), location: 1)
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
