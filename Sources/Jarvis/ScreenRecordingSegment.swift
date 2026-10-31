import AVFoundation
import Foundation
import ScreenCaptureKit

/// A delegate belongs to exactly one segment. Late callbacks never reach a newer segment.
@MainActor
final class ScreenRecordingSegment: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    let url: URL
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var captureStarted = false
    private var started = false
    private var finished = false
    private var failure: String?
    private var stopping = false
    private var systemAudio: ScreenRecordingSystemAudioCapture?
    private let videoClock = ScreenRecordingVideoClock()
    private let videoClockQueue = DispatchQueue(label: "com.jarvis.screen-recording.video-clock")
    var onUnexpectedStop: (@MainActor (String) -> Void)?

    var duration: Double {
        max(0, output?.recordedDuration.seconds ?? 0)
    }

    init(url: URL) {
        self.url = url
    }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, hevc: Bool, systemAudio: Bool = false) async throws {
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = hevc ? .hevc : .h264
        guard recording.availableVideoCodecTypes.contains(recording.videoCodecType),
              recording.availableOutputFileTypes.contains(.mp4)
        else {
            throw ScreenRecordingError.message("当前设备不支持所选编码，请改用 H.264。")
        }
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.output = output
        self.stream = stream
        try stream.addRecordingOutput(output)
        if systemAudio {
            try ScreenRecordingAudioTiming(offset: 0).save(for: url)
            try stream.addStreamOutput(videoClock, type: .screen, sampleHandlerQueue: videoClockQueue)
            let audio = ScreenRecordingSystemAudioCapture(url: ScreenRecordingAudioTiming.audioURL(for: url)) { [weak self] message in
                Task { @MainActor in
                    guard let self, !self.stopping else { return }
                    self.failure = message
                    self.onUnexpectedStop?(message)
                }
            }
            self.systemAudio = audio
            try await audio.start()
        }
        try Task.checkCancellation()
        try await stream.startCapture()
        captureStarted = true
        try Task.checkCancellation()
        // startCapture returning is insufficient: only the writer delegate confirms recording.
        for _ in 0 ..< 150 {
            if let failure {
                throw ScreenRecordingError.message(failure)
            }
            if started {
                try Task.checkCancellation()
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ScreenRecordingError.message("录制启动超时，请检查屏幕录制权限。")
    }

    func stop() async throws {
        // Cancellation of a countdown/start task must not cancel file finalization.
        try await Task { @MainActor [self] in try await finishCapture() }.value
    }

    private func finishCapture() async throws {
        stopping = true
        if !captureStarted {
            if let stream, let output {
                try? stream.removeRecordingOutput(output)
            }
            finished = true
        }
        if !finished, let stream {
            do {
                try await stream.stopCapture()
            } catch {
                // The system may already have stopped capture; still await the file finalizer.
                if !finished {
                    failure = failure ?? error.localizedDescription
                }
            }
        }
        for _ in 0 ..< 200 {
            if finished {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await finishSystemAudio()
        guard finished else { throw ScreenRecordingError.message("视频封装超时，临时文件已保留，可稍后恢复。") }
        stream = nil
        if let failure {
            throw ScreenRecordingError.message(failure)
        }
    }

    private func finishSystemAudio() async throws {
        if let audio = systemAudio {
            let stats = await audio.stop()
            systemAudio = nil
            videoClockQueue.sync {}
            if let firstAudio = stats.firstSampleTime, let firstVideo = videoClock.firstSampleTime {
                try ScreenRecordingAudioTiming(offset: firstAudio - firstVideo).save(for: url)
            } else {
                failure = failure ?? "系统音频或画面时间戳缺失。"
            }
            failure = failure ?? stats.failure
        }
    }

    nonisolated func recordingOutputDidStartRecording(_: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.started = true }
    }

    nonisolated func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.finished = true }
    }

    nonisolated func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            failure = message
            finished = true
            if !stopping {
                onUnexpectedStop?(message)
            }
        }
    }

    nonisolated func stream(_: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, !stopping else { return }
            onUnexpectedStop?(message)
        }
    }
}
