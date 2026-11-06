import SwiftUI

/// Shadow the card silhouette after clipping its preview and overlays, so text
/// and hover controls do not cast separate shadows or clip the card's shadow.
private struct JarvisGridCardShadowModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.jarvisPanel)
                // A broad, nearly centered blur keeps the corners from reading
                // as a separate outline while retaining elevation on every side.
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 10, y: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func jarvisGridCardShadow(cornerRadius: CGFloat = HistoryGridMetrics.clipboardCornerRadius) -> some View {
        modifier(JarvisGridCardShadowModifier(cornerRadius: cornerRadius))
    }
}
