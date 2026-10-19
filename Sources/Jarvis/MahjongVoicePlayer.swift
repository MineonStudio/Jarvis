import AVFoundation
import Foundation

@MainActor
final class MahjongVoicePlayer {
    static let shared = MahjongVoicePlayer()

    private let player = AVQueuePlayer()

    private init() {}

    func play(_ cue: String, gender: MahjongVoiceGender) {
        let audioDirectory = "MahjongAudio/\(gender.rawValue)"
        let url = Bundle.main.url(forResource: cue, withExtension: "mp3", subdirectory: audioDirectory)
            ?? Bundle.main.url(forResource: cue, withExtension: "m4a", subdirectory: audioDirectory)
        guard let url else { return }
        player.volume = 0.9
        player.insert(AVPlayerItem(url: url), after: nil)
        if player.rate == 0 { player.play() }
    }
}
