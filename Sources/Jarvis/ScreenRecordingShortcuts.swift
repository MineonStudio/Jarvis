import AppKit
import Observation

enum ScreenRecordingShortcutAction: String, CaseIterable, Identifiable {
    case open, stop
    var id: Self {
        self
    }

    var hotKeyID: UInt32 {
        self == .open ? 30 : 31
    }
}

@MainActor
@Observable
final class ScreenRecordingShortcuts {
    var bindings: [String: ScreenshotShortcut] = [:]
    var error = ""
    @ObservationIgnored private var managers: [ScreenRecordingShortcutAction: ScreenshotShortcutManager] = [:]
    @ObservationIgnored var onAction: ((ScreenRecordingShortcutAction) -> Void)?

    func install() {
        guard let data = UserDefaults.standard.data(forKey: "jarvis.screen-recording.shortcuts"),
              let saved = try? JSONDecoder().decode([String: ScreenshotShortcut].self, from: data) else { return }
        for action in [ScreenRecordingShortcutAction.open] {
            if let shortcut = saved[action.rawValue] {
                _ = set(shortcut, for: action, persist: false)
            }
        }
    }

    @discardableResult
    func set(_ shortcut: ScreenshotShortcut?, for action: ScreenRecordingShortcutAction, persist: Bool = true) -> Bool {
        guard let shortcut else {
            managers[action] = nil
            bindings[action.rawValue] = nil
            if persist {
                save()
            }
            return true
        }
        let validation = managers[action]?.validate(shortcut)
            ?? ScreenshotShortcutManager.availability(of: shortcut, probeID: action.hotKeyID + 1000)
        guard validation == .available else { error = validation.message; return false }
        if let manager = managers[action] {
            let previous = bindings[action.rawValue]
            guard manager.update(shortcut) else {
                if let previous {
                    _ = manager.update(previous)
                }
                error = "快捷键注册失败，请换一个组合键。"; return false
            }
        } else {
            let manager = ScreenshotShortcutManager(binding: shortcut, hotKeyID: action.hotKeyID) { [weak self] in
                self?.onAction?(action)
            }
            guard manager.isRegistered else { error = "快捷键注册失败，请换一个组合键。"; return false }
            managers[action] = manager
        }
        bindings[action.rawValue] = shortcut
        error = ""
        if persist {
            save()
        }
        return true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: "jarvis.screen-recording.shortcuts")
        }
    }
}
