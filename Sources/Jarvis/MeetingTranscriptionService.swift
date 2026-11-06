import Foundation

protocol MeetingTranscribing: Sendable {
    func prepareModel(_ stage: MeetingModelPreparationStage, progress: @escaping @Sendable (Double) -> Void) async throws
    func removeModel(_ stage: MeetingModelPreparationStage) async throws
    func transcribeTracks(
        _ tracks: [MeetingTranscriptionTrack],
        language: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult
    func releaseCachedModels() async
}

actor SherpaMeetingTranscriptionService: MeetingTranscribing {
    func prepareModel(_: MeetingModelPreparationStage, progress: @escaping @Sendable (Double) -> Void) async throws {
        MeetingModelDownloadMeter.update(completed: 0, total: 0)
        _ = try await MeetingEngineJob().run(["prepare", MeetingEnginePaths.models.path]) { event in
            guard event.type == "download", let done = event.completed, let total = event.total else { return }
            MeetingModelDownloadMeter.update(completed: done, total: total)
            progress(total > 0 ? min(0.99, Double(done) / Double(total)) : 0)
        }
        try MeetingModelStorage.markVerified()
        progress(1)
    }

    func removeModel(_ stage: MeetingModelPreparationStage) async throws {
        try MeetingModelStorage.removeModel(for: stage)
    }

    func transcribeTracks(
        _ tracks: [MeetingTranscriptionTrack], language _: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult {
        guard MeetingModelStorage.availability().isReady else { throw MeetingTranscriptionError.modelsUnavailable }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-transcribe-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var system = "-", mic = "-"
        for (index, track) in tracks.enumerated() {
            try Task.checkCancellation()
            let decoded = work.appendingPathComponent("track-\(index).wav")
            try await MeetingAudioDecoder.decode(track.url, to: decoded, delay: track.timeOffset)
            if track.trackID == "system" {
                system = decoded.path
            } else {
                mic = decoded.path
            }
        }
        let mixed = work.appendingPathComponent("mixed.wav")
        _ = try await MeetingEngineJob().run(["mix", system, mic, mixed.path])
        progress(.transcribing, 0.02)
        let event = try await MeetingEngineJob().run(["transcribe", MeetingEnginePaths.models.path, mixed.path]) { event in
            if let p = event.progress {
                progress(.transcribing, p * 0.9)
            }
        }
        guard let transcript = event.transcript, !transcript.sentences.isEmpty else {
            throw MeetingEngineError.failed("没有识别到有效语音。录音已保留，可检查音量后重试。")
        }
        progress(.diarizing, 1)
        return transcript.result()
    }

    func releaseCachedModels() async { /* Subprocesses release native models on exit. */ }
}

enum MeetingTrackFailure {
    static func turnsAfterFailedTranscription(_ turns: [MeetingMinutesAlgorithm.SpeakerTurn], appendedFrom index: Int) -> [MeetingMinutesAlgorithm.SpeakerTurn] {
        guard index >= 0, index <= turns.count else { return turns }
        return Array(turns.prefix(index))
    }
}

enum MeetingTranscriptionError: LocalizedError {
    case modelsUnavailable
    case speechAssetUnavailable(String)
    var errorDescription: String? {
        switch self {
        case .modelsUnavailable: "请先在设置中下载 Paraformer-large 识别资源。"
        case let .speechAssetUnavailable(message): message
        }
    }
}
