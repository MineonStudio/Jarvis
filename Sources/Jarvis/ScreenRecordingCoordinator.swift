import AppKit
import AVFoundation
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class ScreenRecordingCoordinator {
    var settings = ScreenRecordingSettings()
    var mode: ScreenRecordingMode = .display {
        didSet {
            if mode != .region {
                region = nil
            }
        }
    }

    var displayID: CGDirectDisplayID?
    var windowID: CGWindowID?
    var region: CGRect?
    var phase: ScreenRecordingPhase = .idle {
        didSet { updateMenuBar() }
    }

    var showingSetup = false
    var refreshing = false
    var selectingTarget = false
    var message: String?
    var elapsed: Double = 0
    var lastSaveSucceeded = true
    var records: [ScreenRecordingRecord] = []
    var displays: [SCDisplay] = []
    var windows: [SCWindow] = []
    var preview: NSImage?
    var shortcuts = ScreenRecordingShortcuts()
    var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    @ObservationIgnored let videoPreviewController = EntertainmentVideoPreviewController()
    @ObservationIgnored let repository: ScreenRecordingRepository
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored var sourceContent: SCShareableContent?
    @ObservationIgnored var current: ScreenRecordingRecord?
    @ObservationIgnored var segment: ScreenRecordingSegment?
    @ObservationIgnored var segmentIndex = 0
    @ObservationIgnored var completedDuration: Double = 0
    @ObservationIgnored var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored var timer: Task<Void, Never>?
    @ObservationIgnored let selectionController = ScreenRecordingRegionController()
    @ObservationIgnored let windowSelectionController = ScreenRecordingWindowSelectionController()
    @ObservationIgnored var panelController: ScreenRecordingPanelController?
    @ObservationIgnored var hiddenWindow: NSWindow?
    @ObservationIgnored var observers: [NSObjectProtocol] = []
    @ObservationIgnored var previewRevision = UUID()
    @ObservationIgnored var sessionFilter: SCContentFilter?
    @ObservationIgnored var sessionConfiguration: SCStreamConfiguration?
    @ObservationIgnored var localCountdownMonitor: Any?
    @ObservationIgnored var globalCountdownMonitor: Any?
    @ObservationIgnored var interruptionReason: String?

    init(repository: ScreenRecordingRepository = ScreenRecordingRepository()) {
        self.repository = repository
        records = repository.load()
        if let data = UserDefaults.standard.data(forKey: "jarvis.screen-recording.settings"),
           let saved = try? JSONDecoder().decode(ScreenRecordingSettings.self, from: data)
        {
            settings = saved
        }
        let countdownMigrationKey = "jarvis.screen-recording.three-second-default.migrated"
        if !UserDefaults.standard.bool(forKey: countdownMigrationKey) {
            settings.countdown = 3
            persistSettings()
            UserDefaults.standard.set(true, forKey: countdownMigrationKey)
        }
        let microphoneMigrationKey = "jarvis.screen-recording.no-microphone-default.migrated"
        if !UserDefaults.standard.bool(forKey: microphoneMigrationKey) {
            settings.microphone = false
            settings.microphoneID = ""
            persistSettings()
            UserDefaults.standard.set(true, forKey: microphoneMigrationKey)
        }
    }

    var isActive: Bool {
        phase.isActive
    }

    var selectedDisplay: SCDisplay? {
        displays.first { $0.displayID == displayID }
    }

    var selectedWindow: SCWindow? {
        windows.first { $0.windowID == windowID }
    }

    var targetName: String {
        if mode == .window {
            return selectedWindow.map { "\($0.owningApplication?.applicationName ?? "应用") · \($0.title ?? "无标题窗口")" }
                ?? "请选择窗口"
        }
        guard let selectedDisplay else { return "请选择显示器" }
        let name = displayName(selectedDisplay)
        if mode == .region, let region {
            return "\(name) · \(Int(region.width)) × \(Int(region.height)) 点"
        }
        return name
    }

    var canStart: Bool {
        !isActive && !refreshing && !selectingTarget && sourceContent != nil
            && (mode == .window ? selectedWindow != nil : selectedDisplay != nil)
            && (mode != .region || region != nil)
    }

    var recoverableRecords: [ScreenRecordingRecord] {
        records.filter { !$0.completed && $0.id != current?.id }
    }

    var outputDirectory: URL {
        repository.movieDirectory
    }

    func displayName(_ display: SCDisplay) -> String {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display.displayID }?
            .localizedName ?? "显示器 \(display.displayID)"
    }

    func bind(app: AppModel) {
        guard self.app == nil else { return }
        self.app = app
        panelController = ScreenRecordingPanelController(recorder: self)
        shortcuts.onAction = { [weak self] action in
            guard let self else { return }
            if action == .stop {
                Task { await self.stop() }
            } else {
                handlePrimaryShortcut()
            }
        }
        shortcuts.install()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.interrupt(reason: "系统即将休眠，已结束屏幕录制。") }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.interrupt(reason: "屏幕已锁定，已结束屏幕录制。") }
        })
    }

    func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "jarvis.screen-recording.settings")
        }
    }

    func dismissToolbar() {
        if isPreparing {
            cancelPreparation(); return
        }
        if selectingTarget {
            cancelTargetSelection(); return
        }
        region = nil
        showingSetup = false
        panelController?.hide()
    }

    func present() {
        guard !isActive else { return }
        region = nil
        message = nil
        if !ScreenRecordingSettings.countdownOptions.contains(settings.countdown) {
            settings.countdown = 3
        }
        showingSetup = true
        panelController?.showLauncher()
        Task { await refreshSources() }
    }
}
