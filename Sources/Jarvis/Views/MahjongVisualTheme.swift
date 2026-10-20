import SwiftUI

/// Shared colours for the independent Mahjong window and its game overlays.
enum MahjongVisualTheme {
    static let felt = Color(red: 0.045, green: 0.16, blue: 0.13)
    static let rail = Color(red: 0.055, green: 0.12, blue: 0.10)
    static let surface = Color(red: 0.065, green: 0.17, blue: 0.135)
    static let raisedSurface = Color(red: 0.10, green: 0.23, blue: 0.18)
    static let gold = Color(red: 0.91, green: 0.73, blue: 0.40)
    static let goldHover = Color(red: 1.0, green: 0.83, blue: 0.48)
    static let ivory = Color(red: 0.97, green: 0.94, blue: 0.84)
    static let muted = Color(red: 0.75, green: 0.80, blue: 0.74)
    static let success = Color(red: 0.65, green: 0.81, blue: 0.58)
    static let danger = Color(red: 0.93, green: 0.57, blue: 0.48)
    static let ink = Color(red: 0.16, green: 0.12, blue: 0.075)
}

struct MahjongGameButtonStyle: ButtonStyle {
    enum Kind: Equatable { case primary, secondary }

    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(kind == .primary ? MahjongVisualTheme.ink : MahjongVisualTheme.ivory)
            .padding(.horizontal, 18)
            .frame(minHeight: 38)
            .background(
                kind == .primary ? MahjongVisualTheme.gold : MahjongVisualTheme.raisedSurface,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(kind == .primary ? .clear : MahjongVisualTheme.gold.opacity(0.4), lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension View {
    func mahjongGamePanel(cornerRadius: CGFloat = 20) -> some View {
        background(MahjongVisualTheme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(MahjongVisualTheme.gold.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 20, y: 10)
    }
}
