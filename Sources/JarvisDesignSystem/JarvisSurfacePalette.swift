import AppKit
import SwiftUI

/// Shared by the app and the separately compiled LAN transfer module.
public enum JarvisSurfacePalette {
    /// A dynamic native color keeps AppKit window chrome and SwiftUI roots in sync.
    public static let windowBackgroundColor = windowBackgroundColor(light: .textBackgroundColor)

    public static func windowBackgroundColor(light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                let channel = 24.0 / 255
                return NSColor(srgbRed: channel, green: channel, blue: channel, alpha: 1)
            }
            return light
        }
    }

    public static func panelFill(for colorScheme: ColorScheme) -> Color {
        let channel = colorScheme == .dark ? 32.0 / 255 : 249.0 / 255
        return Color(.sRGB, red: channel, green: channel, blue: channel, opacity: 1)
    }
}

public struct JarvisPanelBackgroundModifier: ViewModifier {
    private let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.background(
            JarvisSurfacePalette.panelFill(for: colorScheme),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
