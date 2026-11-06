import AppKit
import Foundation

extension AppModel {
    func toggleMeetingRecording() {
        toolUsage.recordOpen(.meetingNotes)
        if meetingCurrentRecordingID != nil {
            stopMeetingRecording(); return
        }
        meetingCaptureMode = .dual
        guard meetingModelsReady else {
            selectedSection = .skill(.meetingNotes)
            showToast("请先下载 Paraformer-large 识别资源")
            return
        }
        if !isStartingMeetingRecording {
            Task { await startMeetingRecording() }
        }
    }

    func startMeetingRecording(
        language: MeetingLanguage = .simplifiedChinese,
        reusing recordID: UUID? = nil
    ) async {
        guard canBeginMeetingCapture else { return }
        guard !meetingRecorder.isStopping else {
            showToast(JarvisFeedbackCopy.meetingStopInProgress)
            return
        }
        isStartingMeetingRecording = true
        defer { isStartingMeetingRecording = false }

        guard meetingModelsReady else {
            meetingProcessingState = .idle
            showToast(JarvisFeedbackCopy.downloadModelsFirst)
            return
        }

        refreshPermissionStatus()
        guard meetingCaptureMode == .microphone || screenCapturePermissionGranted else {
            meetingProcessingState = .failed("缺少屏幕录制权限。请到系统设置 > 隐私与安全性 > 屏幕录制，允许Jarvis。")
            promptForTaskPermission(.screenCapture)
            showToast("请允许屏幕录制权限")
            return
        }

        let reused = reusableMeetingPlaceholder(recordID: recordID)
        let id = reused?.id ?? UUID()
        let recordingURLs = meetingRepository.recordingURLs(for: id)
        let recordingsUsage = meetingRepository.recordingsUsageBytes()
        if recordingsUsage >= MeetingRepository.recordingsWarningBytes {
            let gigabytes = Double(recordingsUsage) / (1024 * 1024 * 1024)
            showToast(JarvisFeedbackCopy.recordingsUsageWarning(gigabytes))
        }
        warnIfMeetingDiskIsLow()

        do {
            try await meetingRecorder.start(
                meetingID: id,
                systemAudioURL: recordingURLs.system,
                mode: meetingCaptureMode
            )
            let live = MeetingLiveEngine(directory: meetingRepository.captureDirectory(for: id))
            meetingLiveEngine = live
            meetingLiveGeneration = id
            meetingLiveLines = []
            try await live.start(mode: meetingCaptureMode) { [weak self] lines in
                guard let self, self.meetingLiveGeneration == id else { return }
                self.meetingLiveLines = lines
            }
            try persistStartedMeeting(id: id, reused: reused, language: language)
            meetingCurrentRecordingID = id
            selectedMeetingID = id
            meetingElapsed = 0
            meetingElapsedOrigin = Date()
            meetingElapsedAccumulated = 0
            meetingRecoverySnapshotBucket = -1
            meetingSystemSilentSince = nil
            meetingDidWarnAboutSystemSilence = false
            meetingRecordingPaused = false
            updateMeetingMenuBarState()
            meetingProcessingState = .recording
            startMeetingRecordingTimer(id: id)
            showToast(JarvisFeedbackCopy.recordingStarted)
        } catch {
            meetingLiveEngine?.cancel()
            meetingLiveEngine = nil
            await meetingRecorder.discard()
            meetingProcessingState = .failed("开始录音失败：\(error.localizedDescription)")
            showToast(JarvisFeedbackCopy.recordingStartFailed)
        }
    }

    private func persistStartedMeeting(id: UUID, reused: MeetingRecord?, language: MeetingLanguage) throws {
        let now = reused?.createdAt ?? Date()
        let title = reused?.title ?? MeetingRecord.defaultTitle
        let recordingURLs = meetingRepository.recordingURLs(for: id)
        if let reusedIndex = meetingRecords.firstIndex(where: { $0.id == id }), reused != nil {
            var record = meetingRecords[reusedIndex]
            record.duration = 0
            record.microphoneAudioFileName = nil
            record.systemAudioFileName = nil
            record.language = language
            record.captureMode = meetingCaptureMode
            record.status = .recording
            record.errorMessage = nil
            record.interruptedRecording = nil
            record.awaitingAssets = false
            record.audioChunks = []
            try meetingRepository.save(record)
            meetingRecords[reusedIndex] = record
        } else {
            let record = MeetingRecord(
                id: id,
                title: title,
                createdAt: now,
                audioFileName: recordingURLs.mixed.lastPathComponent,
                microphoneAudioFileName: nil,
                systemAudioFileName: nil,
                language: language,
                captureMode: meetingCaptureMode,
                awaitingAssets: false
            )
            try meetingRepository.save(record)
            meetingRecords.removeAll { $0.id == id }
            meetingRecords.insert(record, at: 0)
        }
    }

    private func startMeetingRecordingTimer(id: UUID) {
        meetingRecordingTimer?.cancel()
        meetingLevelHistory = []
        meetingRecordingTimer = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, self.meetingCurrentRecordingID == id else { return }
                self.sampleMeetingLevel()
                tick += 1
                // The bookkeeping below only has to happen twice a second.
                guard tick % 4 == 0 else { continue }
                if !self.meetingRecordingPaused {
                    self.meetingElapsed = self.meetingElapsedAccumulated
                        + Date().timeIntervalSince(self.meetingElapsedOrigin)
                }
                let closed = self.meetingRecorder.rotateIfDue()
                if !closed.isEmpty {
                    self.appendMeetingChunks(closed, recordID: id)
                }
                self.snapshotRecordingIfNeeded(id)
                self.refreshMeetingRecordingMeters()
                self.checkMeetingCaptureHealth()
                self.updateMeetingMenuBarState()
            }
        }
    }

    private func checkMeetingCaptureHealth() {
        guard meetingCurrentRecordingID != nil, !meetingRecordingPaused,
              let failure = meetingRecorder.captureFailure ?? meetingLiveEngine?.failureMessage else { return }
        showToast(failure)
        stopMeetingRecording()
    }

    func stopMeetingRecording() {
        guard let id = meetingCurrentRecordingID,
              let index = meetingRecords.firstIndex(where: { $0.id == id })
        else { return }

        let duration = meetingElapsed
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingRecordingPaused = false
        meetingElapsed = duration
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()

        var record = meetingRecords[index]
        record.duration = max(duration, 0)
        record.audioChunks = meetingRecorder.snapshotChunks()
        record.status = .transcribing
        meetingRecords[index] = record
        persistMeeting(record)
        meetingProcessingState = .processing(stage: .diarizing, progress: 0)
        // 同步立 flag：下面的 Task 是异步调度的，不立的话用户可立即开始新会话，
        // 旧 stop 恢复后会清掉新会话的采集状态（S-3）。
        meetingRecorder.markStopInFlight()
        meetingFinalizingIDs.insert(id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { meetingFinalizingIDs.remove(id) }
            let live = meetingLiveEngine
            meetingLiveEngine = nil
            let stopResult = await meetingRecorder.stop()
            if let live {
                do {
                    let audioURL = meetingRepository.recordingURLs(for: id).mixed
                    meetingCompletedTranscriptions[id] = try await live.finish(audioURL: audioURL)
                    markMeetingAudioRewritten(id)
                } catch {
                    finishStoppedMeeting(
                        recordID: id,
                        result: stopResult,
                        processAfterStop: false,
                        failureMessage: "录音已保留，处理未完成：\(error.localizedDescription)"
                    )
                    return
                }
            }
            let finalResult = MeetingRecordingStopResult(
                duration: stopResult.duration,
                systemAudioStarted: stopResult.systemAudioStarted,
                systemAudioErrorMessage: stopResult.systemAudioErrorMessage,
                chunks: []
            )
            finishStoppedMeeting(recordID: id, result: finalResult, processAfterStop: true)
        }
    }

    func cancelMeetingRecording() {
        guard let id = meetingCurrentRecordingID else { return }
        let duration = meetingElapsed
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()
        meetingElapsed = duration
        selectedMeetingID = id
        // 同上：同步立 flag，关掉 Task 调度窗口（S-3）。
        meetingRecorder.markStopInFlight()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stopResult = await meetingRecorder.stop()
            meetingLiveEngine?.cancel()
            meetingLiveEngine = nil
            finishStoppedMeeting(
                recordID: id,
                result: stopResult,
                processAfterStop: false,
                failureMessage: "录音已停止，原始录音已保留在本机，可重新处理"
            )
        }
    }

    func finalizeMeetingRecordingForTermination() async {
        guard let id = meetingCurrentRecordingID else { return }
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()
        let stopResult = await meetingRecorder.stop()
        meetingLiveEngine?.cancel()
        meetingLiveEngine = nil
        finishStoppedMeeting(
            recordID: id,
            result: stopResult,
            processAfterStop: false,
            failureMessage: "应用退出时已保存录音，可重新处理"
        )
    }

    func pauseMeetingRecording() {
        guard meetingCurrentRecordingID != nil, !meetingRecordingPaused else { return }
        meetingElapsedAccumulated += Date().timeIntervalSince(meetingElapsedOrigin)
        meetingElapsed = meetingElapsedAccumulated
        meetingRecorder.pauseRecording()
        meetingRecordingPaused = true
        if let id = meetingCurrentRecordingID {
            persistClosedRecorderChunks(id)
        }
    }

    func resumeMeetingRecording() {
        guard meetingCurrentRecordingID != nil, meetingRecordingPaused else { return }
        do {
            try meetingRecorder.resumeRecording()
            meetingElapsedOrigin = Date()
            meetingRecordingPaused = false
        } catch {
            showToast(JarvisFeedbackCopy.recordingStartFailed)
        }
    }
}
