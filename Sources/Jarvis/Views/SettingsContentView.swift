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
            WindowDragLayoutSettingsCard()
            ScreenshotLanguagePackSettingsCard()
            permissionSettingsCard
        case .appearance:
            themeSettingsCard
            accentColorSettingsCard
        case .wallpaperSources:
            WallpaperSourcesSettingsCard()
        case .shortcuts:
            ShortcutSettingsCard()
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
            automaticUpdatesSettingsCard
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

    private var automaticUpdatesSettingsCard: some View {
        JarvisCard {
            HStack(spacing: JarvisSpacing.groupGap) {
                SettingsCardHeader(title: "自动更新", systemImage: "arrow.clockwise")
                Spacer(minLength: 8)
                Toggle("自动更新", isOn: Binding(
                    get: { app.automaticUpdatesEnabled },
                    set: { app.updateAutomaticUpdatesEnabled($0) }
                ))
                .labelsHidden()
                .jarvisSwitchAccent()
                .animation(
                    JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                    value: app.automaticUpdatesEnabled
                )
                .help("自动检查新版本，发现更新时提醒，由你选择更新时间")
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
