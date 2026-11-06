import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

struct MeetingRecordingStopResult: Sendable {
    let duration: TimeInterval
    let systemAudioStarted: Bool
    let systemAudioErrorMessage: String?
    /// Slices finalized before the session state is cleared. Files may already be concatenated.
    let chunks: [MeetingAudioChunk]
}

@MainActor
final class MeetingRecorder {
    private var capture: MeetingCaptureSession?
    private(set) var isStopping = false
    private(set) var isPaused = false
    private(set) var directory: URL?
    private var mode: MeetingCaptureMode = .dual
    var onAudioEvent: (@MainActor (MeetingAudioEvent) -> Void)?
    var isRecording: Bool {
        capture != nil && !isPaused
    }

    var captureFailure: String? {
        capture?.failureMessage
    }

    var isSessionOpen: Bool {
        capture != nil
    }

    func systemAveragePower() -> Float? {
        capture?.latestPower
    }

    func writtenByteCount() -> Int64 {
        guard let directory else { return 0 }
        return ["system.wav", "mic.wav"].reduce(0) { total, name in
            total + Int64((try? directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func snapshotChunks() -> [MeetingAudioChunk] {
        []
    }

    func closedChunksSnapshot() -> [MeetingAudioChunk] {
        []
    }

    func rotateIfDue() -> [MeetingAudioChunk] {
        []
    }

    func markStopInFlight() {
        isStopping = true
    }

    func start(meetingID: UUID, systemAudioURL: URL, mode: MeetingCaptureMode = .dual) async throws {
        guard !isStopping else { throw MeetingRecorderError.stopInProgress }
        guard capture == nil else { return }
        let directory = systemAudioURL.deletingLastPathComponent().appendingPathComponent("meeting-\(meetingID.uuidString).capture")
        self.directory = directory; self.mode = mode
        let session = try MeetingCaptureSession()
        do { try await session.start(directory: directory, mode: mode); capture = session } catch { _ = await session.stop(); throw error }
    }

    func pauseRecording() {
        capture?.setPaused(true); isPaused = true
    }

    func resumeRecording() throws {
        capture?.setPaused(false); isPaused = false
    }

    func stop() async -> MeetingRecordingStopResult {
        isStopping = true
        defer { isStopping = false; isPaused = false; capture = nil }
        let session = capture
        let duration = await session?.stop() ?? 0
        return MeetingRecordingStopResult(
            duration: duration,
            systemAudioStarted: mode != .microphone,
            systemAudioErrorMessage: session?.failureMessage,
            chunks: []
        )
    }

    func discard() async {
        _ = await stop()
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
    }
}

enum MeetingSystemAudioStopNotice {
    static func message(wroteSystemAudio: Bool, failureMessage: String?) -> String? {
        guard wroteSystemAudio, failureMessage != nil else { return nil }
        return JarvisFeedbackCopy.systemAudioCaptureInterrupted
    }
}

struct MeetingSystemLevelState: Equatable {
    static let silentFloor: Float = -160

    var power: Float?
    var frozen = false

    static func shouldFreeze(stopRequested: Bool) -> Bool {
        !stopRequested
    }

    mutating func observe(_ samplePower: Float) {
        guard !frozen else { return }
        power = samplePower
    }

    mutating func freezeSilent() {
        frozen = true
        power = Self.silentFloor
    }
}

enum MeetingAudioMixer {
    enum Error: LocalizedError {
        case microphoneMissing
        case noAudioTrack
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .microphoneMissing: "麦克风原始录音文件不存在"
            case .noAudioTrack: "原始录音中没有可处理的音频轨道"
            case .exportFailed: "无法生成会议合并音轨"
            }
        }
    }

    static func systemAudioInsertionDelay(
        microphoneStartedAt: Date?,
        systemAudioStartedAt: Date?
    ) -> TimeInterval {
        guard let microphoneStartedAt, let systemAudioStartedAt else { return 0 }
        return max(0, systemAudioStartedAt.timeIntervalSince(microphoneStartedAt))
    }

    static func makeMixedAudio(
        microphoneURL: URL?,
        systemAudioURL: URL?,
        outputURL: URL,
        systemAudioDelay: TimeInterval = 0
    ) async throws {
        let microphoneReady = microphoneURL.map { isReadyAudioFile(at: $0) } ?? false
        let systemReady = systemAudioURL.map { isReadyAudioFile(at: $0) } ?? false
        if !microphoneReady, let systemAudioURL, systemReady {
            if systemAudioURL.standardizedFileURL == outputURL.standardizedFileURL {
                return
            }
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: systemAudioURL, to: outputURL)
            return
        }
        guard let microphoneURL, microphoneReady else {
            throw Error.microphoneMissing
        }

        if microphoneURL.standardizedFileURL == outputURL.standardizedFileURL {
            return
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let systemAudioURL, systemReady else {
            try FileManager.default.copyItem(at: microphoneURL, to: outputURL)
            return
        }

        let microphoneAsset = AVURLAsset(url: microphoneURL)
        let systemAsset = AVURLAsset(url: systemAudioURL)
        let microphoneTracks = try await microphoneAsset.loadTracks(withMediaType: .audio)
        let systemTracks = try await systemAsset.loadTracks(withMediaType: .audio)
        guard let microphoneTrack = microphoneTracks.first,
              let systemTrack = systemTracks.first
        else {
            throw Error.noAudioTrack
        }

        let microphoneDuration = try await microphoneAsset.load(.duration)
        let systemDuration = try await systemAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let microphoneCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
            let systemCompositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw Error.noAudioTrack
        }

        try microphoneCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: microphoneDuration),
            of: microphoneTrack,
            at: .zero
        )
        let delay = max(0, systemAudioDelay)
        try systemCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: systemDuration),
            of: systemTrack,
            at: CMTime(seconds: delay, preferredTimescale: 600)
        )

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw Error.exportFailed
        }
        let microphoneMix = AVMutableAudioMixInputParameters(track: microphoneCompositionTrack)
        microphoneMix.setVolume(1.0, at: .zero)
        let systemMix = AVMutableAudioMixInputParameters(track: systemCompositionTrack)
        systemMix.setVolume(0.75, at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [microphoneMix, systemMix]
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: outputURL, as: .m4a)
    }

    static func transcodeToM4A(inputURL: URL, outputURL: URL) async throws {
        guard isReadyAudioFile(at: inputURL) else {
            throw Error.noAudioTrack
        }
        if inputURL.standardizedFileURL == outputURL.standardizedFileURL {
            return
        }
        try? FileManager.default.removeItem(at: outputURL)
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw Error.exportFailed
        }
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: outputURL, as: .m4a)
    }

    static func removeFileIfExists(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func isReadyAudioFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return false
        }
        return fileSize.intValue > 0
    }
}

enum MeetingRecorderError: LocalizedError {
    case cannotStart
    case stopInProgress

    var errorDescription: String? {
        switch self {
        case .cannotStart: "无法开始系统音频录音，请检查屏幕录制权限和系统音频采集状态"
        case .stopInProgress: "上一次录音正在收尾，请稍后再试"
        }
    }
}
