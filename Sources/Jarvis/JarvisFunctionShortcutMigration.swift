import Foundation

/// Run before any global shortcuts are registered, so F2/F3 are freed before reassignment.
enum JarvisFunctionShortcutMigration {
    static let migrationKey = "jarvis.shortcuts.function-keys-v2.migrated"
    static let recordingKey = "jarvis.screen-recording.shortcuts"

    static func apply(to defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let encoder = JSONEncoder()
        let mainBindings: [(String, ScreenshotShortcut)] = [
            ("jarvis.screenshot.shortcut", .default),
            ("jarvis.clipboard.shortcut", .clipboardDefault),
            ("jarvis.meeting.shortcut", .meetingDefault)
        ]
        var recording: [String: ScreenshotShortcut] = [:]
        if let data = defaults.data(forKey: recordingKey) {
            if let saved = try? JSONDecoder().decode([String: ScreenshotShortcut].self, from: data) {
                recording = saved
            } else {
                defaults.set(data, forKey: recordingKey + ".before-function-keys-v2")
            }
        }
        recording["open"] = .screenRecordingDefault
        // A former optional stop key must not also trigger one of the four primary actions.
        let reserved: [ScreenshotShortcut] = [.default, .screenRecordingDefault, .clipboardDefault, .meetingDefault]
        if let stop = recording["stop"], reserved.contains(stop) {
            recording["stop"] = nil
        }
        do {
            let encodedMain = try mainBindings.map { try ($0.0, encoder.encode($0.1)) }
            let encodedRecording = try encoder.encode(recording)
            for (key, data) in encodedMain {
                defaults.set(data, forKey: key)
            }
            defaults.set(encodedRecording, forKey: recordingKey)
            defaults.set(true, forKey: "jarvis.screenshot.shortcut.f1.migrated")
            defaults.set(true, forKey: migrationKey)
        } catch {
            JarvisLog.error(category: .shortcut, event: "shortcuts.functionKeys.migration.failed", error: error)
        }
    }
}
