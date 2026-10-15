import AVFoundation
import Foundation
@testable import Jarvis
import XCTest

final class MeetingAudioWaveformTests: XCTestCase {
    func testTheEnvelopeFollowsHowLoudTheRecordingIs() async throws {
        // Half a second of quiet, a second of tone, half a second of quiet again.
        let url = try writeTestAudio(loudFraction: 0.25 ... 0.75)
        let waveform = await store().waveform(for: url)
        let peaks = try XCTUnwrap(waveform).peaks

        XCTAssertEqual(peaks.count, MeetingAudioWaveform.bucketCount)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1 }, "柱子高度是 0 到 1")

        let quiet = peaks.prefix(peaks.count / 8).max() ?? 1
        let middle = peaks[(peaks.count * 4) / 10 ... (peaks.count * 6) / 10].max() ?? 0
        XCTAssertGreaterThan(middle, quiet + 0.2, "中间那段音调应该明显比两头的静音高")
    }

    func testASilentRecordingHasNoVisibleBars() async throws {
        let url = try writeTestAudio(loudFraction: nil)
        let waveform = await store().waveform(for: url)
        let peaks = try XCTUnwrap(waveform).peaks

        XCTAssertEqual(peaks.count, MeetingAudioWaveform.bucketCount)
        XCTAssertLessThan(peaks.max() ?? 1, 0.05, "全静音不该画出柱子")
    }

    func testTheEnvelopeIsCachedOnDiskSoItIsDecodedOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-waveform-\(UUID().uuidString)", isDirectory: true)
        let url = try writeTestAudio(loudFraction: 0.4 ... 0.6)

        let built = await MeetingAudioWaveformStore(cacheDirectory: directory).waveform(for: url)
        let first = try XCTUnwrap(built)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1, "解出来的包络要落盘")

        // A fresh store, as after a relaunch, reads the file instead of decoding again.
        let reloaded = await MeetingAudioWaveformStore(cacheDirectory: directory).waveform(for: url)
        let second = try XCTUnwrap(reloaded)
        XCTAssertEqual(first, second)

        try? FileManager.default.removeItem(at: directory)
    }

    func testTheCacheKeyFollowsTheFileNotJustItsName() async throws {
        let url = try writeTestAudio(loudFraction: nil)
        // Rewriting the file in place must not keep the old envelope.
        let rewritten = try writeTestAudio(loudFraction: 0.2 ... 0.8, at: url)
        XCTAssertEqual(url, rewritten)

        let waveform = await store().waveform(for: url)
        let peaks = try XCTUnwrap(waveform).peaks
        XCTAssertGreaterThan(peaks.max() ?? 0, 0.5, "改过的文件要重新解码")
    }

    func testDecibelsBecomeBarHeights() {
        XCTAssertEqual(MeetingAudioLevel.normalized(nil), 0)
        XCTAssertEqual(MeetingAudioLevel.normalized(-60), 0)
        XCTAssertEqual(MeetingAudioLevel.normalized(-30), 0.5, accuracy: 0.001)
        XCTAssertEqual(MeetingAudioLevel.normalized(0), 1)
        XCTAssertEqual(MeetingAudioLevel.normalized(6), 1, "超过满刻度也只是一整根柱子")
    }

    // MARK: - Helpers

    private func store() -> MeetingAudioWaveformStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-waveform-\(UUID().uuidString)", isDirectory: true)
        return MeetingAudioWaveformStore(cacheDirectory: directory)
    }

    /// Writes a short mono WAV: a 440 Hz tone where `loudFraction` says, silence elsewhere.
    @discardableResult
    private func writeTestAudio(
        loudFraction: ClosedRange<Double>?,
        at existing: URL? = nil
    ) throws -> URL {
        let url = existing ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-test-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(format.sampleRate * 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0 ..< Int(frames) {
            let position = Double(frame) / Double(frames)
            let isLoud = loudFraction.map { $0.contains(position) } ?? false
            samples[frame] = isLoud
                ? 0.8 * Float(sin(2 * Double.pi * 440 * Double(frame) / format.sampleRate))
                : 0
        }
        try file.write(from: buffer)
        return url
    }
}
