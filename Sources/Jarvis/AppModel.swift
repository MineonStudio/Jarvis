import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: Hashable, Identifiable {
    case home
    case aiConversation
    case entertainment
    case gamePlaza
    case skill(SkillID)

    var id: String {
        switch self {
        case .home: "home"
        case .aiConversation: "ai-conversation"
        case .entertainment: "entertainment"
        case .gamePlaza: "game-plaza"
        case let .skill(skill): "skill.\(skill.id)"
        }
    }

    var title: String {
        switch self {
        case .home: "首页"
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        case .gamePlaza: "游戏广场"
        case let .skill(skill): skill.title
        }
    }

    var navigationTitle: String {
        switch self {
        case .home: "首页"
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        case .gamePlaza: "游戏广场"
        case .skill(.screenshot): "截图"
        case .skill(.screenRecording): "屏幕录制"
        case .skill(.clipboard): "剪贴板"
        case .skill(.windowLayout): "窗口布局"
        case .skill(.resume): "简历制作"
        case .skill(.wallpaper): "桌面壁纸"
        case .skill(.meetingNotes): "会议记录"
        case .skill(.lanTransfer): "局域网传输"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .aiConversation: "sparkles"
        case .entertainment: "play.rectangle"
        case .gamePlaza: "gamecontroller"
        case let .skill(skill): skill.icon
        }
    }

    var skill: SkillID? {
        if case let .skill(skill) = self {
            return skill
        }
        return nil
    }
}

@MainActor
@Observable
final class AppModel {
    var selectedSection: AppSection = .home
    var screenRecording = ScreenRecordingCoordinator()
    var clipboardItems: [ClipboardItem] = []
    var latestScreenshotData: Data?
    var screenshotHistory: [ScreenshotHistoryItem] = []
    var isCapturing = false
    var statusMessage = "系统就绪"
    var toastMessage: String?
    var screenshotShortcut = ScreenshotShortcut.default
    var screenshotShortcutConflictMessage = ""
    var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    var clipboardShortcutConflictMessage = ""
    var meetingShortcut = ScreenshotShortcut.meetingDefault
    var meetingShortcutConflictMessage = ""
    var windowDragLayoutEnabled = WindowDragLayoutPreference.load(from: .standard)
    var themePreference: JarvisTheme = .system
    var accentColorPreference: JarvisAccentColor = .system
    var systemColorScheme: ColorScheme = .light
    var activeColorScheme: ColorScheme {
        themePreference.resolvedColorScheme(system: systemColorScheme)
    }

    var updateState: JarvisUpdateState = .idle
    var automaticUpdatesEnabled = JarvisAutomaticUpdatePreference.defaultValue
    var selectedAIProvider: AIConversationProvider = .deepSeek
    var selectedEntertainmentPlatform: EntertainmentPlatform = .x
    var apiProvider: AIAPIProvider = .openAI
    var providerEndpoint = AIAPIConfiguration.defaultEndpoint
    var providerModel = AIAPIConfiguration.defaultModel
    var availableAIModels: [String] = []
    var aiModelsLoading = false
    var aiModelsRefreshError: String?
    var aiAPIKeyConfigured = false
    var aiAPIKeyMask = ""
    var aiSettingsLocked = false
    var aiConnectionTesting = false
    var aiConnectionTestError: String?
    var meetingRecords: [MeetingRecord] = []
    var selectedMeetingID: UUID?
    var meetingProcessingState: MeetingProcessingState = .idle
    /// Minutes still arriving from the model, keyed by meeting. Kept out of the records so
    /// a preview is never stored, exported or searched before the finished answer lands.
    var meetingLiveSummaries: [UUID: MeetingSummary] = [:]
    var meetingElapsed: TimeInterval = 0
    var meetingElapsedOrigin = Date()
    var meetingElapsedAccumulated: TimeInterval = 0
    var meetingTranscriptConsentRecordID: UUID?
    var meetingRecoverySnapshotBucket = -1
    var meetingSystemSilentSince: Date?
    var meetingDidWarnAboutSystemSilence = false
    var meetingRecordingPaused = false
    var meetingSystemPower: Float?
    /// Recent input levels, newest last, for the live meter. Sampled far faster than the
    /// once-a-second bookkeeping because the drawing has to move.
    var meetingLevelHistory: [Double] = []
    /// Bumped whenever a meeting's mixed recording is written again over the old one. The
    /// path does not change, so this is how a player already open learns to reload.
    var meetingAudioRevisions: [UUID: Int] = [:]
    var meetingBytesWritten: Int64 = 0
    var meetingModelDownloadCompletedBytes: Int64 = 0
    var meetingModelDownloadTotalBytes: Int64 = 0
    var meetingModelState: MeetingModelPreparationState = .checking
    var meetingModelAvailability = MeetingModelAvailability(
        speakerDiarizationReady: false,
        chineseTranscriptionReady: false
    )
    var canManageMeetingModels: Bool {
        guard meetingModelPreparationTask == nil,
              meetingCurrentRecordingID == nil,
              !isStartingMeetingRecording
        else {
            return false
        }
        switch meetingProcessingState {
        case .recording, .processing:
            return false
        default:
            return true
        }
    }

    var meetingStorageError: String?
    var screenCapturePermissionGranted = false
    var accessibilityPermissionGranted = false
    var microphonePermissionGranted = false
    var onboarding = JarvisOnboardingState()
    var launchAtLoginEnabled = JarvisLaunchAtLoginPreference.defaultValue
    var clipboardCacheDirectoryURL: URL
    var clipboardCacheMaximumBytes: Int64
    var clipboardCacheAutoCleanupEnabled = false
    var clipboardCacheAutoCleanupPeriod: ClipboardCacheCleanupPeriod = .never
    var automaticClipboardRecordingEnabled = true
    var hideSensitiveClipboardContent = true
    var taskPermissionPrompt: JarvisTaskPermissionPrompt?
    var clipboardCacheUsage = ClipboardCacheUsage(
        usedBytes: 0,
        capacityBytes: ClipboardCacheStore.defaultMaximumBytes,
        fileCount: 0
    )

    @ObservationIgnored let clipboardCacheStore: ClipboardCacheStore
    @ObservationIgnored let clipboardService: ClipboardService
    @ObservationIgnored lazy var clipboardStore = ClipboardStore()
    @ObservationIgnored lazy var clipboardHistoryWriter = ClipboardHistoryWriter(store: clipboardStore)
    @ObservationIgnored lazy var startupRepository = JarvisStartupRepository()
    @ObservationIgnored let clipboardPanelController = ClipboardPanelController()
    @ObservationIgnored let settingsPanelController = SettingsPanelController()
    @ObservationIgnored lazy var screenshotCacheStore = ScreenshotCacheStore()
    @ObservationIgnored lazy var screenshotHistoryStore = ScreenshotHistoryStore()
    @ObservationIgnored let screenshotController = ScreenshotCaptureController()
    @ObservationIgnored let screenshotHistoryPreviewController = ScreenshotHistoryPreviewController()
    @ObservationIgnored let clipboardMediaPreviewController = ClipboardMediaPreviewController()
    @ObservationIgnored let updateService = JarvisUpdateService()
    @ObservationIgnored let updatePromptController = JarvisUpdatePromptController()
    @ObservationIgnored var automaticUpdateTask: Task<Void, Never>?
    @ObservationIgnored var lastPromptedUpdate: JarvisReleaseInfo?
    var shouldRelaunchAfterTermination = false
    @ObservationIgnored let meetingRepository: MeetingRepository
    @ObservationIgnored let meetingRecorder: MeetingRecorder
    @ObservationIgnored let meetingTranscriptionService: any MeetingTranscribing
    @ObservationIgnored let aiTextCompletionAPI: any AITextCompletionAPI
    @ObservationIgnored let resumeWorkspace = ResumeWorkspace()
    @ObservationIgnored let launchAtLoginService = JarvisLaunchAtLoginService.shared
    @ObservationIgnored let aiAPIConnectionTester: any AIAPIConnectionTesting
    @ObservationIgnored private var aiConversationControllers: [AIConversationProvider: JarvisWebPlatformController] = [:]
    @ObservationIgnored private(set) var entertainmentControllers: [EntertainmentPlatform: JarvisWebPlatformController] = [:]
    @ObservationIgnored var startupTask: Task<Void, Never>?
    @ObservationIgnored var clipboardSaveTask: Task<Void, Never>?
    /// 剪贴板历史写入的版本号。每次落盘都取一个新值，连同当时的状态一起交给
    /// `ClipboardStore`，让迟到的去抖写入无法覆盖更新的直接写入。
    @ObservationIgnored var clipboardHistoryRevision: UInt64 = 0
    @ObservationIgnored var aiModelsRefreshTask: Task<Void, Never>?
    @ObservationIgnored var screenshotShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var clipboardShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var meetingShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var windowLayoutShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var windowLayoutPickerController: WindowLayoutPickerController?
    @ObservationIgnored var windowLayoutController: WindowLayoutController?
    @ObservationIgnored var windowDragLayoutController: WindowDragLayoutController?
    @ObservationIgnored var windowDragLayoutActivation = WindowDragLayoutActivation()
    @ObservationIgnored var accessibilityPermissionPollTask: Task<Void, Never>?
    @ObservationIgnored var systemAppearanceObservation: NSKeyValueObservation?
    @ObservationIgnored var editingHistoryID: UUID?
    @ObservationIgnored var clipboardCacheCleanupTimer: Timer?
    @ObservationIgnored var lastCacheFullNotice: Date?
    @ObservationIgnored var meetingRecordingTimer: Task<Void, Never>?
    @ObservationIgnored var meetingPreserveUserEdits = true
    @ObservationIgnored var meetingProcessingTask: Task<Void, Never>?
    @ObservationIgnored var meetingModelPreparationTask: Task<Void, Never>?
    @ObservationIgnored var meetingModelAvailabilityTask: Task<Void, Never>?
    @ObservationIgnored var meetingCurrentRecordingID: UUID?
    @ObservationIgnored var isStartingMeetingRecording = false
    @ObservationIgnored var meetingProcessingQueue: [MeetingProcessingJob] = []
    @ObservationIgnored var meetingActiveProcessingID: UUID?
    @ObservationIgnored var lastMeetingProgressStage: MeetingProcessingStage?
    @ObservationIgnored var lastMeetingProgressValue = -1.0

    @ObservationIgnored let screenshotShortcutKey = "jarvis.screenshot.shortcut"
    @ObservationIgnored let screenshotShortcutDefaultMigrationKey = "jarvis.screenshot.shortcut.f1.migrated"
    @ObservationIgnored let clipboardShortcutKey = "jarvis.clipboard.shortcut"
    @ObservationIgnored let meetingShortcutKey = "jarvis.meeting.shortcut"
    @ObservationIgnored let themePreferenceKey = "jarvis.theme.preference"
    @ObservationIgnored let accentColorPreferenceKey = "jarvis.accent-color.preference"
    @ObservationIgnored let clipboardCacheAutoCleanupEnabledKey = "jarvis.clipboard.cache.auto-cleanup.enabled"
    @ObservationIgnored let clipboardCacheAutoCleanupPeriodKey = "jarvis.clipboard.cache.auto-cleanup.period"
    @ObservationIgnored let clipboardRecordingEnabledKey = "jarvis.clipboard.recording.enabled"
    @ObservationIgnored let hideSensitiveClipboardContentKey = "jarvis.clipboard.hide-sensitive"
    @ObservationIgnored let selectedAIProviderKey = "jarvis.web.ai-provider"
    @ObservationIgnored let selectedEntertainmentPlatformKey = "jarvis.entertainment.platform"
    @ObservationIgnored var toastDismissTask: Task<Void, Never>?

    init(
        aiAPIConnectionTester: any AIAPIConnectionTesting = OpenAICompatibleAPIClient(),
        aiTextCompletionAPI: any AITextCompletionAPI = OpenAICompatibleAPIClient(),
        meetingTranscriptionService: any MeetingTranscribing = FluidAudioMeetingTranscriptionService()
    ) {
        self.aiAPIConnectionTester = aiAPIConnectionTester
        self.aiTextCompletionAPI = aiTextCompletionAPI
        self.meetingTranscriptionService = meetingTranscriptionService
        let cacheStore = ClipboardCacheStore()
        clipboardCacheStore = cacheStore
        clipboardService = ClipboardService(cacheStore: cacheStore)
        clipboardCacheDirectoryURL = cacheStore.currentDirectoryURL
        clipboardCacheMaximumBytes = cacheStore.currentMaximumBytes
        let repository = MeetingRepository()
        meetingRepository = repository
        let loadedMeetings = repository.load()
        meetingStorageError = loadedMeetings.errorMessage
        var loadedMeetingRecords = loadedMeetings.records
        for index in loadedMeetingRecords.indices {
            let original = loadedMeetingRecords[index]
            if MeetingRecord.isLegacyGeneratedTitle(original.title, createdAt: original.createdAt) {
                loadedMeetingRecords[index].title = MeetingRecord.defaultTitle
            }
            if loadedMeetingRecords[index].status == .summarizing,
               let detail = repository.loadDetail(for: loadedMeetingRecords[index].id)
            {
                loadedMeetingRecords[index].applyDetail(detail)
            }
            loadedMeetingRecords[index].applyInterruptedLaunchRecovery()
            if loadedMeetingRecords[index] != original {
                do {
                    try repository.save(loadedMeetingRecords[index])
                } catch {
                    // #38：以前 try? 静默吞掉。迁移写回失败意味着下次启动还会
                    // 重复做同一份迁移——记下来，方便排查。内存里的记录不受影响。
                    JarvisLog.error(
                        category: .storage,
                        event: "meeting.migration.save.failed",
                        error: error,
                        fields: ["meetingID": loadedMeetingRecords[index].id.uuidString]
                    )
                }
            }
        }
        meetingRecords = loadedMeetingRecords
        meetingRecorder = MeetingRecorder()
        meetingRecorder.onAudioEvent = { [weak self] event in
            self?.appendMeetingAudioEvent(event)
        }
        Task { @MainActor [weak self] in
            await self?.recoverInterruptedMeetingAudio()
        }
        loadClipboardCacheCleanupSettings()
        loadScreenshotShortcut()
        loadClipboardShortcut()
        loadMeetingShortcut()
        WindowLayoutShortcutMigration.apply()
        loadAIAPISettings()
        loadThemePreference()
        loadAccentColorPreference()
        loadLaunchAtLoginPreference()
        automaticUpdatesEnabled = JarvisAutomaticUpdatePreference.load(from: .standard)
        refreshSystemColorScheme()
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshSystemColorScheme()
            }
        }

        screenshotShortcutManager = ScreenshotShortcutManager(binding: screenshotShortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.captureScreenshot()
            }
        }

        clipboardShortcutManager = ScreenshotShortcutManager(
            binding: clipboardShortcut,
            hotKeyID: 2
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.showClipboardPanel()
            }
        }

        meetingShortcutManager = ScreenshotShortcutManager(
            binding: meetingShortcut,
            hotKeyID: 9
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleMeetingRecording()
            }
        }

        windowLayoutController = WindowLayoutController { [weak self] message in
            self?.showToast(message)
        }
        windowLayoutController?.onAccessibilityRequired = { [weak self] in
            self?.promptForTaskPermission(.accessibility)
        }
        if let windowLayoutController {
            windowLayoutPickerController = WindowLayoutPickerController(layoutController: windowLayoutController)
        }
        windowLayoutShortcutManager = ScreenshotShortcutManager(binding: .windowLayoutDefault, hotKeyID: 3) { [weak self] in
            self?.showWindowLayoutPicker()
        }
        loadSelectedAIProvider()
        loadSelectedEntertainmentPlatform()
        refreshPermissionStatus()
        synchronizeLaunchAtLogin()
        refreshMeetingModelState()
        screenRecording.bind(app: self)
        startDeferredStartup()
        JarvisLog.info(
            category: .lifecycle,
            event: "appModel.initialized",
            fields: [
                "clipboardCacheDirectory": JarvisLogRedactor.path(clipboardCacheDirectoryURL.path),
                "clipboardCacheCapacityBytes": String(clipboardCacheMaximumBytes)
            ]
        )
    }

    deinit {
        accessibilityPermissionPollTask?.cancel()
        automaticUpdateTask?.cancel()
        toastDismissTask?.cancel()
        startupTask?.cancel()
        clipboardSaveTask?.cancel()
        aiModelsRefreshTask?.cancel()
        meetingRecordingTimer?.cancel()
        meetingProcessingTask?.cancel()
        meetingModelPreparationTask?.cancel()
        meetingModelAvailabilityTask?.cancel()
    }
}

extension AppModel {
    func aiConversationController(for provider: AIConversationProvider) -> JarvisWebPlatformController {
        if let controller = aiConversationControllers[provider] {
            return controller
        }

        let controller = JarvisWebPlatformController(platform: provider.webPlatform)
        aiConversationControllers[provider] = controller
        return controller
    }

    func entertainmentController(for platform: EntertainmentPlatform) -> JarvisWebPlatformController {
        if let controller = entertainmentControllers[platform] {
            return controller
        }

        let controller = JarvisWebPlatformController(platform: platform.webPlatform)
        entertainmentControllers[platform] = controller
        return controller
    }

    /// 显示器排布变化（拔插外接屏、改分辨率）时收拾场子。
    ///
    /// 贴图是常驻窗口：所在那块屏消失后它既点不到也拿不到焦点，Esc 也关不掉，
    /// 只能重启应用。完全出屏的直接销毁，还留在屏幕内的重新收进可见范围。
    func handleScreenParametersChange() {
        windowDragLayoutController?.cancel()
        windowLayoutPickerController?.cancel()
        screenshotController.reconcilePinnedScreenshotsWithVisibleDisplays()
    }
}
