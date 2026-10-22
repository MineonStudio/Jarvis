import SwiftUI

/// Shared colours for the independent Mahjong window and its game overlays.
enum MahjongVisualTheme {
    static let felt = Color(red: 0.045, green: 0.16, blue: 0.13)
    static let rail = Color(red: 0.055, green: 0.12, blue: 0.10)
    static let surface = Color(red: 0.065, green: 0.17, blue: 0.135)
    static let raisedSurface = Color(red: 0.10, green: 0.23, blue: 0.18)
    static let accent = Color(red: 0.93, green: 0.96, blue: 1)
    static let menuHover = Color.white
    static let ivory = Color(red: 0.97, green: 0.94, blue: 0.84)
    static let muted = Color(red: 0.75, green: 0.80, blue: 0.74)
    static let success = Color(red: 0.65, green: 0.81, blue: 0.58)
    static let danger = Color(red: 0.93, green: 0.57, blue: 0.48)
    static let ink = Color(red: 0.16, green: 0.12, blue: 0.075)
}

struct MahjongGameButtonStyle: PrimitiveButtonStyle {
    enum Kind: Equatable { case primary, secondary }

    var kind: Kind = .secondary
    var borderShape: ButtonBorderShape = .capsule
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.system(size: 14, weight: kind == .primary ? .semibold : .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(borderShape)
        .controlSize(.large)
        .tint(nil)
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    func mahjongGamePanel(cornerRadius: CGFloat = 20) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func mahjongGlassGroup(spacing: CGFloat = 10) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}
