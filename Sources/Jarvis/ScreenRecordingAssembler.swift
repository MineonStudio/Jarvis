import AVFoundation
import Foundation

enum ScreenRecordingAssembler {
    /// Decode only for export. Collection never accumulates raw video frames in memory.
    static func assemble(segments: [URL], destination: URL, hevc: Bool = false, allowIncompleteSegments: Bool = false) async throws -> Double {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenRecordingError.message("无法创建视频轨道。")
        }
        var audioTracks: [Int: AVMutableCompositionTrack] = [:]
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            defer { withExtendedLifetime(asset) {} }
            // An unfinalized crash tail can be unreadable. Recover finalized preceding segments.
            guard let source = try? await asset.loadTracks(withMediaType: .video).first,
                  let range = try? await source.load(.timeRange), range.duration.seconds > 0
            else {
                if allowIncompleteSegments {
                    continue
                }
                throw ScreenRecordingError.message("视频片段未完成封装，请使用历史中的恢复功能保留可用部分。")
            }
            try video.insertTimeRange(range, of: source, at: cursor)
            try await appendAudio(from: asset, to: composition, tracks: &audioTracks, range: range, cursor: cursor)
            try await appendSystemAudio(
                videoURL: url, to: composition, tracks: &audioTracks,
                placement: (range.duration, cursor), allowIncomplete: allowIncompleteSegments
            )
            cursor = CMTimeAdd(cursor, range.duration)
        }
        guard cursor.seconds > 0 else { throw ScreenRecordingError.message("没有可恢复的视频片段。") }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ScreenRecordingError.message("目标文件已经存在，请选择其他保存位置。")
        }
        let preset = hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ScreenRecordingError.message("无法创建视频导出任务。")
        }
        if !audioTracks.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioTracks.keys.sorted().compactMap { key in
                guard let track = audioTracks[key] else { return nil }
                let input = AVMutableAudioMixInputParameters(track: track)
                input.setVolume(1, at: .zero)
                return input
            }
            exporter.audioMix = mix
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: destination, as: .mp4)
        return cursor.seconds
    }

    private static func appendSystemAudio(
        videoURL: URL,
        to composition: AVMutableComposition,
        tracks: inout [Int: AVMutableCompositionTrack],
        placement: (duration: CMTime, cursor: CMTime),
        allowIncomplete: Bool
    ) async throws {
        let url = ScreenRecordingAudioTiming.audioURL(for: videoURL)
        let expected = FileManager.default.fileExists(atPath: ScreenRecordingAudioTiming.metadataURL(for: videoURL).path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if expected, !allowIncomplete {
                throw ScreenRecordingError.message("系统音频片段缺失，已保留视频片段供恢复。")
            }
            return
        }
        do {
            let asset = AVURLAsset(url: url)
            defer { withExtendedLifetime(asset) {} }
            let timing = try ScreenRecordingAudioTiming.load(for: videoURL)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw ScreenRecordingError.message("系统音频片段无有有效音轨。")
            }
            let range = try await source.load(.timeRange)
            guard let aligned = timing.alignedRange(audioRange: range, videoDuration: placement.duration) else { return }
            let output: AVMutableCompositionTrack
            if let track = tracks[1000] {
                output = track
            } else {
                guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw ScreenRecordingError.message("无法创建系统音频轨道。")
                }
                tracks[1000] = track
                output = track
            }
            try output.insertTimeRange(aligned.range, of: source, at: CMTimeAdd(placement.cursor, aligned.destination))
        } catch {
            if !allowIncomplete {
                throw error
            }
        }
    }

    private static func appendAudio(
        from asset: AVURLAsset,
        to composition: AVMutableComposition,
        tracks: inout [Int: AVMutableCompositionTrack],
        range: CMTimeRange,
        cursor: CMTime
    ) async throws {
        for (index, track) in try await asset.loadTracks(withMediaType: .audio).enumerated() {
            let output: AVMutableCompositionTrack
            if let existing = tracks[index] {
                output = existing
            } else {
                guard let newTrack = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw ScreenRecordingError.message("无法创建音频轨道。") }
                tracks[index] = newTrack
                output = newTrack
            }
            let audioRange = try await track.load(.timeRange).intersection(range)
            if audioRange.duration.seconds > 0 {
                let offset = CMTimeSubtract(audioRange.start, range.start)
                try output.insertTimeRange(audioRange, of: track, at: CMTimeAdd(cursor, offset))
            }
        }
    }
}
