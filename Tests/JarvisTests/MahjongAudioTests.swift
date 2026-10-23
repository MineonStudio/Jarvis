import AVFoundation
@testable import Jarvis
import XCTest

@MainActor
final class MahjongAudioTests: XCTestCase {
    func testVolumeSettingsPersistZeroAndClampInvalidValues() throws {
        let name = "MahjongAudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "mahjong.audio.pausesInBackground")
        let settings = MahjongAudioSettings(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "mahjong.audio.pausesInBackground"))
        XCTAssertEqual(settings.overallVolume, 0.5)
        XCTAssertEqual(settings.musicVolume, 0.5)
        XCTAssertEqual(settings.effectsVolume, 0.5)
        XCTAssertEqual(settings.voiceVolume, 0.5)
        settings.musicVolume = 0
        settings.effectsVolume = 2
        settings.voiceVolume = -.infinity
        settings.overallVolume = 0.6
        settings.isMuted = true

        let restored = MahjongAudioSettings(defaults: defaults)
        XCTAssertEqual(restored.musicVolume, 0)
        XCTAssertEqual(restored.effectsVolume, 1)
        XCTAssertEqual(restored.voiceVolume, 0)
        XCTAssertEqual(restored.overallVolume, 0.6)
        XCTAssertTrue(restored.isMuted)
        restored.restoreDefaults()
        XCTAssertEqual(restored.overallVolume, 0.5)
        XCTAssertEqual(restored.musicVolume, 0.5)
        XCTAssertEqual(restored.effectsVolume, 0.5)
        XCTAssertEqual(restored.voiceVolume, 0.5)
        XCTAssertFalse(restored.isMuted)
    }

    func testVoiceCallsReplaceStaleSpeechImmediatelyWithoutWaiting() {
        let firstTile = MahjongVoiceRequest(key: "tile-dots-1", gender: .female)
        let nextTile = MahjongVoiceRequest(key: "tile-dots-2", gender: .male)
        let pass = MahjongVoiceRequest(key: "action-pass", gender: .male)
        let pong = MahjongVoiceRequest(key: "action-pong", gender: .male)
        let win = MahjongVoiceRequest(key: "action-win", gender: .female)

        XCTAssertTrue(firstTile.canInterrupt(nil))
        XCTAssertTrue(nextTile.canInterrupt(firstTile), "The latest discard must not wait for the previous tile name")
        XCTAssertTrue(pong.canInterrupt(nextTile))
        XCTAssertTrue(win.canInterrupt(pong))
        XCTAssertFalse(pass.canInterrupt(nextTile), "A pass must not cut off an actual tile call")
        XCTAssertFalse(nextTile.canInterrupt(pong), "Outdated low priority calls must be dropped")
        XCTAssertFalse(pong.canInterrupt(win))
    }

    func testAllKongVariantsAndTileAnnouncementsHaveMatchingEffects() {
        for key in ["action-kong", "action-exposed-kong", "action-added-kong", "action-concealed-kong"] {
            XCTAssertEqual(MahjongSoundEffect.forVoice(key), .kong)
        }
        XCTAssertEqual(MahjongSoundEffect.forVoice("action-chi"), .chi)
        XCTAssertEqual(MahjongSoundEffect.forVoice("action-pong"), .pong)
        XCTAssertEqual(MahjongSoundEffect.forVoice("tile-bamboo-5"), .tileDiscard)
        XCTAssertEqual(MahjongSoundEffect.forVoice("action-self-draw"), .win)
        XCTAssertEqual(MahjongSoundEffect.forVoice("action-draw"), .win)
        XCTAssertNil(MahjongSoundEffect.forVoice("action-pass"))
        XCTAssertNil(MahjongSoundEffect.forVoice("action-super-double"))
    }

    func testEffectGateDropsOverlapsAndKeepsCallsClear() {
        var gate = MahjongEffectGate()
        XCTAssertTrue(gate.admit(.tileDraw, at: 10, active: nil, voiceBusy: false))
        XCTAssertFalse(gate.admit(.tick, at: 10.02, active: .tileDraw, voiceBusy: false))
        XCTAssertTrue(gate.admit(.pong, at: 10.03, active: .tileDraw, voiceBusy: false))
        XCTAssertFalse(gate.admit(.tileDraw, at: 10.4, active: .pong, voiceBusy: false))
        XCTAssertTrue(gate.admit(.kong, at: 10.7, active: nil, voiceBusy: true))
        XCTAssertFalse(gate.admit(.tileDiscard, at: 10.8, active: nil, voiceBusy: false))
        XCTAssertTrue(gate.admit(.tileDiscard, at: 11, active: nil, voiceBusy: true))
        XCTAssertFalse(gate.admit(.tick, at: 11.5, active: nil, voiceBusy: true))
        XCTAssertTrue(gate.admit(.tileDraw, at: 11.6, active: nil, voiceBusy: true))
    }

    func testDealingIsThrottledEvenAfterPreviousContactFinishes() {
        var gate = MahjongEffectGate()
        XCTAssertTrue(gate.admit(.deal, at: 20, active: nil, voiceBusy: false))
        XCTAssertFalse(gate.admit(.deal, at: 20.21, active: nil, voiceBusy: false))
        XCTAssertFalse(gate.admit(.deal, at: 20.4, active: nil, voiceBusy: false))
        XCTAssertTrue(gate.admit(.deal, at: 20.6, active: nil, voiceBusy: false))
    }

    func testRemotePlayerDecisionsDoNotTriggerLocalCountdownWarnings() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        snapshot.isStarted = true
        snapshot.phase = .responding
        snapshot.pendingHumanSeats = [1]
        let deadline = Date().addingTimeInterval(5)
        snapshot.responseCountdownDeadlines = [1: deadline]
        game.configureLAN(humanSeats: [0, 1], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        XCTAssertNil(MahjongAudioGameState(game: game).deadline)

        snapshot.pendingHumanSeats = [0, 1]
        snapshot.responseCountdownDeadlines[0] = deadline
        game.applyLANSnapshot(snapshot)
        XCTAssertEqual(MahjongAudioGameState(game: game).deadline, deadline)

        snapshot.phase = .choosingMultiplier
        snapshot.pendingMultiplierSeats = [1]
        snapshot.multiplierDeadline = deadline
        game.applyLANSnapshot(snapshot)
        XCTAssertNil(MahjongAudioGameState(game: game).deadline)
    }

    func testMissingSuitCountdownTicksOnlyForTheLocalChooser() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        let deadline = Date().addingTimeInterval(10)
        snapshot.isStarted = true
        snapshot.phase = .choosingMissingSuit
        snapshot.missingSuits = [nil, .dots, .bamboo, .characters]
        snapshot.multiplierDeadline = deadline
        snapshot.pendingHumanSeats = [0]
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        XCTAssertEqual(MahjongAudioGameState(game: game).deadline, deadline)

        snapshot.missingSuits[0] = .characters
        game.applyLANSnapshot(snapshot)
        XCTAssertNil(MahjongAudioGameState(game: game).deadline)
    }

    func testDealingAndDrawingAreDistinctAcrossLANStateUpdates() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        snapshot.isStarted = true
        snapshot.phase = .dealing
        snapshot.wall = Array(repeating: .honor(0), count: 80)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        var old = MahjongAudioGameState(game: game)

        snapshot.dealtCount = 1
        snapshot.wall.removeLast()
        game.applyLANSnapshot(snapshot)
        var new = MahjongAudioGameState(game: game)
        XCTAssertTrue(new.effects(since: old).contains(.deal))
        XCTAssertFalse(new.effects(since: old).contains(.tileDraw))

        snapshot.phase = .playing
        game.applyLANSnapshot(snapshot)
        old = MahjongAudioGameState(game: game)
        snapshot.wall.removeLast()
        game.applyLANSnapshot(snapshot)
        new = MahjongAudioGameState(game: game)
        XCTAssertEqual(new.effects(since: old), [.tileDraw])
        XCTAssertTrue(new.effects(since: new).isEmpty)
    }

    func testWaitingAndDiceChangesRemainSilentBeforeDealing() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        let old = MahjongAudioGameState(game: game)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        snapshot.isStarted = true
        snapshot.phase = .waitingForReady
        snapshot.dice = [3, 4]
        game.applyLANSnapshot(snapshot)
        let ready = MahjongAudioGameState(game: game)
        XCTAssertTrue(ready.effects(since: old).isEmpty)
        snapshot.phase = .dealing
        snapshot.dice = [5, 6]
        game.applyLANSnapshot(snapshot)
        XCTAssertTrue(MahjongAudioGameState(game: game).effects(since: ready).isEmpty)
    }

    func testEveryGeneratedEffectAndLoopDecodesAndContainsUnclippedAudio() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/MahjongAudio")
        let effects = MahjongSoundEffect.allCases.flatMap { effect in
            effect.resourceNames.map { root.appendingPathComponent("effects/\($0).wav") }
        }
        let music = [root.appendingPathComponent("music/happyTable.wav")]
        for url in effects + music {
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 0, url.lastPathComponent)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channel = try XCTUnwrap(buffer.floatChannelData?.pointee)
            let count = Int(buffer.frameLength)
            let samples = UnsafeBufferPointer(start: channel, count: count)
            let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
            XCTAssertGreaterThan(peak, 0.01, "Silent asset: \(url.lastPathComponent)")
            XCTAssertLessThan(peak, 0.70, "Clipped asset: \(url.lastPathComponent)")
            if music.contains(url) {
                XCTAssertGreaterThan(Double(count) / file.processingFormat.sampleRate, 20)
                XCTAssertLessThan(abs(samples[0] - samples[count - 1]), 0.02, "Loop seam: \(url.lastPathComponent)")
            }
        }
    }
}
