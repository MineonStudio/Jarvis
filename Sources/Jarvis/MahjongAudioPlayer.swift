import AVFoundation
import Foundation

/// Action sounds start immediately, with one effect and one voice at most.
@MainActor
final class MahjongAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = MahjongAudioPlayer()
    let settings = MahjongAudioSettings.shared
    private(set) var sessionActive = false
    private var focused = true
    private var music: AVAudioPlayer?
    private var effect: (player: AVAudioPlayer, sound: MahjongSoundEffect)?
    private var gate = MahjongEffectGate()
    private var voice: AVAudioPlayer?
    private var currentVoice: MahjongVoiceRequest?

    override private init() {
        super.init()
        settings.onChange = { [weak self] in self?.applySettings() }
    }

    private var audible: Bool {
        sessionActive && focused && !settings.isMuted
    }

    func startSession() {
        sessionActive = true
        focused = true
        prepareMusic()
        applySettings()
    }

    func stopSession() {
        sessionActive = false
        music?.stop()
        music = nil
        stopTransientAudio()
        gate = MahjongEffectGate()
    }

    func setFocused(_ value: Bool) {
        focused = value
        applySettings()
    }

    private func prepareMusic() {
        guard music == nil else { return }
        music = makePlayer(name: "happyTable", directory: "music")
        music?.numberOfLoops = -1
        music?.volume = 0
    }

    func play(_ sound: MahjongSoundEffect, seat: Int? = nil, localSeat: Int = 0) {
        guard audible, settings.overallVolume > 0, settings.effectsVolume > 0 else { return }
        let active = effect.flatMap { $0.player.isPlaying ? $0.sound : nil }
        guard gate.admit(sound, at: ProcessInfo.processInfo.systemUptime, active: active, voiceBusy: voice != nil) else { return }
        startEffect(sound, seat: seat, localSeat: localSeat)
    }

    func playVoice(_ key: String, gender: MahjongVoiceGender, seat: Int? = nil, localSeat: Int = 0, preview: Bool = false) {
        guard audible, settings.overallVolume > 0 else { return }
        let request = MahjongVoiceRequest(key: key, gender: gender)
        if preview {
            stopTransientAudio()
        } else if request.priority == 3 {
            stopEffect()
        }
        // The contact belongs to this action, even if its spoken call is suppressed.
        if !preview, let sound = MahjongSoundEffect.forVoice(key), sound != .win || settings.voiceVolume == 0 {
            startEffect(sound, seat: seat, localSeat: localSeat)
        }
        let active = voice?.isPlaying == true ? currentVoice : nil
        guard settings.voiceVolume > 0, request.canInterrupt(active) else { return }
        let directory = "MahjongAudio/\(gender.rawValue)"
        guard let url = Bundle.main.url(forResource: key, withExtension: "mp3", subdirectory: directory)
            ?? Bundle.main.url(forResource: key, withExtension: "m4a", subdirectory: directory),
            let player = try? AVAudioPlayer(contentsOf: url) else { return }
        voice?.stop()
        voice = player
        currentVoice = request
        player.delegate = self
        player.volume = Float(settings.overallVolume * settings.voiceVolume)
        if !player.play() {
            voice = nil; currentVoice = nil
        }
        applySettings()
    }

    func resetRound() {
        stopTransientAudio()
        gate = MahjongEffectGate()
        applySettings()
    }

    func previewEffects() {
        guard audible, settings.overallVolume > 0, settings.effectsVolume > 0 else { return }
        stopTransientAudio()
        startEffect(.pong)
    }

    private func startEffect(_ sound: MahjongSoundEffect, seat: Int? = nil, localSeat: Int = 0) {
        guard settings.effectsVolume > 0,
              let name = sound.resourceNames.randomElement(),
              let player = makePlayer(name: name, directory: "effects") else { return }
        stopEffect()
        if let seat {
            let position = (seat - localSeat + 4) % 4
            player.pan = position == 1 ? -0.55 : (position == 3 ? 0.55 : 0)
        }
        player.delegate = self
        player.volume = Float(settings.overallVolume * settings.effectsVolume) * sound.gain
        if player.play() {
            effect = (player, sound)
        }
        applySettings()
    }

    private func applySettings() {
        guard audible, settings.overallVolume > 0 else {
            music?.pause()
            stopTransientAudio()
            return
        }
        if settings.voiceVolume == 0 {
            voice?.stop(); voice = nil; currentVoice = nil
        } else {
            voice?.volume = Float(settings.overallVolume * settings.voiceVolume)
        }
        if settings.effectsVolume == 0 {
            stopEffect()
        } else if let effect {
            let duck: Float = voice?.isPlaying == true ? 0.55 : 1
            effect.player.volume = Float(settings.overallVolume * settings.effectsVolume) * effect.sound.gain * duck
        }
        if settings.musicVolume > 0 {
            if music?.isPlaying == false {
                music?.play()
            }
            let duck: Double = voice != nil ? 0.2 : (effect != nil ? 0.45 : 1)
            music?.setVolume(Float(settings.overallVolume * settings.musicVolume * duck), fadeDuration: 0.15)
        } else {
            music?.pause()
        }
    }

    private func stopEffect() {
        effect?.player.stop()
        effect = nil
    }

    private func stopTransientAudio() {
        voice?.stop(); voice = nil; currentVoice = nil
        stopEffect()
    }

    private func makePlayer(name: String, directory: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "MahjongAudio/\(directory)"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            JarvisLog.error(category: .lifecycle, event: "mahjong.audio.assetUnavailable", fields: ["asset": "\(directory)/\(name)"])
            return nil
        }
        player.prepareToPlay()
        return player
    }

    private func finishedAudio(_ identity: ObjectIdentifier) {
        if let effect, ObjectIdentifier(effect.player) == identity {
            self.effect = nil
            applySettings()
        } else if let voice, ObjectIdentifier(voice) == identity {
            self.voice = nil
            currentVoice = nil
            applySettings()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.finishedAudio(identity) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error _: Error?) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.finishedAudio(identity) }
    }
}
