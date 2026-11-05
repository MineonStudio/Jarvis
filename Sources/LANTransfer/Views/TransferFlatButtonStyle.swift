import JarvisDesignSystem
import SwiftUI

/// Solid controls for the file-transfer content area, with shared button elevation.
struct TransferFlatButtonStyle: ButtonStyle {
    var isPrimary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .padding(.horizontal, JarvisSpacing.cardInset)
            .padding(.vertical, JarvisSpacing.controlGap)
            .background(isPrimary ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: Capsule())
            .modifier(JarvisButtonShadowModifier())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.45)
    }
}
