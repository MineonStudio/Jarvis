import AppKit

extension ScreenRecordingCoordinator {
    var isPreparing: Bool {
        switch phase {
        case .starting, .countdown: true
        default: false
        }
    }

    var recordingButtonTitle: String {
        switch phase {
        case let .countdown(seconds): "\(seconds)秒"
        case .starting: "准备中"
        default: "录制"
        }
    }

    var recordingStartHint: String {
        settings.countdown > 0 ? "录制，倒计时 \(settings.countdown) 秒后开始" : "立即开始录制"
    }

    var recordingScopeSummary: String {
        switch mode {
        case .display: ""
        case .window: selectedWindow?.owningApplication?.applicationName ?? "窗口"
        case .region: region.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "自定义区域"
        }
    }

    func cancelPreparation() {
        guard isPreparing else { return }
        lifecycleTask?.cancel()
    }

    func cancelTargetSelection() {
        region = nil
        selectionController.cancel()
        windowSelectionController.cancel()
        selectingTarget = false
        panelController?.showLauncher()
    }
}
