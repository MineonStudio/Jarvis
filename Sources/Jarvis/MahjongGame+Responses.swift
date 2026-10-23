import Foundation
import Observation

extension MahjongGame {
    func seatName(_ seat: Int) -> String {
        switch seat {
        case 0: "东家"
        case 1: "南家"
        case 2: "西家"
        default: "北家"
        }
    }

    func tileCount(for seat: Int) -> Int {
        guard hands.indices.contains(seat), melds.indices.contains(seat) else { return 0 }
        return hands[seat].count + melds[seat].reduce(0) { $0 + $1.tiles.count }
    }

    func dealOneTile(to seat: Int) {
        guard !wall.isEmpty else { return }
        hands[seat].append(wall.removeFirst())
        dealtCount += 1
    }

    func prepareMissingSuitChoices() {
        phase = .choosingMissingSuit
        pendingHumanSeats = humanSeats
        for seat in 0 ..< 4 where !humanSeats.contains(seat) {
            missingSuits[seat] = Self.leastFrequentSuit(in: hands[seat])
        }
        guard !pendingHumanSeats.isEmpty else {
            prepareMultiplierChoices()
            return
        }
        let seconds = Int(MahjongDoubling.duration)
        message = "请选择定缺花色 · \(seconds) 秒后自动选择"
        multiplierDeadline = Date().addingTimeInterval(MahjongDoubling.duration)
        missingSuitTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MahjongDoubling.duration))
            guard let self, !Task.isCancelled, self.phase == .choosingMissingSuit else { return }
            for seat in self.pendingHumanSeats {
                let suit = Self.leastFrequentSuit(in: self.hands[seat])
                self.missingSuits[seat] = suit
                self.announceVoice("action-missing-suit", for: seat)
            }
            self.pendingHumanSeats = []
            self.missingSuitTimerTask = nil
            self.prepareMultiplierChoices()
        }
    }

    func stopMissingSuitTimer() {
        missingSuitTimerTask?.cancel()
        missingSuitTimerTask = nil
    }

    func prepareMultiplierChoices() {
        stopMissingSuitTimer()
        stopMultiplierTimer()
        phase = .choosingMultiplier
        turn = dealer
        justDrew = true
        needsDiscard = true
        pendingMultiplierSeats = humanSeats.sorted()
        let aiSeats = (0 ..< 4).filter { !humanSeats.contains($0) }.shuffled()
        for (order, seat) in aiSeats.enumerated() {
            scheduleAIChoice(
                for: seat,
                delay: MahjongDoubling.aiRevealDelay(
                    order: order, jitter: Double.random(in: 0.1 ... 0.45)
                )
            )
        }
        message = "请选择本局倍数 · 10 秒后默认不加倍"
        multiplierDeadline = Date().addingTimeInterval(MahjongDoubling.duration)
        multiplierTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MahjongDoubling.duration))
            guard let self, !Task.isCancelled, self.phase == .choosingMultiplier else { return }
            for seat in self.pendingMultiplierSeats {
                self.multipliers[seat] = 1
                self.announceVoice(Self.multiplierVoiceCue(for: 1), for: seat)
            }
            self.pendingMultiplierSeats = []
            self.finishMultiplierChoices()
        }
    }

    func scheduleAIChoice(for seat: Int, delay: TimeInterval) {
        multiplierAIChoiceTasks.removeValue(forKey: seat)?.cancel()
        multiplierAIChoiceTasks[seat] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.phase == .choosingMultiplier,
                  !self.humanSeats.contains(seat), self.multipliers[seat] == nil else { return }
            let value = MahjongDoubling.aiChoice(
                balance: self.roundStartingBalances[seat], roll: Int.random(in: 0 ..< 100)
            )
            self.multipliers[seat] = value
            self.multiplierAIChoiceTasks[seat] = nil
            self.announceVoice(Self.multiplierVoiceCue(for: value), for: seat)
            self.message = "\(self.seatName(seat)) 已选择 ×\(value)"
            self.finishMultiplierChoices()
        }
    }

    func finishMultiplierChoices() {
        guard phase == .choosingMultiplier, pendingMultiplierSeats.isEmpty,
              multipliers.allSatisfy({ $0 != nil }), multiplierCompletionTask == nil else { return }
        multiplierTimerTask?.cancel()
        multiplierTimerTask = nil
        multiplierCompletionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MahjongDoubling.revealPause))
            guard let self, !Task.isCancelled, self.phase == .choosingMultiplier else { return }
            self.stopMultiplierTimer()
            self.phase = .playing
            self.message = "加倍完成 · 庄家 \(self.seatName(self.dealer)) 起手 14 张"
            Task { await self.runAutomatedTurns() }
        }
    }

    func stopMultiplierTimer() {
        multiplierTimerTask?.cancel()
        multiplierTimerTask = nil
        for task in multiplierAIChoiceTasks.values {
            task.cancel()
        }
        multiplierAIChoiceTasks = [:]
        multiplierCompletionTask?.cancel()
        multiplierCompletionTask = nil
        multiplierDeadline = nil
    }

    func performDiscard(_ tile: MahjongTile, by player: Int, preserveOrder: Bool = false) {
        let index = preserveOrder ? hands[player].lastIndex(of: tile) : hands[player].firstIndex(of: tile)
        guard let index else { return }
        hands[player].remove(at: index)
        if !preserveOrder {
            hands[player].sort { $0.sortKey < $1.sortKey }
        }
        discards[player].append(tile)
        announceVoice("tile-\(tile.id)", for: player)
        justDrew = false
        needsDiscard = false
        message = "\(seatName(player)) 打出 \(tile.accessibilityName)"
    }

    func beginResponses(to tile: MahjongTile, from discarder: Int) {
        clearPendingResponses()
        pendingTile = tile
        pendingDiscarder = discarder
        for distance in 1 ... 3 {
            let seat = (discarder + distance) % 4
            let options = availableCalls(for: seat, using: tile, from: discarder)
            guard !options.isEmpty else { continue }
            pendingOptions[seat] = options
            if humanSeats.contains(seat) {
                pendingHumanSeats.append(seat)
            } else {
                pendingAISeats.insert(seat)
            }
        }
        if !pendingHumanSeats.isEmpty || !pendingAISeats.isEmpty {
            phase = .responding
            for seat in pendingHumanSeats {
                startResponseTimer(for: seat)
            }
            if let responder = currentResponderSeat {
                message = "\(seatName(responder))，请回应这张弃牌"
            } else {
                message = "AI 正在判断是否吃、碰或杠"
            }
            continueResponsesAfterHumans()
        } else {
            resolveResponses()
        }
    }

    func continueResponsesAfterHumans() {
        guard phase == .responding, pendingHumanSeats.isEmpty else { return }
        if !chosenResponses.isEmpty {
            pendingAISeats.removeAll()
            resolveResponses()
            Task { await runAutomatedTurns() }
            return
        }
        guard !pendingAIStarted else { return }
        pendingAIStarted = true
        guard let tile = pendingTile, let discarder = pendingDiscarder else { return }
        if pendingAISeats.isEmpty {
            resolveResponses()
            Task { await runAutomatedTurns() }
            return
        }
        message = "AI 正在判断是否吃、碰或杠"
        let responseID = pendingResponseID
        for seat in pendingAISeats {
            startResponseTimer(for: seat)
            Task { await resolveAICall(for: seat, discardedTile: tile, discarder: discarder, responseID: responseID) }
        }
    }
}
