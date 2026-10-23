import Foundation
import Observation

extension MahjongGame {
    func start() {
        if mode == .lan, !isLANAuthority {
            onLANAction?(.start); return
        }
        if let balances = onRoundBalancesRequested?() {
            setRoundStartingBalances(balances)
        }
        stopTurnTimer()
        stopMissingSuitTimer()
        stopMultiplierTimer()
        clearPendingResponses()
        let tiles = Self.makeWall(for: ruleset).shuffled()
        // A new match picks the dealer at random. nextRound has already chosen it.
        if !isStarted, phase == .idle {
            dealer = Int.random(in: 0 ..< 4)
            roundNumber = 1
        }
        roundStartedAt = nil
        roundEndedAt = nil
        wall = tiles
        hands = Array(repeating: [], count: 4)
        melds = Array(repeating: [], count: 4)
        discards = Array(repeating: [], count: 4)
        missingSuits = Array(repeating: nil, count: 4)
        multipliers = Array(repeating: nil, count: 4)
        pendingMultiplierSeats = []
        dice = []
        dealtCount = 0
        turn = dealer
        winner = nil
        discarder = nil
        winningTile = nil
        winByDiscard = false
        roundResult = ""
        justDrew = false
        needsDiscard = false
        readySeats = (0 ..< 4).map { !humanSeats.contains($0) }
        phase = .waitingForReady
        isStarted = true
        message = "AI 已准备 · 等待玩家准备"
    }

    func leaveTable() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.leave)
        }
        leaveTableLocally()
    }

    func leaveTableLocally() {
        stopTurnTimer()
        stopMissingSuitTimer()
        stopMultiplierTimer()
        clearPendingResponses()
        isStarted = false
        phase = .idle
        roundStartedAt = nil
        roundEndedAt = nil
        winner = nil
        winningTile = nil
        winByDiscard = false
        roundResult = ""
        message = "选择玩法并开始一局"
    }

    func addLANGuest(seat: Int, nickname: String) {
        guard mode == .lan, isLANAuthority, (1 ..< 4).contains(seat), !humanSeats.contains(seat) else { return }
        humanSeats.append(seat)
        humanSeats.sort()
        setLANNickname(nickname, for: seat)
        if phase == .waitingForReady {
            readySeats[seat] = false
        }
        if phase == .choosingMissingSuit, missingSuits[seat] == nil, !pendingHumanSeats.contains(seat) {
            pendingHumanSeats.append(seat)
        }
        if phase == .choosingMultiplier, multipliers[seat] == nil {
            multiplierAIChoiceTasks.removeValue(forKey: seat)?.cancel()
            if !pendingMultiplierSeats.contains(seat) {
                pendingMultiplierSeats.append(seat)
            }
        }
        if phase == .responding, pendingAISeats.contains(seat) {
            if pendingAIStarted {
                pendingResponseID = UUID()
                for aiSeat in pendingAISeats {
                    stopResponseTimer(for: aiSeat)
                    chosenResponses.removeValue(forKey: aiSeat)
                }
                pendingAIStarted = false
            }
            pendingAISeats.remove(seat)
            pendingHumanSeats.append(seat)
            stopResponseTimer(for: seat)
            startResponseTimer(for: seat)
        } else if phase == .playing, turn == seat {
            stopTurnTimer()
            startTurnTimerIfNeeded()
        }
    }

    func removeLANGuest(seat: Int, aiNickname: String = "AI") {
        guard mode == .lan, isLANAuthority, (1 ..< 4).contains(seat), humanSeats.contains(seat) else { return }
        humanSeats.removeAll { $0 == seat }
        setLANNickname(aiNickname, for: seat)
        if phase == .waitingForReady {
            readySeats[seat] = true
            if readySeats.allSatisfy({ $0 }) {
                Task { await rollDiceAndDeal() }
            }
        }
        if phase == .choosingMissingSuit, pendingHumanSeats.contains(seat) {
            pendingHumanSeats.removeAll { $0 == seat }
            missingSuits[seat] = Self.leastFrequentSuit(in: hands[seat])
            if pendingHumanSeats.isEmpty {
                prepareMultiplierChoices()
            }
        }
        if phase == .choosingMultiplier, pendingMultiplierSeats.contains(seat) {
            pendingMultiplierSeats.removeAll { $0 == seat }
            scheduleAIChoice(for: seat, delay: 1.4)
        }
        if phase == .responding, pendingHumanSeats.contains(seat) {
            pendingHumanSeats.removeAll { $0 == seat }
            pendingAISeats.insert(seat)
            stopResponseTimer(for: seat)
            continueResponsesAfterHumans()
        } else if phase == .playing, turn == seat {
            Task { await runAutomatedTurns() }
        }
    }

    func markReady() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.ready); return
        }
        let seat = remoteActionSeat ?? localSeat
        guard phase == .waitingForReady,
              humanSeats.contains(seat),
              readySeats.indices.contains(seat),
              !readySeats[seat] else { return }
        readySeats[seat] = true
        message = "\(seatName(seat)) 已准备"
        if readySeats.allSatisfy({ $0 }) {
            Task { await rollDiceAndDeal() }
        }
    }

    func rollDiceAndDeal() async {
        guard phase == .waitingForReady, readySeats.allSatisfy({ $0 }) else { return }
        phase = .dealing
        roundStartedAt = Date()
        roundEndedAt = nil
        dice = [Int.random(in: 1 ... 6), Int.random(in: 1 ... 6)]
        let breakIndex = (dice.reduce(0, +) * 2) % max(wall.count, 1)
        wall = Array(wall[breakIndex...]) + Array(wall[..<breakIndex])
        message = "掷出 \(dice[0]) 点和 \(dice[1]) 点 · 从庄家右侧开门"

        // Deal three four-tile packets, then one tile per seat, then the dealer's extra tile.
        for packetSize in [4, 4, 4, 1] {
            for _ in 0 ..< packetSize {
                for offset in 0 ..< 4 {
                    let seat = (dealer + offset) % 4
                    dealOneTile(to: seat)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        dealOneTile(to: dealer)
        let dealerDraw = hands[dealer].last
        for seat in 0 ..< 4 {
            hands[seat].sort { $0.sortKey < $1.sortKey }
        }
        if let dealerDraw, let index = hands[dealer].firstIndex(of: dealerDraw) {
            let tile = hands[dealer].remove(at: index)
            hands[dealer].append(tile)
        }
        turn = dealer
        justDrew = true
        needsDiscard = true
        if ruleset == .sichuan {
            prepareMissingSuitChoices()
        } else {
            prepareMultiplierChoices()
        }
        await runAutomatedTurns()
    }

    func chooseMissingSuit(_ suit: MahjongSuit) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.missingSuit(suit)); return
        }
        guard phase == .choosingMissingSuit, let seat = currentResponderSeat else { return }
        announceVoice("action-missing-suit", for: seat)
        missingSuits[seat] = suit
        pendingHumanSeats.removeAll { $0 == seat }
        if pendingHumanSeats.contains(localSeat) {
            let nextSeat = localSeat
            message = "\(seatName(nextSeat)) 请选择定缺花色"
            return
        }
        if let waitingSeat = pendingHumanSeats.first {
            message = "等待\(seatName(waitingSeat))选择定缺花色"
            return
        }
        stopMissingSuitTimer()
        prepareMultiplierChoices()
    }

    func discard(_ tile: MahjongTile) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.discard(tile, drawnTile: false)); return
        }
        discard(tile, drawnTile: false)
    }

    func discardDrawnTile() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.discardDrawn); return
        }
        guard justDrew, let tile = currentHand.last else { return }
        discard(tile, drawnTile: true)
    }

    func discard(_ tile: MahjongTile, drawnTile: Bool) {
        guard canActForCurrentSeat, currentHand.count == concealedCountRequired(for: turn, onTurn: true), currentHand.contains(tile) else { return }
        if let missingSuit = missingSuits[turn], currentHand.contains(where: { $0.matches(missingSuit) }), !tile.matches(missingSuit) {
            message = "缺一门，请先打出缺门花色"
            return
        }
        stopTurnTimer()
        performDiscard(tile, by: turn, preserveOrder: drawnTile)
        beginResponses(to: tile, from: turn)
        Task { await runAutomatedTurns() }
    }

    func respond(to option: MahjongCallOption) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.respond(option)); return
        }
        guard phase == .responding, let seat = currentResponderSeat else { return }
        guard option.kind == .pass || pendingOptions[seat, default: []].contains(option) else { return }
        if option.kind == .pass {
            announceVoice("action-pass", for: seat)
        }
        stopResponseTimer(for: seat)
        if option.kind != .pass {
            chosenResponses[seat] = option
        }
        pendingHumanSeats.removeAll { $0 == seat }
        if let nextSeat = currentResponderSeat {
            message = "\(seatName(nextSeat))，请回应这张弃牌"
            _ = nextSeat
        } else {
            continueResponsesAfterHumans()
        }
    }

    func claimSelfDraw() {
        if mode == .lan && !isLANAuthority && !applyingRemoteAction {
            onLANAction?(.selfDraw); return
        }
        guard canSelfDraw || (remoteActionSeat == turn && Self.isWinningHand(currentHand, meldCount: melds[turn].count, missingSuit: missingSuits[turn])) else { return }
        stopTurnTimer()
        finishRound(winner: turn, tile: hands[turn].last, byDiscard: false)
    }

    func declareKong(_ tile: MahjongTile) {
        if mode == .lan && !isLANAuthority && !applyingRemoteAction {
            onLANAction?(.kong(tile)); return
        }
        guard availableKongTiles.contains(tile) || (remoteActionSeat == turn && aiKongTiles(for: turn).contains(tile)) else { return }
        stopTurnTimer()
        performKong(tile, for: turn)
        Task { await runAutomatedTurns() }
    }

    func nextRound() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.nextRound); return
        }
        guard phase == .roundEnded else { return }
        if winner != dealer {
            dealer = (dealer + 1) % 4
        }
        roundNumber += 1
        start()
    }
}
