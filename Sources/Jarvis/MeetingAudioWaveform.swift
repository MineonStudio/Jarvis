import AVFoundation
import Foundation

/// The loudness envelope of a recording: one value per drawn bar, 0...1.
struct MeetingAudioWaveform: Codable, Equatable, Sendable {
    /// Few and thick on purpose. A bar per few milliseconds reads as noise across a card;
    /// this is the shape of the meeting, not its waveform.
    static let bucketCount = 140

    var peaks: [Float]
}

enum MeetingAudioLevel {
    /// Decibels as the recorder reports them, turned into a 0...1 bar height.
    /// -60 dB and below counts as silence.
    static func normalized(_ power: Float?) -> Double {
        guard let power else { return 0 }
        let clamped = min(0, max(-60, power))
        return Double((clamped + 60) / 60)
    }
}

/// Builds waveforms off the main actor and keeps them.
///
/// Decoding a meeting takes seconds — roughly 220× realtime, so about four seconds for
/// fifteen minutes of audio — which is far too slow to do while drawing, and the same file
/// is opened every time the meeting is selected. The result is therefore computed once in
/// the background and kept in memory and beside the app's cache.
actor MeetingAudioWaveformStore {
    static let shared = MeetingAudioWaveformStore()

    private let cacheDirectory: URL?
    private var memory: [String: MeetingAudioWaveform] = [:]

    /// `cacheDirectory` is injectable so a test can keep its decoded envelopes to itself.
    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory
    }

    /// A waveform already computed, without waiting for anything.
    func cached(for url: URL?) -> MeetingAudioWaveform? {
        guard let url else { return nil }
        return memory[Self.identifier(for: url)]
    }

    /// Decodes on the caller's task rather than on a detached one: the decode is long, and
    /// this way leaving the meeting abandons it instead of burning a core for a view that
    /// is gone. Nothing is cached for a recording that was never read to the end.
    func waveform(for url: URL) async -> MeetingAudioWaveform? {
        let key = Self.identifier(for: url)
        if let ready = memory[key] {
            return ready
        }
        let directory = cacheDirectory ?? Self.defaultCacheDirectory
        if let stored = Self.readFromCache(key: key, directory: directory), !stored.peaks.isEmpty {
            memory[key] = stored
            return stored
        }
        guard let built = Self.decode(url: url), !built.peaks.isEmpty else { return nil }
        guard !Task.isCancelled else { return nil }
        memory[key] = built
        Self.writeToCache(built, key: key, directory: directory)
        return built
    }

    /// The file's identity, so a re-encoded recording does not keep an old envelope.
    private static func identifier(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        // Sub-second precision on purpose: re-mixing a recording can produce the same
        // number of bytes a moment later, and the envelope must not survive that.
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        // The bar count is part of the identity, so a cached envelope drawn for a different
        // resolution is never reused after the drawing changes.
        return "\(url.lastPathComponent)-\(size)-\(Int(modified * 1000))-\(MeetingAudioWaveform.bucketCount)"
    }

    // MARK: - Decoding

    private static func decode(url: URL) -> MeetingAudioWaveform? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let total = AVAudioFramePosition(file.length)
        let channelCount = Int(format.channelCount)
        guard total > 0, channelCount > 0 else { return nil }

        let bucketCount = MeetingAudioWaveform.bucketCount
        let framesPerBucket = Double(total) / Double(bucketCount)
        let chunk = AVAudioFrameCount(65536)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }

        var peaks = [Float](repeating: 0, count: bucketCount)
        var processed: AVAudioFramePosition = 0
        while processed < total {
            // Checked per chunk: the caller may have moved to another meeting.
            if Task.isCancelled {
                return nil
            }
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: chunk)) != nil else { break }
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            let frames = Int(buffer.frameLength)
            for frame in 0 ..< frames {
                var value: Float = 0
                for channel in 0 ..< channelCount {
                    let sample = abs(channels[channel][frame])
                    if sample > value {
                        value = sample
                    }
                }
                let offset = Double(processed + AVAudioFramePosition(frame))
                let index = min(bucketCount - 1, Int(offset / framesPerBucket))
                if value > peaks[index] {
                    peaks[index] = value
                }
            }
            processed += AVAudioFramePosition(frames)
        }
        guard processed > 0 else { return nil }
        return MeetingAudioWaveform(peaks: shaped(peaks))
    }

    /// Speech is spiky: scaling by the loudest moment and drawing that linearly leaves
    /// everything else flat, so the ratio is curved before it becomes a bar height.
    private static func shaped(_ peaks: [Float]) -> [Float] {
        guard let loudest = peaks.max(), loudest > 0 else { return peaks }
        return peaks.map { peak in
            let ratio = min(1, max(0, peak / loudest))
            return pow(ratio, 0.65)
        }
    }

    // MARK: - Cache

    private static var defaultCacheDirectory: URL {
        JarvisAppDirectory.url("Cache").appendingPathComponent("Waveforms", isDirectory: true)
    }

    private static func readFromCache(key: String, directory: URL) -> MeetingAudioWaveform? {
        let url = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MeetingAudioWaveform.self, from: data)
    }

    private static func writeToCache(_ waveform: MeetingAudioWaveform, key: String, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(waveform) else { return }
        try? data.write(to: directory.appendingPathComponent("\(key).json"), options: .atomic)
        pruneCache(directory: directory)
    }

    /// Deleting a meeting removes its recording but not this file, and a re-encode adds
    /// another, so the directory is capped rather than left to grow.
    private static func pruneCache(directory: URL, limit: Int = 200) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              names.count > limit
        else { return }
        let entries = names.compactMap { name -> (URL, Date)? in
            let url = directory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url, modified)
        }
        for (url, _) in entries.sorted(by: { $0.1 < $1.1 }).prefix(entries.count - limit) {
            try? fileManager.removeItem(at: url)
        }
    }
}
