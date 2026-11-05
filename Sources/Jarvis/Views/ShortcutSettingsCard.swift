import AppKit
import SwiftUI

struct ShortcutSettingsCard: View {
    @Environment(AppModel.self) private var app
    @State private var screenshotShortcut = ScreenshotShortcut.default
    @State private var screenRecordingShortcut = ScreenshotShortcut.screenRecordingDefault
    @State private var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @State private var meetingShortcut = ScreenshotShortcut.meetingDefault
    @State private var windowLayoutShortcut = ScreenshotShortcut.windowLayoutDefault
    @State private var recordingAction: Action?

    private enum Action {
        case screenshot, screenRecording, clipboard, meeting, windowLayout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.itemGap) {
            HStack(spacing: JarvisSpacing.groupGap) {
                Text("快捷键")
                    .font(SettingsTypography.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("恢复默认") {
                    recordingAction = nil
                    _ = app.restoreFunctionShortcutDefaults()
                    loadShortcuts()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsContentPanel {
                content
            }
        }
        .onAppear {
            loadShortcuts()
            _ = app.validateScreenshotShortcut(screenshotShortcut)
            _ = app.validateClipboardShortcut(clipboardShortcut)
            _ = app.validateMeetingShortcut(meetingShortcut)
            _ = app.validateWindowLayoutShortcut(windowLayoutShortcut)
        }
        .onChange(of: screenshotShortcut) { _, newValue in
            guard recordingAction == .screenshot else { return }
            _ = app.updateScreenshotShortcut(newValue)
        }
        .onChange(of: screenRecordingShortcut) { _, newValue in
            guard recordingAction == .screenRecording else { return }
            _ = app.screenRecording.shortcuts.set(newValue, for: .open)
        }
        .onChange(of: clipboardShortcut) { _, newValue in
            guard recordingAction == .clipboard else { return }
            _ = app.updateClipboardShortcut(newValue)
        }
        .onChange(of: meetingShortcut) { _, newValue in
            guard recordingAction == .meeting else { return }
            _ = app.updateMeetingShortcut(newValue)
        }
        .onChange(of: windowLayoutShortcut) { _, newValue in
            guard recordingAction == .windowLayout else { return }
            _ = app.updateWindowLayoutShortcut(newValue)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            shortcutRow(
                title: "截图",
                shortcut: $screenshotShortcut,
                action: .screenshot,
                conflictMessage: app.screenshotShortcutConflictMessage
            )
            shortcutRow(
                title: "屏幕录制",
                shortcut: $screenRecordingShortcut,
                action: .screenRecording,
                conflictMessage: app.screenRecording.shortcuts.error
            )
            shortcutRow(
                title: "剪贴板",
                shortcut: $clipboardShortcut,
                action: .clipboard,
                conflictMessage: app.clipboardShortcutConflictMessage
            )
            shortcutRow(
                title: "会议录制",
                shortcut: $meetingShortcut,
                action: .meeting,
                conflictMessage: app.meetingShortcutConflictMessage
            )
            shortcutRow(
                title: "窗口布局",
                shortcut: $windowLayoutShortcut,
                action: .windowLayout,
                conflictMessage: app.windowLayoutShortcutConflictMessage
            )
        }
    }

    private func loadShortcuts() {
        screenshotShortcut = app.screenshotShortcut
        screenRecordingShortcut = app.screenRecording.shortcuts.bindings[ScreenRecordingShortcutAction.open.rawValue]
            ?? .screenRecordingDefault
        clipboardShortcut = app.clipboardShortcut
        meetingShortcut = app.meetingShortcut
        windowLayoutShortcut = app.windowLayoutShortcut
    }

    private func shortcutRow(
        title: String,
        shortcut: Binding<ScreenshotShortcut>,
        action: Action,
        conflictMessage: String
    ) -> some View {
        HStack(spacing: JarvisSpacing.groupGap) {
            Text(title)
                .font(SettingsTypography.itemTitle)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            if !conflictMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(conflictMessage)
            }
            ShortcutRecorderControl(
                shortcut: shortcut,
                isRecording: Binding(
                    get: { recordingAction == action },
                    set: { isRecording in
                        if isRecording {
                            recordingAction = action
                        } else if recordingAction == action {
                            recordingAction = nil
                        }
                    }
                )
            )
            .frame(width: 170, height: 32)
            .accessibilityLabel("\(title)快捷键")
        }
    }
}
