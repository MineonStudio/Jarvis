import AppKit

extension ScreenshotShortcut {
    /// F1 is the default global shortcut for screenshot capture.
    static let `default` = ScreenshotShortcut(
        keyCode: 122, // F1
        modifiers: 0
    )

    /// Previous builds used F2 and then ⌘⇧J for screenshot capture while the
    /// clipboard panel was being introduced. Both built-in values migrate to F1.
    static let legacyDefault = ScreenshotShortcut(
        keyCode: 120, // F2
        modifiers: 0
    )

    static let previousDefault = ScreenshotShortcut(
        keyCode: 38, // J
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )

    static let screenRecordingDefault = ScreenshotShortcut(
        keyCode: 120, // F2
        modifiers: 0
    )

    static let clipboardDefault = ScreenshotShortcut(
        keyCode: 99, // F3
        modifiers: 0
    )

    /// F4 toggles the local meeting recorder.
    static let meetingDefault = ScreenshotShortcut(
        keyCode: 118, // F4
        modifiers: 0
    )
}
