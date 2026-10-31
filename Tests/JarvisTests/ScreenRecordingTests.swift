import AppKit
import AVFoundation
@testable import Jarvis
import XCTest

final class ScreenRecordingTests: XCTestCase {
    func testOlderSettingsRemainDecodableWithoutMouseClickPreference() throws {
        let original = ScreenRecordingSettings()
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "showsMouseClicks")
        object["countdown"] = 5
        let decoded = try JSONDecoder().decode(ScreenRecordingSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.showsMouseClicks)
        XCTAssertEqual(decoded.countdown, 5)
        XCTAssertEqual(decoded.systemAudio, original.systemAudio)
    }

    @MainActor
    func testNewRecordingsUseManagedJarvisStorage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = ScreenRecordingCoordinator(repository: ScreenRecordingRepository(root: root))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ScreenRecordingSettings())) as? [String: Any])
        legacy["directoryPath"] = "/tmp/legacy-recording-directory"
        coordinator.settings = try JSONDecoder().decode(ScreenRecordingSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(coordinator.outputDirectory, root.appendingPathComponent("Videos", isDirectory: true))
    }

    func testQualityCapsRetinaAndPortraitWithoutUpscalingOrStretching() {
        XCTAssertEqual(
            ScreenRecordingQuality.fullHD.outputSize(for: CGSize(width: 5120, height: 2880)),
            CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(
            ScreenRecordingQuality.fullHD.outputSize(for: CGSize(width: 1440, height: 2560)),
            CGSize(width: 606, height: 1080)
        )
        XCTAssertEqual(
            ScreenRecordingQuality.hd.outputSize(for: CGSize(width: 301, height: 201)),
            CGSize(width: 300, height: 200)
        )
        XCTAssertEqual(
            ScreenRecordingQuality.original.outputSize(for: CGSize(width: 5119, height: 2879)),
            CGSize(width: 5118, height: 2878)
        )
    }

    func testRegionMappingUsesDisplayLocalCoordinatesAndTopLeftCaptureOrigin() {
        // Display can have a negative global x/y; only its local rect enters this mapping.
        let selected = CGRect(x: 100, y: 200, width: 800, height: 450)
        XCTAssertEqual(
            ScreenRecordingGeometry.sourceRect(from: selected, screenHeight: 900),
            CGRect(x: 100, y: 250, width: 800, height: 450)
        )
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ScreenRecordingGeometry.sourceRect(from: full, screenHeight: 900), full)
        XCTAssertNil(ScreenRecordingGeometry.validRegion(CGRect(x: 0, y: 0, width: 12, height: 40), in: full))
        XCTAssertEqual(
            ScreenRecordingGeometry.validRegion(CGRect(x: 1400, y: 850, width: 100, height: 100), in: full),
            CGRect(x: 1400, y: 850, width: 40, height: 50)
        )
    }

    func testWindowMarkerMappingHandlesDisplaysAboveAndLeftOfMainScreen() {
        XCTAssertEqual(
            ScreenRecordingGeometry.windowFrame(CGRect(x: -1200, y: -800, width: 800, height: 600), desktopTop: 900),
            CGRect(x: -1200, y: 1100, width: 800, height: 600)
        )
        XCTAssertEqual(
            ScreenRecordingGeometry.windowFrame(CGRect(x: 100, y: 200, width: 800, height: 450), desktopTop: 900),
            CGRect(x: 100, y: 250, width: 800, height: 450)
        )
    }

    func testIndependentManifestsPreserveIncompleteSessionsAndChronologicalOrder() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ScreenRecordingRepository(root: root)
        var first = record(directory: root)
        first.createdAt = Date(timeIntervalSince1970: 10)
        var second = record(directory: root)
        second.createdAt = Date(timeIntervalSince1970: 20)
        second.completed = true
        try repository.save(first)
        try repository.save(second)
        XCTAssertEqual(repository.load(), [second, first])
        try Data([1, 2, 3]).write(to: repository.segment(first.id, index: 10))
        try Data([4, 5, 6]).write(to: repository.segment(first.id, index: 2))
        XCTAssertEqual(repository.segments(first.id).map(\.lastPathComponent), ["segment-000002.mp4", "segment-000010.mp4"])
        XCTAssertFalse(try XCTUnwrap(repository.load().last).completed)
    }

    func testSegmentAssemblyProducesContinuousPlayableMovieAndPreservesAudio() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.mp4")
        let second = root.appendingPathComponent("second.mp4")
        try await Self.writeMovie(at: first, red: true)
        try await Self.writeMovie(at: second, red: false)
        let withAudio = root.appendingPathComponent("with-audio.mp4")
        try await addAudio(to: second, output: withAudio, directory: root)
        let corruptTail = root.appendingPathComponent("interrupted.mp4")
        try Data([1, 2, 3]).write(to: corruptTail)
        let destination = root.appendingPathComponent("final.mp4")
        let duration = try await ScreenRecordingAssembler.assemble(
            segments: [first, withAudio, corruptTail],
            destination: destination,
            allowIncompleteSegments: true
        )
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        let asset = AVURLAsset(url: destination)
        let finalDuration = try await asset.load(.duration)
        XCTAssertEqual(finalDuration.seconds, 2, accuracy: 0.1)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioRange = try await XCTUnwrap(audioTracks.first).load(.timeRange)
        XCTAssertGreaterThan(audioRange.duration.seconds, 0.8)
        let reader = AVAssetImageGenerator(asset: asset)
        let image = try await reader.image(at: CMTime(seconds: 1.5, preferredTimescale: 600))
        XCTAssertEqual(image.image.width, 160)
    }

    func testAssemblerDoesNotOverwriteAnExistingFileOrRemoveRecoverySources() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mp4")
        try await Self.writeMovie(at: source, red: true)
        let destination = root.appendingPathComponent("existing.mp4")
        let sentinel = Data("existing user file".utf8)
        try sentinel.write(to: destination)
        do {
            _ = try await ScreenRecordingAssembler.assemble(segments: [source], destination: destination)
            XCTFail("Must not overwrite user data")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: destination), sentinel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testFailedRecoveryKeepsManifestAndSegmentsAndReleasesBusyState() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ScreenRecordingRepository(root: root)
        let pending = record(directory: root)
        try repository.save(pending)
        let part = repository.segment(pending.id, index: 0)
        try Data([0, 1, 2]).write(to: part)
        let coordinator = ScreenRecordingCoordinator(repository: repository)
        await coordinator.recover(pending)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(coordinator.recoverableRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path))
        XCTAssertFalse(try XCTUnwrap(repository.load().first).completed)
        XCTAssertTrue(coordinator.message?.contains("恢复失败") == true)
    }

    @MainActor
    func testSuccessfulRecoveryCommitsMovieBeforeRemovingRecoverySources() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ScreenRecordingRepository(root: root)
        let pending = record(directory: root)
        try repository.save(pending)
        try await Self.writeMovie(at: repository.segment(pending.id, index: 0), red: true)
        let coordinator = ScreenRecordingCoordinator(repository: repository)
        await coordinator.recover(pending)
        let completed = try XCTUnwrap(repository.load().first)
        XCTAssertTrue(completed.completed)
        XCTAssertTrue(completed.exists)
        XCTAssertGreaterThan(completed.byteCount, 0)
        XCTAssertEqual(completed.duration, 1, accuracy: 0.1)
        XCTAssertTrue(repository.segments(pending.id).isEmpty)
    }

    @MainActor
    func testRecoveryNeverAdoptsAnExistingDestinationAndDeletesItsSources() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ScreenRecordingRepository(root: root)
        let pending = record(directory: root)
        try repository.save(pending)
        try await Self.writeMovie(at: pending.fileURL, red: true)
        let original = try Data(contentsOf: pending.fileURL)
        let source = repository.segment(pending.id, index: 0)
        try await Self.writeMovie(at: source, red: false)
        let coordinator = ScreenRecordingCoordinator(repository: repository)
        await coordinator.recover(pending)
        XCTAssertFalse(try XCTUnwrap(repository.load().first).completed)
        XCTAssertEqual(try Data(contentsOf: pending.fileURL), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(coordinator.isActive)
    }

    func testNormalExportRejectsAnUnfinalizedSegmentInsteadOfSilentlyTruncating() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appendingPathComponent("valid.mp4")
        let corrupt = root.appendingPathComponent("corrupt.mp4")
        try await Self.writeMovie(at: valid, red: true)
        try Data([0, 1, 2]).write(to: corrupt)
        let output = root.appendingPathComponent("output.mp4")
        do {
            _ = try await ScreenRecordingAssembler.assemble(segments: [valid, corrupt], destination: output)
            XCTFail("Normal export must not silently discard a segment")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: valid.path))
    }

    private func record(directory: URL) -> ScreenRecordingRecord {
        ScreenRecordingRecord(
            id: UUID(),
            title: "测试录制",
            createdAt: Date(),
            mode: .region,
            targetName: "测试显示器",
            settings: ScreenRecordingSettings(),
            width: 160,
            height: 90,
            filePath: directory.appendingPathComponent("final.mp4").path
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-screen-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func writeMovie(at url: URL, red: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< 30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let context = try XCTUnwrap(CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: 160,
                height: 90,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ))
            context.setFillColor(red ? CGColor(red: 1, green: 0, blue: 0, alpha: 1) : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(value: 30, timescale: 30))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func addAudio(to videoURL: URL, output: URL, directory: URL) async throws {
        let audioURL = directory.appendingPathComponent("tone.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        try writeTone(at: audioURL, format: format)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        defer { withExtendedLifetime((videoAsset, audioAsset)) {} }
        let videoSources = try await videoAsset.loadTracks(withMediaType: .video)
        let audioSources = try await audioAsset.loadTracks(withMediaType: .audio)
        let sourceVideo = try XCTUnwrap(videoSources.first)
        let sourceAudio = try XCTUnwrap(audioSources.first)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        let videoTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let audioTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
        try audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
        let export = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        try await export.export(to: output, as: .mp4)
    }

    private func writeTone(at url: URL, format: AVAudioFormat) throws {
        // AVAudioFile seals the CAF header on deinit, before the fixture is read as an asset.
        let audio = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
        buffer.frameLength = 48000
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0 ..< 48000 {
            samples[index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000) * 0.2)
        }
        try audio.write(from: buffer)
    }
}
