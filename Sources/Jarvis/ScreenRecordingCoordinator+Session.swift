import AppKit
import AVFoundation
import ScreenCaptureKit

extension ScreenRecordingCoordinator {
    func handlePrimaryShortcut() {
        guard !selectingTarget else { return }
        switch phase {
        case .idle:
            present()
        case .countdown:
            cancelCountdown()
        case .recording, .paused:
            Task { await stop() }
        case .starting:
            lifecycleTask?.cancel()
        case .changing:
            interruptionReason = "已停止屏幕录制。"
        case .saving:
            app?.showToast("正在保存屏幕录制，请稍候。")
        }
    }

    func start() {
        guard canStart else { return }
        guard app?.meetingCurrentRecordingID == nil, app?.isStartingMeetingRecording != true,
              app?.meetingRecorder.isStopping != true
        else {
            message = "请先停止会议录音，再开始屏幕录制。"; return
        }
        phase = .starting // reserve session before microphone permission or any other suspension
        message = nil
        panelController?.showModeHint(nil)
        lifecycleTask = Task { await startSession() }
    }

    func startSession() async {
        do {
            try await authorizeMicrophone()
            try Task.checkCancellation()
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let filter = try makeFilter(content: content)
            let config = try makeConfiguration(filter: filter, content: content)
            try prepareSession(filter: filter, configuration: config)
            hiddenWindow = NSApp.windows.first { $0.frameAutosaveName == JarvisMainWindowController.frameAutosaveName }
            hiddenWindow?.orderOut(nil)
            installCountdownCancellation()
            for seconds in stride(from: settings.countdown, through: 1, by: -1) {
                phase = .countdown(seconds)
                try await Task.sleep(for: .seconds(1))
            }
            try Task.checkCancellation()
            removeCountdownCancellation()
            phase = .starting
            showingSetup = false
            panelController?.hide()
            panelController?.updateRegionBorder()
            try await Task.sleep(for: .milliseconds(150))
            try Task.checkCancellation()
            try await startSegment()
            phase = .recording
            beginTimer()
        } catch {
            if let segment {
                try? await segment.stop()
            }
            segment = nil
            if let current, repository.segments(current.id).isEmpty {
                try? repository.remove(current)
                records.removeAll { $0.id == current.id }
            }
            finishSession()
            if !(error is CancellationError) {
                message = error.localizedDescription
            }
            showingSetup = true
            panelController?.showLauncher()
        }
    }

    func startSegment() async throws {
        guard let current, let sessionFilter, let sessionConfiguration else { return }
        if let interruptionReason {
            throw ScreenRecordingError.message(interruptionReason)
        }
        let next = ScreenRecordingSegment(url: repository.segment(current.id, index: segmentIndex))
        segmentIndex += 1
        segment = next
        next.onUnexpectedStop = { [weak self] message in
            guard let self, self.current?.id == current.id else { return }
            Task { await self.interrupt(reason: "采集已中断：\(message)") }
        }
        try await next.start(filter: sessionFilter, configuration: sessionConfiguration, hevc: current.settings.useHEVC, systemAudio: current.settings.systemAudio)
        if let interruptionReason {
            throw ScreenRecordingError.message(interruptionReason)
        }
    }

    func cancelCountdown() {
        guard case .countdown = phase else { return }
        lifecycleTask?.cancel()
    }

    func installCountdownCancellation() {
        localCountdownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == JarvisKeyCode.escape {
                Task { @MainActor in self?.cancelCountdown() }
            }
            return event
        }
        globalCountdownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == JarvisKeyCode.escape {
                Task { @MainActor in self?.cancelCountdown() }
            }
        }
    }

    func removeCountdownCancellation() {
        if let localCountdownMonitor {
            NSEvent.removeMonitor(localCountdownMonitor)
        }
        if let globalCountdownMonitor {
            NSEvent.removeMonitor(globalCountdownMonitor)
        }
        localCountdownMonitor = nil; globalCountdownMonitor = nil
    }

    func interrupt(reason: String) async {
        guard isActive else { return }
        interruptionReason = reason
        if phase == .starting {
            lifecycleTask?.cancel()
            message = reason
        } else {
            await stop(reason: reason)
        }
    }

    func togglePause() async {
        if phase == .recording {
            phase = .changing
            do {
                try await closeSegment()
                phase = .paused
                if let interruptionReason {
                    await stop(reason: interruptionReason)
                }
            } catch { await stopAfterTransitionFailure(error) }
        } else if phase == .paused {
            phase = .changing
            do {
                guard try await validateCurrentTarget() else { return }
                try await startSegment()
                phase = .recording
            } catch {
                if segment == nil, interruptionReason == nil {
                    phase = .paused
                    message = error.localizedDescription
                } else {
                    await stopAfterTransitionFailure(error)
                }
            }
        }
    }

    func closeSegment() async throws {
        guard let active = segment else { return }
        try await active.stop()
        let duration = active.duration
        completedDuration += duration.isFinite ? duration : 0
        elapsed = completedDuration
        segment = nil
        if var record = current {
            record.duration = completedDuration
            try repository.save(record)
            current = record
        }
    }

    func stopAfterTransitionFailure(_ error: any Error) async {
        phase = .paused
        await stop(reason: error.localizedDescription)
    }

    func stop(reason: String? = nil) async {
        if case .countdown = phase {
            cancelCountdown(); return
        }
        guard phase == .recording || phase == .paused, var record = current else { return }
        phase = .saving
        lastSaveSucceeded = false
        var warning = reason
        do { try await closeSegment() } catch { warning = warning ?? error.localizedDescription }
        do {
            try await finalize(&record, allowIncompleteSegments: warning != nil)
            lastSaveSucceeded = true
            finishSession()
            message = warning.map { "\($0) 已保存可用的视频内容。" }
            if let message {
                app?.showToast(message)
            }
        } catch {
            finishSession()
            message = "保存未完成：\(error.localizedDescription) 临时片段已保留，请在历史中恢复。"
        }
    }

    func finishSession() {
        removeCountdownCancellation()
        timer?.cancel(); timer = nil
        current = nil; segment = nil
        region = nil
        interruptionReason = nil
        sessionFilter = nil; sessionConfiguration = nil
        phase = .idle
        panelController?.hide()
        hiddenWindow?.makeKeyAndOrderFront(nil)
        hiddenWindow = nil
        updateMenuBar()
    }
}
