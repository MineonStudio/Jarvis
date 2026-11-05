import SwiftUI

public extension EnvironmentValues {
    /// Enabled only for controls in the main window's content branch.
    @Entry var jarvisContentButtonShadows = false
}

/// Shared button elevation for the app and file-transfer controls.
/// Panels, toolbar controls, and settings do not inherit this policy.
public struct JarvisButtonShadowModifier: ViewModifier {
    @Environment(\.jarvisContentButtonShadows) private var showsShadow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func body(content: Content) -> some View {
        if showsShadow {
            content.shadow(
                color: .black.opacity((colorScheme == .dark ? 0.24 : 0.12) * (isEnabled ? 1 : 0.35)),
                radius: 6,
                x: 0,
                y: 2
            )
        } else {
            content
        }
    }
}
