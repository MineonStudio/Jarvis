import AVFoundation
import Foundation

struct ScreenRecordingAudioTiming: Codable {
    /// Audio timestamp minus the first video timestamp, on the shared host clock.
    let offset: Double

    static func audioURL(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("system.caf")
    }

    static func metadataURL(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("audio.json")
    }

    func save(for video: URL) throws {
        try JarvisProtectedStorage.write(JSONEncoder().encode(self), to: Self.metadataURL(for: video))
    }

    static func load(for video: URL) throws -> Self {
        let url = metadataURL(for: video)
        guard FileManager.default.fileExists(atPath: url.path) else { return Self(offset: 0) }
        let timing = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard timing.offset.isFinite else { throw ScreenRecordingError.message("系统音频时间戳无效。") }
        return timing
    }

    func alignedRange(audioRange: CMTimeRange, videoDuration: CMTime) -> (range: CMTimeRange, destination: CMTime)? {
        let offsetTime = CMTime(seconds: offset, preferredTimescale: 48000)
        let start = CMTimeMaximum(audioRange.start, CMTimeSubtract(.zero, offsetTime))
        let end = CMTimeMinimum(audioRange.end, CMTimeSubtract(videoDuration, offsetTime))
        guard end > start else { return nil }
        return (CMTimeRange(start: start, end: end), CMTimeAdd(start, offsetTime))
    }
}
