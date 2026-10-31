import AppKit
import Observation
import SwiftUI

enum ScreenRecordingShortcutAction: String, CaseIterable, Identifiable {
    case open, stop
    var id: Self {
        self
    }

    var title: String {
        self == .open ? "屏幕录制（开始 / 停止）" : "独立停止屏幕录制（可选）"
    }

    var suggested: ScreenshotShortcut {
        if self == .open {
            return .screenRecordingDefault
        }
        return ScreenshotShortcut(
            keyCode: 1,
            modifiers: NSEvent.ModifierFlags([.command, .option, .shift]).rawValue
        )
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

struct ScreenRecordingShortcutSettings: View {
    let shortcuts: ScreenRecordingShortcuts
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("屏幕录制快捷键").font(.headline)
            Text("默认 F2：打开录制操作栏，点击“录制”开始，录制中按 F2 停止，也可在系统菜单栏停止。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach([ScreenRecordingShortcutAction.open]) { action in
                ScreenRecordingShortcutRow(shortcuts: shortcuts, action: action)
            }
            if !shortcuts.error.isEmpty {
                Text(shortcuts.error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct ScreenRecordingShortcutRow: View {
    let shortcuts: ScreenRecordingShortcuts
    let action: ScreenRecordingShortcutAction
    @State private var draft = ScreenshotShortcut.default
    @State private var editing = false
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                Text(shortcuts.bindings[action.rawValue] == nil ? "未启用" : "已启用")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutRecorderControl(shortcut: $draft, isRecording: $editing).frame(width: 170, height: 32)
            Button("启用") { _ = shortcuts.set(draft, for: action) }.disabled(editing)
            if action == .open {
                Button("恢复默认") {
                    if shortcuts.set(.screenRecordingDefault, for: action) {
                        draft = .screenRecordingDefault
                    }
                }
            }
            Button("清除") { _ = shortcuts.set(nil, for: action) }
                .disabled(shortcuts.bindings[action.rawValue] == nil)
        }
        .onAppear { draft = shortcuts.bindings[action.rawValue] ?? action.suggested }
    }
}
