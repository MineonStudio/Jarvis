import AVFoundation
import ScreenCaptureKit

/// A display-wide audio stream is intentionally independent of the video filter.
/// AVAudioFile state is confined to writeQueue; stream/failure state uses stateLock.
final class ScreenRecordingSystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Stats: Sendable {
        let firstSampleTime: Double?
        let failure: String?
    }

    private let url: URL
    private let onFailure: @Sendable (String) -> Void
    private let writeQueue = DispatchQueue(label: "com.jarvis.screen-recording.system-audio")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var stopping = false
    private var failure: String?
    private var file: AVAudioFile?
    private var firstSampleTime: Double?

    init(url: URL, onFailure: @escaping @Sendable (String) -> Void) {
        self.url = url
        self.onFailure = onFailure
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw ScreenRecordingError.message("未找到系统音频采集源。") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 48000; config.channelCount = 2
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)
        stateLock.withLock { self.stream = stream }
        try await stream.startCapture()
    }

    func stop() async -> Stats {
        let active = stateLock.withLock { stopping = true; return stream }
        if let active {
            do {
                try await active.stopCapture()
            } catch {
                recordFailure(error.localizedDescription)
            }
        }
        // Drain callbacks and seal the CAF before the assembler opens it.
        let first = writeQueue.sync { file = nil; return firstSampleTime }
        return stateLock.withLock {
            stream = nil
            return Stats(firstSampleTime: first, failure: failure ?? (first == nil ? "未收到系统音频数据。" : nil))
        }
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        do {
            try sampleBuffer.withAudioBufferList { list, _ in
                guard let description = sampleBuffer.formatDescription,
                      let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                      let format = AVAudioFormat(streamDescription: basic),
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer)
                else { throw ScreenRecordingError.message("系统音频格式无效。") }
                if file == nil {
                    file = try AVAudioFile(forWriting: url, settings: format.settings)
                }
                try file?.write(from: buffer)
                if firstSampleTime == nil {
                    let time = sampleBuffer.presentationTimeStamp.seconds
                    if time.isFinite {
                        firstSampleTime = time
                    }
                }
            }
        } catch { recordFailure(error.localizedDescription) }
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        if !stateLock.withLock({ stopping }) {
            recordFailure(error.localizedDescription)
        }
    }

    private func recordFailure(_ message: String) {
        let notify = stateLock.withLock {
            guard failure == nil else { return false }
            failure = message
            return !stopping
        }
        if notify {
            onFailure("系统音频采集失败：\(message)")
        }
    }
}

/// Observe timestamps only; no video frames are retained or copied.
final class ScreenRecordingVideoClock: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var first: Double?
    var firstSampleTime: Double? {
        lock.withLock { first }
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, sampleBuffer.imageBuffer != nil else { return }
        let time = sampleBuffer.presentationTimeStamp.seconds
        guard time.isFinite else { return }
        lock.withLock {
            if first == nil {
                first = time
            }
        }
    }
}
