import AVFoundation
@testable import Jarvis
import XCTest

final class ScreenRecordingSystemAudioTests: XCTestCase {
    func testIndependentSystemAudioIsInsertedAtItsHostClockOffset() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("window.mp4")
        try await ScreenRecordingTests.writeMovie(at: video, red: true)
        try writeTone(to: ScreenRecordingAudioTiming.audioURL(for: video), duration: 1, silence: 0)
        try ScreenRecordingAudioTiming(offset: 0.3).save(for: video)
        let output = root.appendingPathComponent("result.mp4")
        let duration = try await ScreenRecordingAssembler.assemble(segments: [video], destination: output)
        XCTAssertEqual(duration, 1, accuracy: 0.05)
        let audio = try await readAudio(output)
        XCTAssertLessThan(audio.rms(from: 0.05, to: 0.15), 0.003)
        XCTAssertGreaterThan(audio.rms(from: 0.5, to: 0.7), 0.05)
    }

    func testAudioRecordedBeforeTheFirstVideoFrameIsTrimmed() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("window.mp4")
        try await ScreenRecordingTests.writeMovie(at: video, red: true)
        try writeTone(to: ScreenRecordingAudioTiming.audioURL(for: video), duration: 1.5, silence: 0.25)
        try ScreenRecordingAudioTiming(offset: -0.25).save(for: video)
        let output = root.appendingPathComponent("result.mp4")
        _ = try await ScreenRecordingAssembler.assemble(segments: [video], destination: output)
        let audio = try await readAudio(output)
        XCTAssertGreaterThan(audio.rms(from: 0.08, to: 0.18), 0.05)
    }

    func testMicrophoneAndIndependentSystemAudioAreBothMixedIntoTheExport() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let silentVideo = root.appendingPathComponent("silent.mp4")
        let microphone = root.appendingPathComponent("microphone.caf")
        let video = root.appendingPathComponent("window.mp4")
        try await ScreenRecordingTests.writeMovie(at: silentVideo, red: true)
        try writeTone(to: microphone, duration: 1, silence: 0, frequency: 440)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silentVideo)
        let microphoneAsset = AVURLAsset(url: microphone)
        defer { withExtendedLifetime((videoAsset, microphoneAsset)) {} }
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let microphoneTracks = try await microphoneAsset.loadTracks(withMediaType: .audio)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        let outputVideo = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let outputMic = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try outputVideo.insertTimeRange(range, of: XCTUnwrap(videoTracks.first), at: .zero)
        try outputMic.insertTimeRange(range, of: XCTUnwrap(microphoneTracks.first), at: .zero)
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        try await exporter.export(to: video, as: .mp4)
        try writeTone(to: ScreenRecordingAudioTiming.audioURL(for: video), duration: 1, silence: 0, frequency: 880)
        try ScreenRecordingAudioTiming(offset: 0).save(for: video)
        let output = root.appendingPathComponent("result.mp4")
        _ = try await ScreenRecordingAssembler.assemble(segments: [video], destination: output)
        let audio = try await readAudio(output)
        XCTAssertGreaterThan(audio.amplitude(at: 440), 0.1)
        XCTAssertGreaterThan(audio.amplitude(at: 880), 0.1)
    }

    func testMissingExpectedAudioDoesNotSilentlyCreateASilentMovie() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("window.mp4")
        try await ScreenRecordingTests.writeMovie(at: video, red: true)
        try ScreenRecordingAudioTiming(offset: 0).save(for: video)
        let output = root.appendingPathComponent("result.mp4")
        do {
            _ = try await ScreenRecordingAssembler.assemble(segments: [video], destination: output)
            XCTFail("An expected but missing system audio source must be reported")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
    }

    func testSuccessfulCleanupRemovesAudioAndTimingAlongWithVideoSegments() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ScreenRecordingRepository(root: root)
        let id = UUID()
        try FileManager.default.createDirectory(at: repository.directory(id), withIntermediateDirectories: true)
        let video = repository.segment(id, index: 0)
        try Data([1]).write(to: video)
        try Data([2]).write(to: ScreenRecordingAudioTiming.audioURL(for: video))
        try ScreenRecordingAudioTiming(offset: 0).save(for: video)
        try repository.cleanSegments(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScreenRecordingAudioTiming.audioURL(for: video).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScreenRecordingAudioTiming.metadataURL(for: video).path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-system-audio-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeTone(to url: URL, duration: Double, silence: Double, frequency: Double = 440) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0 ..< Int(frames) {
            let time = Double(index) / format.sampleRate
            samples[index] = time < silence ? 0 : Float(sin(time * frequency * 2 * .pi) * 0.25)
        }
        try file.write(from: buffer)
    }

    private func readAudio(_ url: URL) async throws -> AudioSamples {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let start = try await XCTUnwrap(tracks.first).load(.timeRange).start.seconds
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        return AudioSamples(
            samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))),
            sampleRate: file.processingFormat.sampleRate, start: start
        )
    }
}

private struct AudioSamples {
    let samples: [Float]
    let sampleRate: Double
    let start: Double

    func amplitude(at frequency: Double) -> Double {
        let first = Int(sampleRate * 0.1), last = min(samples.count, Int(sampleRate * 0.8))
        guard last > first else { return 0 }
        var real = 0.0, imaginary = 0.0
        for index in first ..< last {
            let angle = 2 * Double.pi * frequency * Double(index) / sampleRate
            real += Double(samples[index]) * cos(angle)
            imaginary += Double(samples[index]) * sin(angle)
        }
        return 2 * hypot(real, imaginary) / Double(last - first)
    }

    func rms(from begin: Double, to end: Double) -> Double {
        let first = max(0, Int((begin - start) * sampleRate))
        let last = min(samples.count, max(0, Int((end - start) * sampleRate)))
        guard last > first else { return 0 }
        let sum = samples[first ..< last].reduce(0.0) { $0 + Double($1 * $1) }
        return sqrt(sum / max(1, (end - begin) * sampleRate))
    }
}
