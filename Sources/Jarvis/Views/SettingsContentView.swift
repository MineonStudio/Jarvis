import AppKit
import SwiftUI

enum SettingsLayout {
    static let contentMaxWidth: CGFloat = 760
    static let defaultWindowSize = CGSize(width: 1040, height: 680)
    static let minimumWindowSize = CGSize(width: 728, height: 520)
}

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case appearance
    case wallpaperSources
    case shortcuts
    case model
    case privacyCache
    case diagnostics
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "常规"
        case .privacyCache: "隐私与缓存"
        case .appearance: "外观"
        case .wallpaperSources: "壁纸源"
        case .shortcuts: "快捷键"
        case .model: "模型"
        case .diagnostics: "诊断"
        case .about: "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .privacyCache: "lock.shield"
        case .appearance: "paintbrush"
        case .wallpaperSources: "photo.stack"
        case .shortcuts: "keyboard"
        case .model: "cube"
        case .diagnostics: "waveform.path.ecg"
        case .about: "info.circle"
        }
    }
}

enum SettingsTypography {
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let itemTitle = Font.system(size: 13, weight: .semibold)
    static let itemSubtitle = Font.system(size: 12)
}

enum SettingsFormMetrics {
    static let cardContentSpacing = JarvisSpacing.groupGap
    static let sectionSpacing = JarvisSpacing.groupGap
    static let labelSpacing = JarvisSpacing.controlGap
    static let controlHeight: CGFloat = 34
    static let disabledControlOpacity = 0.82
}

struct SettingsCardHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: JarvisSpacing.controlGap) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 22, height: 22)
            Text(title)
                .font(SettingsTypography.cardTitle)
        }
    }
}

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

struct WindowLayoutShortcutSettingsCard: View {
    var body: some View {
        JarvisCard {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            SettingsCardHeader(
                title: "窗口布局快捷键",
                systemImage: "macwindow.on.rectangle"
            )

            ForEach(WindowLayout.allCases, id: \.self) { layout in
                WindowLayoutShortcutRow(layout: layout)
            }
        }
    }
}

private struct WindowLayoutShortcutRow: View {
    @Environment(AppModel.self) private var app

    let layout: WindowLayout

    @State private var shortcut = ScreenshotShortcut.default
    @State private var isRecording = false
    @State private var conflictMessage = ""

    var body: some View {
        HStack(spacing: JarvisSpacing.groupGap) {
            Text(layout.title)
                .font(SettingsTypography.itemTitle)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            ShortcutRecorderControl(
                shortcut: $shortcut,
                isRecording: $isRecording
            )
            .frame(width: 170, height: 32)
            if !conflictMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(conflictMessage)
            }
            Button("恢复默认", action: restoreDefault)
                .buttonStyle(JarvisSecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
        }
        .onAppear {
            shortcut = app.windowLayoutShortcut(for: layout)
            conflictMessage = validationMessage(for: shortcut)
        }
        .onChange(of: shortcut) { _, newValue in
            guard isRecording else { return }
            let validation = app.validateWindowLayoutShortcut(layout, newValue)
            conflictMessage = validation == .available ? "" : validation.message
            guard validation == .available else { return }
            guard newValue != app.windowLayoutShortcut(for: layout) else { return }
            guard app.updateWindowLayoutShortcut(layout, newValue) else {
                shortcut = app.windowLayoutShortcut(for: layout)
                conflictMessage = validationMessage(for: shortcut)
                return
            }
        }
    }

    private func restoreDefault() {
        let defaultShortcut = layout.defaultShortcut
        guard app.updateWindowLayoutShortcut(layout, defaultShortcut) else {
            shortcut = app.windowLayoutShortcut(for: layout)
            conflictMessage = validationMessage(for: shortcut)
            return
        }
        shortcut = defaultShortcut
        conflictMessage = ""
    }

    private func validationMessage(for shortcut: ScreenshotShortcut) -> String {
        let validation = app.validateWindowLayoutShortcut(layout, shortcut)
        return validation == .available ? "" : validation.message
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SettingsSection = .general
    @State private var isClearPermissionsConfirmationPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            JarvisSidebarNavigation(
                topItems: SettingsSection.allCases,
                selection: $selection,
                title: { $0.title },
                icon: { $0.icon },
                showsHeader: false
            )
            .background(Color.jarvisBackground)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(
                min: JarvisMetrics.sidebarMinimumWidth,
                ideal: JarvisMetrics.sidebarWidth,
                max: JarvisMetrics.sidebarMaximumWidth
            )
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: JarvisSpacing.sectionGap) {
                    Text(selection.title)
                        .font(SettingsTypography.pageTitle)
                        .foregroundStyle(.primary)

                    detailContent
                }
                .frame(maxWidth: SettingsLayout.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(JarvisMetrics.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.jarvisBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .general:
            launchAtLoginSettingsCard
            ScreenshotLanguagePackSettingsCard()
            permissionSettingsCard
        case .appearance:
            themeSettingsCard
            accentColorSettingsCard
        case .wallpaperSources:
            WallpaperSourcesSettingsCard()
        case .shortcuts:
            ShortcutSettingsCard()
            WindowLayoutShortcutSettingsCard()
        case .model:
            AIAPISettingsCard()
            MeetingModelSettingsCard()
        case .privacyCache:
            ClipboardPrivacySettingsCard()
            ClipboardCacheSettingsCard()
        case .diagnostics:
            DiagnosticsSettingsCard()
        case .about:
            versionAndUpdateCard
            sourceRepositoryCard
        }
    }

    private var versionAndUpdateCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                SettingsCardHeader(
                    title: "版本与更新",
                    systemImage: "arrow.triangle.2.circlepath"
                )

                HStack(alignment: .center, spacing: JarvisSpacing.groupGap) {
                    versionStatusLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                    updateActionButton
                }
            }
        }
    }

    /// 平时显示版本号。检查有了结果之后，结果占同一位置，版本号让开。
    private var versionStatusLine: some View {
        ZStack(alignment: .leading) {
            if let status = updateStatusText {
                Text(status)
                    .font(SettingsTypography.itemSubtitle)
                    .foregroundStyle(updateStatusColor)
                    .lineLimit(updateStatusWraps ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: updateStatusWraps)
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            } else {
                Text("Jarvis V\(JarvisAppVersion.shortVersion)")
                    .font(SettingsTypography.itemSubtitle)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: updateStatusText
        )
    }

    private var updateStatusText: String? {
        switch app.updateState {
        case .idle, .checking:
            nil
        case .upToDate:
            JarvisFeedbackCopy.latestVersion
        case let .available(release):
            "\(JarvisFeedbackCopy.updateAvailable) \(displayVersion(release.version))"
        case let .downloading(version):
            "正在下载 \(displayVersion(version))"
        case let .readyToInstall(version):
            "准备安装 \(displayVersion(version))"
        case let .installing(version):
            "正在安装 \(displayVersion(version))"
        case let .failed(message):
            message
        }
    }

    private var updateStatusColor: Color {
        if case .available = app.updateState {
            Color.jarvisAccent
        } else {
            Color.jarvisTextSecondary
        }
    }

    private var updateStatusWraps: Bool {
        if case .failed = app.updateState {
            true
        } else {
            false
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch app.updateState {
        case .checking:
            Button("检查中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case let .available(release):
            Button("下载新版本") {
                app.downloadAndInstallUpdate()
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
            .accessibilityLabel("下载新版本 \(displayVersion(release.version))")
        case .downloading:
            Button("下载中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case .installing, .readyToInstall:
            Button("安装中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case .failed:
            Button("重试") {
                app.checkForUpdates()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        case .idle, .upToDate:
            Button("检查更新") {
                app.checkForUpdates()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }

    private func displayVersion(_ version: String) -> String {
        version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }

    private var themeSettingsCard: some View {
        JarvisCard {
            HStack(spacing: JarvisSpacing.groupGap) {
                SettingsCardHeader(title: "主题", systemImage: "circle.lefthalf.filled")
                Spacer(minLength: 8)
                JarvisThemePicker(selection: Binding(
                    get: { app.themePreference },
                    set: { app.updateThemePreference($0) }
                ))
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var accentColorSettingsCard: some View {
        JarvisCard {
            HStack(spacing: JarvisSpacing.groupGap) {
                SettingsCardHeader(title: "强调色", systemImage: "paintpalette")
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                JarvisAccentColorPicker(selection: Binding(
                    get: { app.accentColorPreference },
                    set: { app.updateAccentColorPreference($0) }
                ))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var launchAtLoginSettingsCard: some View {
        JarvisCard {
            HStack(spacing: JarvisSpacing.groupGap) {
                SettingsCardHeader(title: "开机自启", systemImage: "power")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { app.launchAtLoginEnabled },
                    set: { app.updateLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .jarvisSwitchAccent()
                .animation(
                    JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                    value: app.launchAtLoginEnabled
                )
            }
        }
    }

    private var sourceRepositoryCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                SettingsCardHeader(
                    title: "开源仓库",
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
                HStack(spacing: JarvisSpacing.groupGap) {
                    Text("github.com/MineonStudio/Jarvis")
                        .font(JarvisTypography.monospacedSmall)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Button {
                        guard let url = URL(string: "https://github.com/MineonStudio/Jarvis") else {
                            return
                        }
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("前往GitHub")
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var permissionSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: JarvisSpacing.itemGap) {
                HStack(spacing: JarvisSpacing.groupGap) {
                    SettingsCardHeader(title: "权限", systemImage: "lock.shield")
                    Spacer(minLength: 8)
                    Button("清除所有权限") {
                        isClearPermissionsConfirmationPresented = true
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                }
                JarvisPermissionList(cornerRadius: 12, mode: .settings)
            }
        }
        .confirmationDialog(
            "清除所有权限？",
            isPresented: $isClearPermissionsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("确认并重启", role: .destructive) {
                app.clearAllPrivacyPermissionsAndRestart()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除屏幕录制、辅助功能、麦克风和摄像头授权，然后重新打开工作搭子 Jarvis。")
        }
    }
}

struct DiagnosticsSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            HStack(spacing: JarvisSpacing.groupGap) {
                SettingsCardHeader(title: "诊断日志", systemImage: "waveform.path.ecg")
                Spacer(minLength: 8)
                Button("导出日志") {
                    app.exportDiagnostics()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
    }
}

struct MeetingModelSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            content
        }
        .onAppear {
            app.refreshMeetingModelState()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.sectionSpacing) {
            SettingsCardHeader(title: "会议识别模型", systemImage: "waveform.and.person.filled")

            ForEach(MeetingModelPreparationStage.allCases) { stage in
                MeetingModelSettingsRow(stage: stage)
            }

            if case let .failed(nil, _, message) = app.meetingModelState {
                Text(message)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct MeetingModelSettingsRow: View {
    @Environment(AppModel.self) private var app
    let stage: MeetingModelPreparationStage

    private var isReady: Bool {
        app.meetingModelAvailability.isReady(for: stage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.controlGap) {
            HStack(alignment: .center, spacing: JarvisSpacing.itemGap) {
                VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                    Text(stage.title)
                        .font(SettingsTypography.itemTitle)
                    Text(stage.modelName)
                        .font(JarvisTypography.monospacedSmall)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)
                action
                    .fixedSize(horizontal: true, vertical: false)
            }

            if case let .downloading(activeStage, progress) = app.meetingModelState,
               activeStage == stage
            {
                HStack(spacing: JarvisSpacing.controlGap) {
                    ProgressView(value: progress)
                        .tint(Color.jarvisAccent)
                    Text("下载中 · \(Int(progress * 100))%")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }

            if case let .failed(failedStage, operation, message) = app.meetingModelState,
               failedStage == stage
            {
                Text("\(operation == .remove ? "移除失败" : "下载失败")：\(message)")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, JarvisSpacing.controlGap)
    }

    @ViewBuilder
    private var action: some View {
        switch app.meetingModelState {
        case .checking:
            Button("检查中") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case let .downloading(activeStage, _):
            if activeStage == stage {
                Button("取消") { app.cancelMeetingModelPreparation() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            } else {
                availabilityAction
            }
        case let .removing(activeStage):
            if activeStage == stage {
                HStack(spacing: JarvisSpacing.iconGap) {
                    ProgressView().controlSize(.small)
                    Text("移除中")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            } else {
                availabilityAction
            }
        case let .failed(failedStage, operation, _) where failedStage == stage:
            if operation == .remove {
                Button("重试移除", role: .destructive) {
                    app.removeMeetingModel(stage)
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
                .disabled(!app.canManageMeetingModels)
            } else {
                Button("重试下载") {
                    app.prepareMeetingModel(stage)
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .disabled(!app.canManageMeetingModels)
            }
        default:
            availabilityAction
        }
    }

    @ViewBuilder
    private var availabilityAction: some View {
        if isReady {
            if stage == .chineseTranscription {
                Text("系统已安装")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
            } else {
                Button("移除", role: .destructive) {
                    app.removeMeetingModel(stage)
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
                .disabled(!app.canManageMeetingModels)
                .help("移除本机下载的 \(stage.title) 模型")
            }
        } else {
            Button("下载") {
                app.prepareMeetingModel(stage)
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
            .disabled(!app.canManageMeetingModels)
        }
    }
}

struct JarvisThemePicker: View {
    @Binding var selection: JarvisTheme

    var body: some View {
        JarvisSegmentedControl(items: Array(JarvisTheme.allCases), selection: $selection) { theme, isSelected in
            Text(theme.title)
                .font(JarvisTypography.controlEmphasis)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(
                    minWidth: 54,
                    minHeight: JarvisMetrics.segmentedItemHeight,
                    maxHeight: JarvisMetrics.segmentedItemHeight
                )
                .padding(.horizontal, JarvisSpacing.controlGap)
                .padding(.vertical, JarvisMetrics.segmentedItemVerticalPadding)
                .contentShape(Capsule())
        }
    }
}

struct JarvisAccentColorPicker: View {
    @Binding var selection: JarvisAccentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredAccent: JarvisAccentColor?

    /// 色块中心距。截图里九颗圆按 36pt 排开，不随卡片变宽被拉开。
    private static let pitch: CGFloat = 36
    /// 跟上面应用图标那条分段控件一样高，色块在这行里垂直居中。
    private static var controlHeight: CGFloat {
        JarvisMetrics.segmentedItemHeight
            + JarvisMetrics.segmentedItemVerticalPadding * 2
            + JarvisMetrics.segmentedControlPadding * 2
    }

    private var accents: [JarvisAccentColor] {
        Array(JarvisAccentColor.allCases)
    }

    var body: some View {
        GeometryReader { proxy in
            let pitch = fittedPitch(in: proxy.size.width)
            HStack(spacing: 0) {
                ForEach(accents) { accent in
                    accentTab(accent, pitch: pitch)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: Self.controlHeight)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: selection
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: hoveredAccent
        )
    }

    /// 宽够用时保持 36pt。标题必须留在一行里，窄的时候只把色块间距收回去。
    private func fittedPitch(in available: CGFloat) -> CGFloat {
        let count = CGFloat(accents.count)
        guard available > 1 else { return Self.pitch }
        return min(Self.pitch, max(AccentColorSwatch.slot, available / count))
    }

    private func accentTab(_ accent: JarvisAccentColor, pitch: CGFloat) -> some View {
        let isSelected = selection == accent
        return Button {
            selection = accent
        } label: {
            AccentColorSwatch(accent: accent, isSelected: isSelected)
                .overlay(alignment: .top) {
                    Text(accent.title)
                        .font(JarvisTypography.caption)
                        // 系统设置里这行名称大约是 42% 的黑，比 secondary 更浅。
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(y: AccentColorSwatch.slot + 2)
                        .opacity(hoveredAccent == accent ? 1 : 0)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.9))
        .frame(width: pitch, height: Self.controlHeight)
        .accessibilityLabel("强调色：\(accent.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering in
            if isHovering {
                hoveredAccent = accent
            } else if hoveredAccent == accent {
                hoveredAccent = nil
            }
        }
    }
}

/// 未选中是一颗实心圆。选中时圆的大小不变，外面加一圈同色环，环和圆之间露出底色。
/// 跟随系统不是单一颜色，用色轮表示。
private struct AccentColorSwatch: View {
    let accent: JarvisAccentColor
    var isSelected: Bool

    static let diameter: CGFloat = 24
    static let ringLineWidth: CGFloat = 2
    static let ringGap: CGFloat = 2
    static var slot: CGFloat {
        diameter + (ringLineWidth + ringGap) * 2
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ringColor, lineWidth: Self.ringLineWidth)
                .opacity(isSelected ? 1 : 0)
            Circle()
                .fill(fill)
                .padding(Self.ringLineWidth + Self.ringGap)
        }
        .frame(width: Self.slot, height: Self.slot)
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        if accent == .system {
            AnyShapeStyle(Self.wheel)
        } else {
            AnyShapeStyle(accent.color)
        }
    }

    private var ringColor: Color {
        if accent == .system {
            Color(nsColor: .controlAccentColor)
        } else {
            accent.color
        }
    }

    private static let wheel = AngularGradient(
        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
        center: .center
    )
}

struct JarvisToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(JarvisTypography.captionEmphasis)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, JarvisSpacing.cardInset)
            .padding(.vertical, JarvisSpacing.rowInset)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.15), radius: 14, y: 6)
            .frame(maxWidth: 520)
    }
}
