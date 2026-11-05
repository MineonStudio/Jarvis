import Foundation

enum WindowLayoutShortcutPreference {
    static let key = "jarvis.window-layout.shortcut"

    static func load(from defaults: UserDefaults) -> ScreenshotShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data)
        else { return .windowLayoutDefault }
        return shortcut
    }
}

extension AppModel {
    func loadWindowLayoutShortcut() {
        windowLayoutShortcut = WindowLayoutShortcutPreference.load(from: .standard)
    }

    @discardableResult
    func validateWindowLayoutShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        guard let manager = windowLayoutShortcutManager else {
            windowLayoutShortcutConflictMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        windowLayoutShortcutConflictMessage = validation.message
        return validation == .available
    }

    @discardableResult
    func updateWindowLayoutShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        guard let manager = windowLayoutShortcutManager else {
            showToast(JarvisFeedbackCopy.shortcutServiceUnavailable)
            return false
        }
        guard validateWindowLayoutShortcut(shortcut) else { return false }
        guard manager.update(shortcut) else {
            _ = manager.update(windowLayoutShortcut)
            windowLayoutShortcutConflictMessage = "快捷键注册失败，可能与其他应用或系统快捷键冲突"
            return false
        }
        windowLayoutShortcut = shortcut
        windowLayoutShortcutConflictMessage = ""
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: windowLayoutShortcutKey)
        }
        showToast(JarvisFeedbackCopy.shortcutUpdated)
        return true
    }

    /// Release the recording shortcut before resetting the other four, so
    /// custom bindings can exchange default keys without blocking one another.
    @discardableResult
    func restoreFunctionShortcutDefaults() -> Bool {
        guard let screenshotShortcutManager, let clipboardShortcutManager,
              let meetingShortcutManager, let windowLayoutShortcutManager
        else {
            showToast(JarvisFeedbackCopy.shortcutServiceUnavailable)
            return false
        }
        let previous: [(manager: ScreenshotShortcutManager, shortcut: ScreenshotShortcut)] = [
            (screenshotShortcutManager, screenshotShortcut),
            (clipboardShortcutManager, clipboardShortcut),
            (meetingShortcutManager, meetingShortcut),
            (windowLayoutShortcutManager, windowLayoutShortcut)
        ]
        let defaults: [(manager: ScreenshotShortcutManager, shortcut: ScreenshotShortcut)] = [
            (screenshotShortcutManager, .default),
            (clipboardShortcutManager, .clipboardDefault),
            (meetingShortcutManager, .meetingDefault),
            (windowLayoutShortcutManager, .windowLayoutDefault)
        ]
        let previousRecording = screenRecording.shortcuts.bindings[ScreenRecordingShortcutAction.open.rawValue]
        _ = screenRecording.shortcuts.set(nil, for: .open, persist: false)
        guard ScreenshotShortcutManager.updateTogether(defaults) else {
            _ = screenRecording.shortcuts.set(previousRecording, for: .open, persist: false)
            showToast("恢复失败，默认快捷键与其他应用或系统快捷键冲突")
            return false
        }
        guard screenRecording.shortcuts.set(.screenRecordingDefault, for: .open) else {
            _ = ScreenshotShortcutManager.updateTogether(previous)
            _ = screenRecording.shortcuts.set(previousRecording, for: .open, persist: false)
            showToast("恢复失败，默认快捷键与其他应用或系统快捷键冲突")
            return false
        }

        screenshotShortcut = .default
        clipboardShortcut = .clipboardDefault
        meetingShortcut = .meetingDefault
        windowLayoutShortcut = .windowLayoutDefault
        screenshotShortcutConflictMessage = ""
        clipboardShortcutConflictMessage = ""
        meetingShortcutConflictMessage = ""
        windowLayoutShortcutConflictMessage = ""
        screenRecording.shortcuts.error = ""
        for (key, shortcut) in [
            (screenshotShortcutKey, screenshotShortcut),
            (clipboardShortcutKey, clipboardShortcut),
            (meetingShortcutKey, meetingShortcut),
            (windowLayoutShortcutKey, windowLayoutShortcut)
        ] {
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
        showToast("已恢复默认快捷键")
        return true
    }
}
