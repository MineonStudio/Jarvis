import Foundation

@MainActor
final class MahjongVoicePlayer {
    static let shared = MahjongVoicePlayer()
    private init() {}

    func play(_ cue: String, gender: MahjongVoiceGender, seat: Int? = nil, localSeat: Int = 0) {
        MahjongAudioPlayer.shared.playVoice(cue, gender: gender, seat: seat, localSeat: localSeat)
    }

    func preview(gender: MahjongVoiceGender) {
        MahjongAudioPlayer.shared.playVoice("action-win", gender: gender, preview: true)
    }
}
