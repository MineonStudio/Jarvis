import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func summarizeSelectedMeeting() {
        guard let selectedMeetingID,
              meetingRecords.contains(where: { $0.id == selectedMeetingID })
        else { return }
        summarizeMeeting(recordID: selectedMeetingID)
    }

    func summarizeMeeting(recordID: UUID, preserveUserEdits: Bool = true) {
        guard meetingRecords.contains(where: { $0.id == recordID }) else { return }
        ensureMeetingDetailLoaded(recordID)
        guard AIAPIConfiguration.load().isConfigured else {
            settingsPanelController.show(app: self)
            showToast(JarvisFeedbackCopy.configureAIFirst)
            return
        }
        guard MeetingTranscriptConsent.isConfirmed else {
            meetingPreserveUserEdits = preserveUserEdits
            meetingTranscriptConsentRecordID = recordID
            return
        }
        if !preserveUserEdits, let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
           let summary = meetingRecords[index].summary
        {
            meetingRecords[index].minutesVersions.append(MeetingMinutesVersion(summary: summary))
            meetingRecords[index].summaryCheckpoint = nil
            persistMeeting(meetingRecords[index])
        }
        meetingPreserveUserEdits = preserveUserEdits
        enqueueMeetingProcessing(
            recordID: recordID,
            kind: .summarizeOnly,
            preserveUserEdits: preserveUserEdits
        )
    }

    func confirmMeetingTranscriptConsent() {
        MeetingTranscriptConsent.confirm()
        let recordID = meetingTranscriptConsentRecordID
        meetingTranscriptConsentRecordID = nil
        if let recordID {
            summarizeMeeting(recordID: recordID, preserveUserEdits: meetingPreserveUserEdits)
        }
    }

    func cancelMeetingTranscriptConsent() {
        meetingTranscriptConsentRecordID = nil
    }

    func retryMeetingProcessing(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        let current = meetingRecords.first { $0.id == record.id } ?? record
        if current.transcript.isEmpty {
            enqueueMeetingProcessing(recordID: current.id, kind: .transcribeAndSummarize)
        } else {
            enqueueMeetingProcessing(recordID: current.id, kind: .summarizeOnly)
        }
    }

    /// Stops the run in flight — including the request itself, which is cancelled mid-stream.
    /// Everything already produced stays: the transcript, the finished windows, and whatever
    /// part of the minutes had arrived.
    func cancelMeetingProcessing() {
        guard meetingProcessingTask != nil else { return }
        meetingProcessingTask?.cancel()
        meetingProcessingTask = nil
        let activeID = meetingActiveProcessingID
        meetingActiveProcessingID = nil
        if let activeID {
            meetingLiveSummaries[activeID] = nil
        }
        if let activeID, let index = meetingRecords.firstIndex(where: { $0.id == activeID }) {
            meetingRecords[index].status = meetingRecords[index].transcript.isEmpty ? .failed : .summaryFailed
            meetingRecords[index].errorMessage = JarvisFeedbackCopy.processingStopped
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .idle
        showToast(JarvisFeedbackCopy.processingStopped)
        startNextMeetingProcessingIfNeeded()
    }

    func ensureMeetingDetailLoaded(_ id: UUID) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == id }) else { return }
        if !meetingRecords[index].detail.isEmpty {
            return
        }
        guard let detail = meetingRepository.loadDetail(for: id), !detail.isEmpty else { return }
        meetingRecords[index].applyDetail(detail)
    }

    func matchingMeetingIDs(searchText: String) async -> Set<UUID> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Set(meetingRecords.map(\.id)) }
        let records = meetingRecords
        let repository = meetingRepository
        return await Task.detached(priority: .userInitiated) {
            Set(records.compactMap { record in
                record.matchesSearch(query)
                    || repository.detailMatchesSearch(for: record.id, query: query)
                    ? record.id
                    : nil
            })
        }.value
    }

    func enqueueMeetingProcessing(
        recordID: UUID,
        kind: MeetingProcessingJob.Kind,
        preserveUserEdits: Bool = true
    ) {
        if meetingActiveProcessingID == recordID {
            return
        }
        let job = MeetingProcessingJob(
            recordID: recordID,
            kind: kind,
            preserveUserEdits: preserveUserEdits
        )
        if !meetingProcessingQueue.contains(job) {
            meetingProcessingQueue.append(job)
        }
        startNextMeetingProcessingIfNeeded()
    }

    func startNextMeetingProcessingIfNeeded() {
        guard meetingActiveProcessingID == nil else { return }
        guard meetingProcessingQueue.isEmpty == false else {
            Task { await meetingTranscriptionService.releaseCachedModels() }
            return
        }

        let job = meetingProcessingQueue.removeFirst()
        guard let record = meetingRecords.first(where: { $0.id == job.recordID }) else {
            startNextMeetingProcessingIfNeeded()
            return
        }

        switch job.kind {
        case .transcribeAndSummarize:
            processMeeting(record)
        case .summarizeOnly:
            startSummarizeTask(record, preserveUserEdits: job.preserveUserEdits)
        }
    }

    private func processMeeting(_ record: MeetingRecord) {
        meetingActiveProcessingID = record.id
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .transcribing
            meetingRecords[index].interruptedRecording = false
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .diarizing, progress: 0)
        lastMeetingProgressStage = .diarizing
        lastMeetingProgressValue = 0
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { completeActiveMeetingProcessing(for: record.id) }
            do {
                let transcription: MeetingTranscriptionResult
                let captureDirectory = meetingRepository.captureDirectory(for: record.id)
                if let completed = meetingCompletedTranscriptions.removeValue(forKey: record.id) {
                    transcription = completed
                } else if FileManager.default.fileExists(atPath: captureDirectory.path) {
                    transcription = try await MeetingLiveEngine.recover(
                        directory: captureDirectory,
                        audioURL: meetingRepository.recordingURLs(for: record.id).mixed
                    )
                    markMeetingAudioRewritten(record.id)
                } else {
                    // Existing meetings remain readable and can be reprocessed with the new engine.
                    let prepared = try await prepareAudioForTranscription(record)
                    let sourceRecord = meetingRecords.first { $0.id == record.id } ?? record
                    transcription = try await meetingTranscriptionService.transcribeTracks(
                        transcriptionTracks(
                            for: sourceRecord,
                            mixedURL: prepared.mixedURL,
                            systemAudioFileName: prepared.systemAudioFileName
                        ), language: record.language
                    ) { [weak self] stage, progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.meetingActiveProcessingID == record.id else { return }
                            self.meetingProcessingState = .processing(stage: stage, progress: progress)
                        }
                    }
                }
                try Task.checkCancellation()

                guard let currentIndex = meetingRecords.firstIndex(where: { $0.id == record.id }) else { return }
                let updatedRecord = try MeetingTranscriptCommit.applying(transcription, to: meetingRecords[currentIndex])
                meetingRecords[currentIndex] = updatedRecord
                try meetingRepository.save(updatedRecord)
                try? FileManager.default.removeItem(at: captureDirectory)

                let configuration = AIAPIConfiguration.load()
                guard configuration.isConfigured else {
                    meetingProcessingState = .awaitingConfiguration
                    showToast(JarvisFeedbackCopy.configureAIFirst)
                    return
                }
                guard MeetingTranscriptConsent.isConfirmed else {
                    meetingTranscriptConsentRecordID = updatedRecord.id
                    meetingProcessingState = .idle
                    return
                }
                try await performSummarize(
                    updatedRecord,
                    configuration: configuration,
                    preserveUserEdits: true
                )
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func startSummarizeTask(_ record: MeetingRecord, preserveUserEdits: Bool = true) {
        ensureMeetingDetailLoaded(record.id)
        let record = meetingRecords.first { $0.id == record.id } ?? record
        let configuration = AIAPIConfiguration.load()
        guard !record.transcript.isEmpty else {
            meetingProcessingState = .failed("逐字稿为空，暂时无法生成总结")
            startNextMeetingProcessingIfNeeded()
            return
        }
        guard configuration.isConfigured else {
            meetingProcessingState = .awaitingConfiguration
            showToast(JarvisFeedbackCopy.configureAIFirst)
            startNextMeetingProcessingIfNeeded()
            return
        }
        guard MeetingTranscriptConsent.isConfirmed else {
            meetingTranscriptConsentRecordID = record.id
            meetingProcessingState = .idle
            startNextMeetingProcessingIfNeeded()
            return
        }

        meetingActiveProcessingID = record.id
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: nil)
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { completeActiveMeetingProcessing(for: record.id) }
            do {
                try await performSummarize(
                    record,
                    configuration: configuration,
                    preserveUserEdits: preserveUserEdits
                )
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    /// What the meeting view shows right now: the answer still arriving, or the minutes
    /// that are actually stored.
    func displayedMeetingSummary(for record: MeetingRecord) -> MeetingSummary? {
        meetingLiveSummaries[record.id] ?? record.summary
    }

    private func performSummarize(
        _ record: MeetingRecord,
        configuration: AIAPIConfiguration,
        preserveUserEdits: Bool
    ) async throws {
        cancelMeetingTitleGeneration(record.id)
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: nil)
        let operationID = JarvisLog.operationID()
        JarvisLog.notice(
            category: .meeting,
            event: "summary.begin",
            operationID: operationID,
            fields: [
                "meetingID": record.id.uuidString,
                "transcriptSegments": String(record.transcript.count),
                "resuming": record.summaryCheckpoint == nil ? "false" : "true"
            ]
        )
        let summary = try await MeetingSummaryService(
            api: aiTextCompletionAPI,
            policy: AIStreamingPolicy.load(configuration: configuration)
        ).summarize(
            record: record,
            configuration: configuration,
            checkpoint: preserveUserEdits ? record.summaryCheckpoint : nil,
            preserveUserEdits: preserveUserEdits,
            onCheckpoint: { [weak self] checkpoint in
                guard let self,
                      let index = self.meetingRecords.firstIndex(where: { $0.id == record.id })
                else { return }
                self.meetingRecords[index].summaryCheckpoint = checkpoint
                self.persistMeeting(self.meetingRecords[index])
                JarvisLog.info(
                    category: .meeting,
                    event: "summary.checkpoint",
                    operationID: operationID,
                    fields: [
                        "meetingID": record.id.uuidString,
                        "stage": checkpoint.stage.rawValue,
                        "completedChunks": String(checkpoint.completedChunkCount),
                        "totalChunks": String(checkpoint.totalChunkCount)
                    ]
                )
            },
            onProgress: { [weak self] progress in
                guard let self, self.meetingActiveProcessingID == record.id else { return }
                self.meetingProcessingState = .processing(stage: .summarizing, progress: progress)
            },
            onLiveUpdate: { [weak self] update in
                guard let self, self.meetingActiveProcessingID == record.id else { return }
                switch update {
                case .thinking:
                    self.meetingProcessingState = .processing(stage: .thinking, progress: nil)
                case let .draft(draft):
                    self.meetingProcessingState = .processing(stage: .summarizing, progress: nil)
                    // Shown while the model is still writing. It lives beside the records,
                    // not in them, so nothing partial is stored or exported.
                    self.meetingLiveSummaries[record.id] = draft
                }
            }
        )
        meetingLiveSummaries[record.id] = nil
        guard let index = meetingRecords.firstIndex(where: { $0.id == record.id }) else { return }
        meetingRecords[index].summary = summary
        meetingRecords[index].status = .ready
        meetingRecords[index].summaryCheckpoint = nil
        meetingRecords[index].errorMessage = nil
        persistMeeting(meetingRecords[index])
        JarvisLog.notice(
            category: .meeting,
            event: "summary.complete",
            operationID: operationID,
            result: "success",
            fields: [
                "meetingID": record.id.uuidString,
                "actionItems": String(summary.actionItems.count)
            ]
        )
        meetingProcessingState = .ready
        showToast(JarvisFeedbackCopy.summaryReady)
        generateMeetingTitle(recordID: record.id, summary: summary, configuration: configuration)
    }

    private func completeActiveMeetingProcessing(for recordID: UUID) {
        meetingLiveSummaries[recordID] = nil
        guard meetingActiveProcessingID == recordID else { return }
        meetingActiveProcessingID = nil
        meetingProcessingTask = nil
        startNextMeetingProcessingIfNeeded()
    }

    /// The mixed recording was written over the one that was there before. Anyone already
    /// showing or playing that file has to be told, because its path never changes.
    func markMeetingAudioRewritten(_ recordID: UUID) {
        meetingAudioRevisions[recordID, default: 0] += 1
    }

    /// What a file looks like right now, or nil when there is no such file. Used to tell a
    /// real rewrite from a mixing pass that had nothing to do.
    private func recordingIdentity(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return "\(size.int64Value)-\(modified.timeIntervalSince1970)"
    }

    private func prepareAudioForTranscription(
        _ record: MeetingRecord
    ) async throws -> (mixedURL: URL, systemAudioFileName: String?) {
        _ = await assembleMeetingChunksIfCanonicalMissing(recordID: record.id)
        let source = meetingRecords.first { $0.id == record.id } ?? record
        let audioURL = try meetingRepository.audioURL(for: source)
        let microphoneURL = source.resolvedCaptureMode.recordsMicrophone
            ? try meetingRepository.microphoneAudioURL(for: source)
            : nil
        var systemAudioURL = try meetingRepository.systemAudioURL(for: source)
        var systemAudioFileName = source.systemAudioFileName
        let recordingURLs = meetingRepository.recordingURLs(for: source.id)

        if let currentSystemURL = systemAudioURL,
           currentSystemURL.pathExtension.lowercased() == "caf",
           MeetingAudioMixer.isReadyAudioFile(at: currentSystemURL)
        {
            do {
                try await MeetingAudioMixer.transcodeToM4A(
                    inputURL: currentSystemURL,
                    outputURL: recordingURLs.systemCompressed
                )
                systemAudioURL = recordingURLs.systemCompressed
                systemAudioFileName = recordingURLs.systemCompressed.lastPathComponent
                // Point the record at the m4a before deleting the caf, so a retry
                // does not look up a file that has already been removed.
                if let index = meetingRecords.firstIndex(where: { $0.id == source.id }) {
                    meetingRecords[index].systemAudioFileName = systemAudioFileName
                    persistMeeting(meetingRecords[index])
                }
                MeetingAudioMixer.removeFileIfExists(at: currentSystemURL)
            } catch {
                let before = recordingIdentity(audioURL)
                try await MeetingAudioMixer.makeMixedAudio(
                    microphoneURL: microphoneURL,
                    systemAudioURL: currentSystemURL,
                    outputURL: audioURL,
                    systemAudioDelay: source.resolvedSystemAudioStartOffset
                )
                if recordingIdentity(audioURL) != before {
                    markMeetingAudioRewritten(source.id)
                }
                return (audioURL, systemAudioFileName)
            }
        }

        let identityBefore = recordingIdentity(audioURL)
        try await MeetingAudioMixer.makeMixedAudio(
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            outputURL: audioURL,
            systemAudioDelay: source.resolvedSystemAudioStartOffset
        )
        if recordingIdentity(audioURL) != identityBefore {
            markMeetingAudioRewritten(source.id)
        }
        MeetingAudioMixer.removeFileIfExists(at: recordingURLs.system)
        return (audioURL, systemAudioFileName)
    }

    func finishStoppedMeeting(
        recordID: UUID,
        result: MeetingRecordingStopResult,
        processAfterStop: Bool,
        failureMessage: String? = nil
    ) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        var record = meetingRecords[index]
        record.duration = result.duration
        record.audioChunks = result.chunks
        record.systemAudioStartOffset = 0
        if result.systemAudioStarted,
           let systemAudioURL = try? meetingRepository.systemAudioURL(for: record),
           !isReadyAudioFile(at: systemAudioURL)
        {
            record.systemAudioFileName = nil
        }
        if let failureMessage {
            record.status = .failed
            record.errorMessage = failureMessage
            meetingRecords[index] = record
            persistMeeting(record)
            meetingProcessingState = .failed(failureMessage)
            return
        }
        meetingRecords[index] = record
        persistMeeting(record)
        if let message = MeetingSystemAudioStopNotice.message(
            wroteSystemAudio: result.systemAudioStarted,
            failureMessage: result.systemAudioErrorMessage
        ) {
            showToast(message)
        }
        if processAfterStop {
            enqueueMeetingProcessing(recordID: record.id, kind: .transcribeAndSummarize)
        }
    }

    private func updateMeetingFailure(recordID: UUID, message: String) {
        var hasTranscript = false
        if let index = meetingRecords.firstIndex(where: { $0.id == recordID }) {
            hasTranscript = !meetingRecords[index].transcript.isEmpty
            meetingRecords[index].status = hasTranscript ? .summaryFailed : .failed
            meetingRecords[index].errorMessage = message
            if var checkpoint = meetingRecords[index].summaryCheckpoint {
                checkpoint.stage = .failed
                checkpoint.updatedAt = Date()
                meetingRecords[index].summaryCheckpoint = checkpoint
            }
            persistMeeting(meetingRecords[index])
            let failureEvent = hasTranscript ? "summary.failed" : "processing.failed"
            JarvisLog.error(
                category: .meeting,
                event: failureEvent,
                fields: [
                    "meetingID": recordID.uuidString,
                    "hasTranscript": hasTranscript ? "true" : "false"
                ]
            )
        }
        meetingProcessingState = .failed(message)
        showToast(
            hasTranscript
                ? JarvisFeedbackCopy.summaryFailed
                : JarvisFeedbackCopy.processingFailed
        )
    }

    private func transcriptionTracks(
        for record: MeetingRecord,
        mixedURL: URL,
        systemAudioFileName: String?
    ) -> [MeetingTranscriptionTrack] {
        if record.resolvedCaptureMode == .system,
           let systemURL = readySystemAudioURL(
               recordID: record.id,
               preferredFileName: systemAudioFileName ?? record.systemAudioFileName
           )
        {
            return [
                MeetingTranscriptionTrack(
                    url: systemURL,
                    timeOffset: 0,
                    diarize: true,
                    trackID: "system"
                )
            ]
        }
        let microphoneURL = (try? meetingRepository.microphoneAudioURL(for: record)) ?? mixedURL
        var tracks = [
            MeetingTranscriptionTrack(url: microphoneURL, timeOffset: 0, diarize: true, trackID: "mic")
        ]
        if record.resolvedCaptureMode == .dual,
           let systemURL = readySystemAudioURL(
               recordID: record.id,
               preferredFileName: systemAudioFileName ?? record.systemAudioFileName
           )
        {
            tracks.insert(
                MeetingTranscriptionTrack(
                    url: systemURL,
                    timeOffset: record.resolvedSystemAudioStartOffset,
                    diarize: true,
                    trackID: "system"
                ),
                at: 0
            )
        }
        return tracks
    }

    /// Prefer the name just produced by transcode, then the compressed m4a, then the caf.
    private func readySystemAudioURL(recordID: UUID, preferredFileName: String?) -> URL? {
        let urls = meetingRepository.recordingURLs(for: recordID)
        var candidates: [URL] = []
        if let preferredFileName {
            let preferred = meetingRepository.recordingsDirectoryURL
                .appendingPathComponent(preferredFileName, isDirectory: false)
            candidates.append(preferred)
        }
        candidates.append(urls.systemCompressed)
        candidates.append(urls.system)
        var seen = Set<String>()
        for url in candidates where seen.insert(url.path).inserted {
            if MeetingAudioMixer.isReadyAudioFile(at: url) {
                return url
            }
        }
        return nil
    }

    func appendMeetingChunks(_ chunks: [MeetingAudioChunk], recordID: UUID) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        for chunk in chunks {
            meetingRecords[index].audioChunks.removeAll { $0.kind == chunk.kind && $0.index == chunk.index }
            meetingRecords[index].audioChunks.append(chunk)
        }
        meetingRecords[index].audioChunks.sort { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.index < rhs.index
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        persistMeeting(meetingRecords[index])
    }

    func appendMeetingAudioEvent(_ event: MeetingAudioEvent) {
        guard let id = meetingCurrentRecordingID,
              let index = meetingRecords.firstIndex(where: { $0.id == id })
        else { return }
        meetingRecords[index].audioEvents.append(event)
        persistMeeting(meetingRecords[index])
        persistClosedRecorderChunks(id)
        showToast(event.message)
    }

    func persistClosedRecorderChunks(_ id: UUID) {
        let chunks = meetingRecorder.closedChunksSnapshot()
        guard !chunks.isEmpty else { return }
        appendMeetingChunks(chunks, recordID: id)
    }

    func reusableMeetingPlaceholder(recordID: UUID?) -> MeetingRecord? {
        let candidate = recordID ?? selectedMeetingID
        guard let candidate,
              let record = meetingRecords.first(where: { $0.id == candidate }),
              record.awaitingAssets == true
        else { return nil }
        return record
    }

    /// One bar of the live meter. Reads the recorder directly: the once-a-second mirror in
    /// `meetingSystemPower` is too coarse to draw with.
    func sampleMeetingLevel() {
        let level = meetingRecordingPaused
            ? 0
            : MeetingAudioLevel.normalized(meetingRecorder.systemAveragePower())
        meetingLevelHistory.append(level)
        let limit = Self.meetingLevelHistoryLimit
        if meetingLevelHistory.count > limit {
            meetingLevelHistory.removeFirst(meetingLevelHistory.count - limit)
        }
    }

    private static let meetingLevelHistoryLimit = 48

    func refreshMeetingRecordingMeters() {
        meetingSystemPower = meetingRecorder.systemAveragePower()
        meetingBytesWritten = meetingRecorder.writtenByteCount()
    }

    func warnIfMeetingDiskIsLow() {
        let directory = meetingRepository.recordingsDirectoryURL
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values?.volumeAvailableCapacityForImportantUsage, bytes < 512 * 1024 * 1024 {
            showToast("磁盘剩余空间不足 512MB，录音可能写不完整")
        }
    }

    /// Builds canonical tracks from closed slices when stop() never finished that track.
    /// A playable microphone file does not skip system slices that are still on disk.
    private func assembleMeetingChunksIfCanonicalMissing(recordID: UUID) async -> Bool {
        let urls = meetingRepository.recordingURLs(for: recordID)
        guard let record = meetingRecords.first(where: { $0.id == recordID }) else {
            return false
        }
        let recordsMicrophone = record.resolvedCaptureMode.recordsMicrophone
        let microphoneReady = recordsMicrophone
            ? await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
            : true
        let systemCAFReady = await MeetingAudioAssembler.playableDuration(at: urls.system) != nil
        let systemM4AReady = await MeetingAudioAssembler.playableDuration(at: urls.systemCompressed) != nil
        let systemReady = systemCAFReady || systemM4AReady
        let plan = MeetingCanonicalAssembly.plan(
            microphoneReady: microphoneReady,
            systemReady: systemReady
        )
        if !plan.assembleMicrophone && !plan.assembleSystem {
            return recordsMicrophone ? microphoneReady : systemReady
        }
        let directory = urls.microphone.deletingLastPathComponent()
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let merged = MeetingAudioChunkFile.mergedChunks(
            stored: record.audioChunks,
            discovered: MeetingAudioChunkFile.discoveredChunks(meetingID: recordID, fileNames: fileNames)
        )
        let playable = await recoverableChunkFiles(merged, directory: directory)
        let microphone = plan.assembleMicrophone
            ? playable.filter { $0.chunk.kind == .microphone }
            : []
        let system = plan.assembleSystem
            ? playable.filter { $0.chunk.kind == .system }
            : []
        guard !microphone.isEmpty || !system.isEmpty else {
            return recordsMicrophone ? microphoneReady : systemReady
        }

        var consumedNames = Set<String>()
        var assembledDuration: TimeInterval = 0
        if !microphone.isEmpty,
           let assembled = try? await MeetingAudioAssembler.concatenate(
               urls: microphone.map(\.url),
               outputURL: urls.microphone
           ),
           await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
        {
            assembledDuration = max(assembled, microphone.reduce(0) { $0 + $1.chunk.duration })
            consumedNames.formUnion(microphone.map(\.url.lastPathComponent))
        }
        var assembledSystemName: String?
        if !system.isEmpty,
           await (try? MeetingAudioAssembler.concatenate(
               urls: system.map(\.url),
               outputURL: urls.system
           )) != nil,
           await MeetingAudioAssembler.playableDuration(at: urls.system) != nil
        {
            assembledSystemName = urls.system.lastPathComponent
            consumedNames.formUnion(system.map(\.url.lastPathComponent))
        }
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else {
            return recordsMicrophone
                ? await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
                : systemReady
        }
        if assembledDuration > 0 {
            meetingRecords[index].microphoneAudioFileName = urls.microphone.lastPathComponent
            meetingRecords[index].duration = max(meetingRecords[index].duration, assembledDuration)
        }
        if let assembledSystemName {
            meetingRecords[index].systemAudioFileName = assembledSystemName
            if meetingRecords[index].captureMode == nil {
                meetingRecords[index].captureMode = .dual
            }
            if !recordsMicrophone {
                meetingRecords[index].duration = max(
                    meetingRecords[index].duration,
                    system.reduce(0) { $0 + $1.chunk.duration }
                )
            }
        }
        if !consumedNames.isEmpty {
            for name in consumedNames {
                let url = directory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: url)
            }
            meetingRecords[index].audioChunks.removeAll { consumedNames.contains($0.fileName) }
            persistMeeting(meetingRecords[index])
        }
        if recordsMicrophone {
            return await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
        }
        if await MeetingAudioAssembler.playableDuration(at: urls.system) != nil {
            return true
        }
        return await MeetingAudioAssembler.playableDuration(at: urls.systemCompressed) != nil
    }

    func recoverInterruptedMeetingAudio() async {
        let snapshot = meetingRecords.map { record in
            (id: record.id, interrupted: record.interruptedRecording == true)
        }
        for item in snapshot {
            let ready = await assembleMeetingChunksIfCanonicalMissing(recordID: item.id)
            guard item.interrupted, ready else { continue }
            guard let index = meetingRecords.firstIndex(where: { $0.id == item.id }) else { continue }
            let duration = meetingRecords[index].duration
            meetingRecords[index].status = .failed
            meetingRecords[index].interruptedRecording = true
            meetingRecords[index].errorMessage =
                "录音未正常结束，已保留约 \(MeetingRecordingStyle.formatDuration(duration))。可以手动继续处理，不会自动开始转写。"
            persistMeeting(meetingRecords[index])
        }
    }

    private func recoverableChunkFiles(
        _ chunks: [MeetingAudioChunk],
        directory: URL
    ) async -> [(chunk: MeetingAudioChunk, url: URL)] {
        var kept: [(MeetingAudioChunk, URL)] = []
        for chunk in chunks where MeetingAudioChunkFile.isChunkFileName(chunk.fileName) {
            let url = directory.appendingPathComponent(chunk.fileName)
            guard MeetingAudioMixer.isReadyAudioFile(at: url) else { continue }
            if chunk.closed {
                kept.append((chunk, url))
            } else if await MeetingAudioAssembler.playableDuration(at: url) != nil {
                kept.append((chunk, url))
            }
        }
        return kept
    }

    func snapshotRecordingIfNeeded(_ id: UUID) {
        let bucket = Int(meetingElapsed / 30)
        guard bucket > 0, bucket != meetingRecoverySnapshotBucket else { return }
        meetingRecoverySnapshotBucket = bucket
        guard let index = meetingRecords.firstIndex(where: { $0.id == id }) else { return }
        meetingRecords[index].duration = meetingElapsed
        persistMeeting(meetingRecords[index])
    }

    @discardableResult
    func persistMeeting(_ record: MeetingRecord) -> Bool {
        do {
            try meetingRepository.save(record)
            return true
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "meeting.persist.failed",
                error: error,
                fields: ["meetingID": record.id.uuidString]
            )
            showToast(JarvisFeedbackCopy.saveFailed)
            return false
        }
    }

    private func waitForMeetingAudioFile(at url: URL) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !isReadyAudioFile(at: url) {
            guard !Task.isCancelled else { throw CancellationError() }
            guard Date() < deadline else {
                throw MeetingAudioFileError.unavailable
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func isReadyAudioFile(at url: URL) -> Bool {
        MeetingAudioMixer.isReadyAudioFile(at: url)
    }

    func updateMeetingMenuBarState() {
        JarvisMenuBarController.shared.updateMeetingRecordingState(
            isRecording: meetingCurrentRecordingID != nil,
            elapsed: meetingElapsed,
            modelsReady: meetingModelsReady
        )
    }
}

struct MeetingProcessingJob: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case transcribeAndSummarize
        case summarizeOnly
    }

    let recordID: UUID
    let kind: Kind
    var preserveUserEdits: Bool = true
}

private enum MeetingAudioFileError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "原始录音文件未完成保存，无法开始转写"
        }
    }
}
