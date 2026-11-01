import AppKit

/// Floating capture windows live outside the main SwiftUI scene. Apply the
/// app's appearance at the window so both SwiftUI and native controls inherit it.
@MainActor
final class CaptureToolbarAppearance {
    static let shared = CaptureToolbarAppearance()

    private var preference: JarvisTheme = .system
    private let windows = NSHashTable<NSWindow>.weakObjects()

    func register(_ window: NSWindow) {
        windows.add(window)
        window.appearance = appearance
    }

    func update(_ preference: JarvisTheme) {
        self.preference = preference
        for window in windows.allObjects {
            window.appearance = appearance
        }
    }

    private var appearance: NSAppearance? {
        switch preference {
        case .system: nil // Let AppKit track system appearance changes live.
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
