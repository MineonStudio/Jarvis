import AppKit
import SwiftUI

struct ShortcutSettingsCard: View {
    @Environment(AppModel.self) private var app
    @State private var screenshotShortcut = ScreenshotShortcut.default
    @State private var screenRecordingShortcut = ScreenshotShortcut.screenRecordingDefault
    @State private var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @State private var meetingShortcut = ScreenshotShortcut.meetingDefault
    @State private var isRecordingScreenshotShortcut = false
    @State private var isRecordingScreenRecordingShortcut = false
    @State private var isRecordingClipboardShortcut = false
    @State private var isRecordingMeetingShortcut = false

    var body: some View {
        JarvisCard {
            content
        }
        .onAppear {
            screenshotShortcut = app.screenshotShortcut
            screenRecordingShortcut = app.screenRecording.shortcuts.bindings[ScreenRecordingShortcutAction.open.rawValue]
                ?? .screenRecordingDefault
            clipboardShortcut = app.clipboardShortcut
            meetingShortcut = app.meetingShortcut
            _ = app.validateScreenshotShortcut(screenshotShortcut)
            _ = app.validateClipboardShortcut(clipboardShortcut)
            _ = app.validateMeetingShortcut(meetingShortcut)
        }
        .onChange(of: screenshotShortcut) { _, newValue in
            guard isRecordingScreenshotShortcut else { return }
            if app.validateScreenshotShortcut(newValue) {
                guard newValue != app.screenshotShortcut else { return }
                _ = app.updateScreenshotShortcut(newValue)
            }
        }
        .onChange(of: screenRecordingShortcut) { _, newValue in
            guard isRecordingScreenRecordingShortcut,
                  newValue != app.screenRecording.shortcuts.bindings[ScreenRecordingShortcutAction.open.rawValue]
            else { return }
            _ = app.screenRecording.shortcuts.set(newValue, for: .open)
        }
        .onChange(of: clipboardShortcut) { _, newValue in
            guard isRecordingClipboardShortcut else { return }
            if app.validateClipboardShortcut(newValue) {
                guard newValue != app.clipboardShortcut else { return }
                _ = app.updateClipboardShortcut(newValue)
            }
        }
        .onChange(of: meetingShortcut) { _, newValue in
            guard isRecordingMeetingShortcut else { return }
            if app.validateMeetingShortcut(newValue) {
                guard newValue != app.meetingShortcut else { return }
                _ = app.updateMeetingShortcut(newValue)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            SettingsCardHeader(title: "快捷键", systemImage: "keyboard")

            shortcutRow(
                title: "截图",
                shortcut: $screenshotShortcut,
                isRecording: $isRecordingScreenshotShortcut,
                conflictMessage: app.screenshotShortcutConflictMessage
            ) {
                let previous = screenshotShortcut
                if !app.updateScreenshotShortcut(.default) {
                    screenshotShortcut = previous
                } else {
                    screenshotShortcut = .default
                }
            }

            shortcutRow(
                title: "屏幕录制",
                shortcut: $screenRecordingShortcut,
                isRecording: $isRecordingScreenRecordingShortcut,
                conflictMessage: app.screenRecording.shortcuts.error
            ) {
                if app.screenRecording.shortcuts.set(.screenRecordingDefault, for: .open) {
                    screenRecordingShortcut = .screenRecordingDefault
                }
            }

            shortcutRow(
                title: "剪贴板",
                shortcut: $clipboardShortcut,
                isRecording: $isRecordingClipboardShortcut,
                conflictMessage: app.clipboardShortcutConflictMessage
            ) {
                let previous = clipboardShortcut
                if !app.updateClipboardShortcut(.clipboardDefault) {
                    clipboardShortcut = previous
                } else {
                    clipboardShortcut = .clipboardDefault
                }
            }

            shortcutRow(
                title: "会议录制",
                shortcut: $meetingShortcut,
                isRecording: $isRecordingMeetingShortcut,
                conflictMessage: app.meetingShortcutConflictMessage
            ) {
                let previous = meetingShortcut
                if !app.updateMeetingShortcut(.meetingDefault) {
                    meetingShortcut = previous
                } else {
                    meetingShortcut = .meetingDefault
                }
            }

            HStack(spacing: JarvisSpacing.groupGap) {
                Text("窗口布局")
                    .font(SettingsTypography.itemTitle)
                Spacer(minLength: 8)
                Text(ScreenshotShortcut.windowLayoutDefault.displayString)
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .frame(minHeight: 32)
            .help("按 F5 打开顶部布局面板，点击选择布局；按 Esc 取消。")
        }
    }

    private func shortcutRow(
        title: String,
        shortcut: Binding<ScreenshotShortcut>,
        isRecording: Binding<Bool>,
        conflictMessage: String,
        onRestore: @escaping () -> Void
    ) -> some View {
        HStack(spacing: JarvisSpacing.groupGap) {
            Text(title)
                .font(SettingsTypography.itemTitle)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            ShortcutRecorderControl(
                shortcut: shortcut,
                isRecording: isRecording
            )
            .frame(width: 170, height: 32)
            if !conflictMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(conflictMessage)
            }
            Button("恢复默认", action: onRestore)
                .buttonStyle(JarvisSecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
