import SwiftUI

/// Derived from the same state on hosts and LAN guests; audio never drives game rules.
struct MahjongAudioGameState: Equatable {
    let started: Bool
    let phase: MahjongRoundPhase
    let round: Int
    let dealt: Int
    let wall: Int
    let turn: Int
    let localSeat: Int
    let deadline: Date?

    @MainActor
    init(game: MahjongGame) {
        started = game.isStarted
        phase = game.phase
        round = game.roundNumber
        dealt = game.dealtCount
        wall = game.wall.count
        turn = game.turn
        localSeat = game.localSeat
        let canDiscard = game.isHumanTurn
        let isResponding = phase == .responding && game.currentResponderSeat == localSeat
        if phase == .choosingMultiplier, game.pendingMultiplierSeats.contains(localSeat) {
            deadline = game.multiplierDeadline
        } else if phase == .choosingMissingSuit,
                  game.missingSuits.indices.contains(localSeat),
                  game.missingSuits[localSeat] == nil
        {
            deadline = game.multiplierDeadline
        } else if isResponding {
            deadline = game.responseCountdownDeadlines[localSeat]
        } else if canDiscard {
            deadline = game.countdownDeadline(for: localSeat)
        } else {
            deadline = nil
        }
    }

    func effects(since old: Self) -> [MahjongSoundEffect] {
        var sounds: [MahjongSoundEffect] = []
        if phase == .dealing, dealt > old.dealt {
            sounds.append(.deal)
        }
        if round == old.round, phase == .playing, old.phase != .dealing,
           dealt == old.dealt, wall < old.wall
        {
            sounds.append(.tileDraw)
        }
        // LAN snapshots may combine several changes; keep only the main action.
        return sounds.max(by: { $0.priority < $1.priority }).map { [$0] } ?? []
    }
}

struct MahjongGameAudioFeedback: ViewModifier {
    let model: MahjongGameWindowModel
    @State private var hasObserved = false
    @State private var lastVoiceID: UUID?
    private let audio = MahjongAudioPlayer.shared

    private var game: MahjongGame {
        model.game
    }

    private var state: MahjongAudioGameState {
        MahjongAudioGameState(game: game)
    }

    func body(content: Content) -> some View {
        content
            .onReceive(model.lanRoomService.$lastVoiceCue) { cue in
                receiveVoice(cue)
            }
            .onChange(of: state, initial: true) { old, new in
                update(from: old, to: new)
            }
            .task(id: state.deadline) { await monitorCountdown() }
    }

    private func receiveVoice(_ cue: MahjongVoiceCue?) {
        guard let cue, cue.id != lastVoiceID, game.isStarted,
              game.mode == .lan, model.lanRoomService.connected, !model.lanRoomService.isHosting else { return }
        lastVoiceID = cue.id
        let gender = model.lanRoomService.syncedProfiles[cue.seat]?.voiceGender
            ?? (cue.seat == game.localSeat ? model.archive.player.voiceGender : .female)
        MahjongVoicePlayer.shared.play(cue.key, gender: gender, seat: cue.seat, localSeat: game.localSeat)
    }

    private func update(from old: MahjongAudioGameState, to new: MahjongAudioGameState) {
        defer { hasObserved = true }
        guard hasObserved else { return }
        if new.phase == .waitingForReady, old.phase != .waitingForReady {
            audio.resetRound()
        } else if !new.started, old.started {
            audio.resetRound()
        }
        for effect in new.effects(since: old) {
            audio.play(effect, seat: effect == .tileDraw ? new.turn : nil, localSeat: new.localSeat)
        }
    }

    private func monitorCountdown() async {
        guard let deadline = state.deadline else { return }
        var warned = false
        while !Task.isCancelled {
            guard MahjongAudioGameState(game: game).deadline == deadline else { return }
            let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            if (1 ... 3).contains(remaining), !warned {
                audio.play(.tick)
                warned = true
            }
            if remaining == 0 {
                return
            }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        }
    }
}

struct MahjongAudioMuteButton: View {
    @Bindable private var settings = MahjongAudioSettings.shared

    var body: some View {
        Button {
            settings.isMuted.toggle()
        } label: {
            Image(systemName: settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 16)
        }
        .buttonStyle(MahjongGameButtonStyle())
        .help(settings.isMuted ? "开启声音" : "静音")
        .accessibilityLabel(settings.isMuted ? "开启声音" : "静音")
    }
}
