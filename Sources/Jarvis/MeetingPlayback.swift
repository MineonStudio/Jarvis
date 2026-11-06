import AVFoundation
import Foundation
import Observation

@Observable @MainActor
final class MeetingPlayback {
    private var player: AVAudioPlayer?
    private var previewEnd: Double?
    private var previewTask: Task<Void, Never>?
    private(set) var previewSpeakerID: String?
    var position: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var requestedTime: Double?
    private(set) var seekRequestID = 0
    var available = false
    func load(_ url: URL?) {
        clearPreview()
        requestedTime = nil
        player?.stop(); player = nil; position = 0; duration = 0; isPlaying = false; available = false
        guard let url, let audio = try? AVAudioPlayer(contentsOf: url) else { return }
        player = audio; audio.prepareToPlay(); duration = audio.duration; available = duration > 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause(); previewTask?.cancel()
        } else {
            if player.currentTime >= duration {
                player.currentTime = 0
            }
            player.play()
            schedulePreviewEnd()
        }
        refresh()
    }

    func isPlayingSource(at time: Double?) -> Bool {
        guard let time else { return false }
        return isPlaying && previewSpeakerID == nil && requestedTime == time
    }

    func toggleSource(at time: Double) {
        if isPlayingSource(at: time) {
            player?.pause(); refresh()
        } else {
            seekAndPlay(time)
        }
    }

    func seek(_ time: Double) {
        clearPreview()
        player?.currentTime = min(duration, max(0, time)); refresh()
    }

    func seekAndPlay(_ time: Double) {
        requestedTime = time; seekRequestID += 1; seek(time); player?.play(); refresh()
    }

    func isPreviewingSpeaker(_ speakerID: String) -> Bool {
        isPlaying && previewSpeakerID == speakerID
    }

    func toggleSpeakerPreview(_ speakerID: String, _ segment: MeetingTranscriptSegment) {
        guard let player, let range = MeetingSpeakerPreview.range(for: segment, duration: duration) else { return }
        if isPreviewingSpeaker(speakerID) {
            player.pause(); previewTask?.cancel(); refresh()
            return
        }
        clearPreview()
        previewSpeakerID = speakerID
        previewEnd = range.upperBound
        requestedTime = nil
        player.currentTime = range.lowerBound
        player.play()
        refresh()
        schedulePreviewEnd()
    }

    func refresh() {
        if let end = previewEnd, let player, player.currentTime >= end {
            player.pause()
            player.currentTime = end
            clearPreview()
        }
        position = player?.currentTime ?? 0
        isPlaying = player?.isPlaying ?? false
    }

    func stop() {
        clearPreview(); player?.stop(); isPlaying = false
    }

    private func clearPreview() {
        previewTask?.cancel(); previewTask = nil
        previewEnd = nil; previewSpeakerID = nil
    }

    private func schedulePreviewEnd() {
        previewTask?.cancel()
        guard previewEnd != nil else { return }
        previewTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player, let end = self.previewEnd else { return }
                if !player.isPlaying {
                    player.currentTime = end
                    self.clearPreview(); self.refresh()
                    return
                }
                let remaining = end - player.currentTime
                if remaining <= 0 {
                    self.refresh(); return
                }
                do { try await Task.sleep(for: .seconds(max(0.01, remaining))) } catch { return }
            }
        }
    }
}
