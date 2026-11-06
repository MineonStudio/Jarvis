import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit supplies both tracks on a shared clock, as in Tingo.
/// All conversion and disk writes stay on the serial audio queue.
final class MeetingCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jarvis.meeting.capture", qos: .userInitiated)
    private let lock = NSLock()
    private var stream: SCStream?
    private var microphone: AVAudioEngine?
    private var writers: [String: MeetingWAVWriter] = [:]
    private var converters: [String: AVAudioConverter] = [:]
    private var origin: CMTime?
    private var paused = false
    private var pauseStart: CMTime?
    private var skipped: Double = 0
    private var power: Float = -160
    private var failure: String?
    private var stopping = false
    private let format: AVAudioFormat

    init(validatingFormat _: Void = ()) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            throw MeetingEngineError.failed("无法创建录音格式")
        }
        self.format = format
        super.init()
    }

    var latestPower: Float {
        lock.withLock { power }
    }

    var failureMessage: String? {
        lock.withLock { failure }
    }

    var duration: Double {
        queue.sync { Double(writers.values.map(\.frames).max() ?? 0) / 16000 }
    }

    func start(directory: URL, mode: MeetingCaptureMode) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if mode.recordsMicrophone {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw MeetingEngineError.failed("请在系统设置中允许 Jarvis 使用麦克风。") }
        }
        let names = mode == .system ? ["system"] : mode == .microphone ? ["mic"] : ["system", "mic"]
        for name in names {
            writers[name] = try MeetingWAVWriter(url: directory.appendingPathComponent("\(name).wav"))
        }
        if mode == .microphone {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else { throw MeetingEngineError.failed("没有可用的麦克风") }
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                // The tap buffer belongs to AVAudioEngine and cannot outlive this callback.
                self?.queue.sync { self?.write(buffer, source: "mic", timestamp: nil) }
            }
            microphone = engine
            try engine.start()
            return
        }
        guard CGPreflightScreenCaptureAccess() else { throw MeetingEngineError.failed("请允许 Jarvis 录制屏幕与系统音频。") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw MeetingEngineError.failed("未找到显示器") }
        let configuration = SCStreamConfiguration()
        configuration.width = 2; configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000; configuration.channelCount = 1
        configuration.captureMicrophone = mode.recordsMicrophone
        configuration.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let stream = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if mode.recordsMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        self.stream = stream
        try await stream.startCapture()
    }

    func setPaused(_ value: Bool) {
        queue.sync { paused = value }
    }

    func stop() async -> Double {
        lock.withLock { stopping = true }
        if let stream {
            try? await stream.stopCapture()
        }
        microphone?.inputNode.removeTap(onBus: 0); microphone?.stop(); microphone = nil
        let duration = queue.sync {
            let frames = writers.values.map(\.frames).max() ?? 0
            writers.removeAll(); converters.removeAll()
            return Double(frames) / 16000
        }
        stream = nil
        return duration
    }

    func stream(_: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sample.isValid, type == .audio || type == .microphone,
              let description = sample.formatDescription,
              var asbd = description.audioStreamBasicDescription,
              let inputFormat = AVAudioFormat(streamDescription: &asbd) else { return }
        do {
            try sample.withAudioBufferList { buffers, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: buffers.unsafePointer) else { return }
                write(buffer, source: type == .audio ? "system" : "mic", timestamp: sample.presentationTimeStamp)
            }
        } catch { recordFailure(error.localizedDescription) }
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        if !lock.withLock({ stopping }) {
            recordFailure("录音中断：\(error.localizedDescription)")
        }
    }

    private func recordFailure(_ text: String) {
        lock.withLock {
            if failure == nil {
                failure = text
            }
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer, source: String, timestamp: CMTime?) {
        guard let writer = writers[source] else { return }
        guard advanceTimeline(timestamp) else { return }
        do {
            if let timestamp, let origin {
                let expected = max(0, (timestamp - origin).seconds - skipped) * 16000
                if expected.isFinite, expected > Double(writer.frames) + 1600 {
                    try writer.silence(frames: UInt64(expected) - writer.frames)
                }
            }
            guard let converted = try convert(buffer, source: source) else { return }
            let audio = converted.audioBufferList.pointee.mBuffers
            guard let bytes = audio.mData, audio.mDataByteSize > 0 else { return }
            let count = Int(converted.frameLength)
            let samples = bytes.assumingMemoryBound(to: Int16.self)
            var energy: Double = 0
            for i in 0 ..< count {
                let x = Double(samples[i]) / 32768; energy += x * x
            }
            let db = Float(10 * log10(max(energy / Double(max(1, count)), 1e-16)))
            lock.withLock { power = max(db, power - 4) }
            try writer.append(Data(bytes: bytes, count: Int(audio.mDataByteSize)))
        } catch { recordFailure("录音写入失败：\(error.localizedDescription)") }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, source: String) throws -> AVAudioPCMBuffer? {
        let converter: AVAudioConverter
        if let existing = converters[source], existing.inputFormat == buffer.format {
            converter = existing
        } else {
            guard let created = AVAudioConverter(from: buffer.format, to: format) else { return nil }
            converters[source] = created; converter = created
        }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 128)
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, state in
            if supplied {
                state.pointee = .noDataNow; return nil
            }
            supplied = true; state.pointee = .haveData; return buffer
        }
        if status == .error {
            throw error ?? MeetingEngineError.failed("音频转换失败")
        }
        return converted
    }

    private func advanceTimeline(_ timestamp: CMTime?) -> Bool {
        if paused {
            if pauseStart == nil {
                pauseStart = timestamp
            }; return false
        }
        if let pauseStart, let timestamp {
            skipped += max(0, (timestamp - pauseStart).seconds); self.pauseStart = nil
        }
        if origin == nil {
            origin = timestamp
        }
        return true
    }
}
