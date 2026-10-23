import Foundation
import Observation

extension MahjongGame {
    func availableCalls(for seat: Int, using tile: MahjongTile, from discarder: Int) -> [MahjongCallOption] {
        guard hands.indices.contains(seat) else { return [] }
        if let missingSuit = missingSuits[seat], hands[seat].contains(where: { $0.matches(missingSuit) }) {
            return []
        }
        var options: [MahjongCallOption] = []
        if Self.isWinningHand(hands[seat] + [tile], meldCount: melds[seat].count, missingSuit: missingSuits[seat]) {
            options.append(MahjongCallOption(kind: .win, heldTiles: []))
        }
        let same = hands[seat].filter { $0 == tile }
        if same.count >= 3, !wall.isEmpty {
            options.append(MahjongCallOption(kind: .exposedKong, heldTiles: Array(same.prefix(3))))
        }
        if same.count >= 2 {
            options.append(MahjongCallOption(kind: .pong, heldTiles: Array(same.prefix(2))))
        }
        if seat == (discarder + 1) % 4, case let .suited(suit, value) = tile {
            for start in max(1, value - 2) ... min(7, value) {
                let run = [MahjongTile.suited(suit, start), .suited(suit, start + 1), .suited(suit, start + 2)]
                guard run.contains(tile) else { continue }
                var available = hands[seat]
                var held: [MahjongTile] = []
                for required in run where required != tile {
                    guard let index = available.firstIndex(of: required) else { held = []; break }
                    held.append(available.remove(at: index))
                }
                if held.count == 2 {
                    options.append(MahjongCallOption(kind: .chi, heldTiles: held))
                }
            }
        }
        return options
    }

    func resolveAICall(
        for seat: Int,
        discardedTile: MahjongTile,
        discarder: Int,
        responseID: UUID
    ) async {
        let options = pendingOptions[seat, default: []]
        let choice = await aiCall(from: options, for: seat, discardedTile: discardedTile, discarder: discarder)
        guard phase == .responding,
              pendingTile == discardedTile,
              pendingDiscarder == discarder,
              pendingResponseID == responseID,
              pendingAISeats.contains(seat) else { return }
        stopResponseTimer(for: seat)
        if let choice {
            chosenResponses[seat] = choice
            if choice.kind == .pass {
                announceVoice("action-pass", for: seat)
            }
        } else {
            announceVoice("action-pass", for: seat)
        }
        pendingAISeats.remove(seat)
        if pendingAISeats.isEmpty, pendingHumanSeats.isEmpty {
            resolveResponses()
            await runAutomatedTurns()
        }
    }

    func aiCall(
        from options: [MahjongCallOption],
        for seat: Int,
        discardedTile: MahjongTile,
        discarder: Int
    ) async -> MahjongCallOption? {
        let fallback = fallbackAICall(from: options, for: seat)
        // 胡牌是确定性规则判断，命中后直接胡牌，不等待模型接口。
        if let winningOption = options.first(where: { $0.kind == .win }) {
            return winningOption
        }
        let choices = options + [MahjongCallOption(kind: .pass, heldTiles: [])]
        let choiceText = choices.enumerated()
            .map { "\($0.offset + 1). \(aiCallLabel($0.element))" }
            .joined(separator: "\n")
        let handText = hands[seat].map(\.accessibilityName).joined(separator: "、")
        let meldText = melds[seat].map(\.label).joined(separator: "；")
        let userPrompt = """
        玩法：\(ruleset.title)
        你的手牌：\(handText)
        你的副露：\(meldText.isEmpty ? "无" : meldText)
        定缺：\(missingSuits[seat]?.shortName ?? "无")
        刚打出的牌：\(discardedTile.accessibilityName)（\(seatName(discarder))）
        可选操作（只返回对应序号）：
        \(choiceText)

        选择最有利的一项；不值得吃碰杠时选择“过”。只返回序号，不要添加其他内容。
        """
        guard let answer = await requestMahjongAI(userPrompt: userPrompt, outputFormat: .optionIndex),
              let index = parseAIOptionIndex(answer, count: choices.count) else { return fallback }
        return choices[index]
    }

    func fallbackAICall(from options: [MahjongCallOption], for seat: Int) -> MahjongCallOption? {
        if let win = options.first(where: { $0.kind == .win }) {
            return win
        }
        if let kong = options.first(where: { $0.kind == .exposedKong }) {
            return kong
        }
        if let pong = options.first(where: { $0.kind == .pong }) {
            return pong
        }
        if let chi = options.first(where: { $0.kind == .chi }) {
            let hand = hands[seat] + chi.heldTiles
            return Self.isWinningHand(hand, meldCount: melds[seat].count, missingSuit: missingSuits[seat]) || Int.random(in: 0 ... 2) == 0 ? chi : nil
        }
        return nil
    }

    func aiCallLabel(_ option: MahjongCallOption) -> String {
        switch option.kind {
        case .pass: return "过"
        case .win: return "胡"
        case .exposedKong, .pong:
            guard let tile = option.heldTiles.first else { return option.kind.rawValue }
            return "\(option.kind.rawValue)\(tile.aiName)"
        case .chi:
            let tiles = option.heldTiles.sorted { $0.sortKey < $1.sortKey }.map(\.aiName).joined()
            return "吃\(tiles)"
        }
    }

    func resolveResponses() {
        guard pendingHumanSeats.isEmpty, pendingAISeats.isEmpty else { return }
        guard let tile = pendingTile, let discarder = pendingDiscarder else { return }
        let selected = chosenResponses
            .filter { $0.value.kind != .pass }
            .sorted { lhs, rhs in
                if lhs.value.kind.priority != rhs.value.kind.priority {
                    return lhs.value.kind.priority > rhs.value.kind.priority
                }
                let leftDistance = (lhs.key - discarder + 4) % 4
                let rightDistance = (rhs.key - discarder + 4) % 4
                return leftDistance < rightDistance
            }
        clearPendingResponses()
        if let (seat, option) = selected.first {
            switch option.kind {
            case .win:
                finishRound(winner: seat, tile: tile, byDiscard: true, discarder: discarder)
            case .exposedKong:
                announceVoice("action-exposed-kong", for: seat)
                consumeClaimedDiscard(from: discarder)
                remove(option.heldTiles, from: seat)
                melds[seat].append(MahjongMeld(kind: .exposedKong, tiles: option.heldTiles + [tile]))
                turn = seat
                message = "\(seatName(seat)) 明杠 · 补一张牌"
                drawSupplement(for: seat)
            case .pong:
                announceVoice("action-pong", for: seat)
                consumeClaimedDiscard(from: discarder)
                remove(option.heldTiles, from: seat)
                melds[seat].append(MahjongMeld(kind: .triplet, tiles: option.heldTiles + [tile]))
                turn = seat
                justDrew = false
                needsDiscard = true
                phase = .playing
                message = "\(seatName(seat)) 碰牌 · 请打出一张"
            case .chi:
                announceVoice("action-chi", for: seat)
                consumeClaimedDiscard(from: discarder)
                remove(option.heldTiles, from: seat)
                melds[seat].append(MahjongMeld(kind: .sequence, tiles: option.heldTiles + [tile]))
                turn = seat
                justDrew = false
                needsDiscard = true
                phase = .playing
                message = "\(seatName(seat)) 吃牌 · 请打出一张"
            case .pass:
                break
            }
        } else {
            turn = (discarder + 1) % 4
            drawTurnTile()
        }
    }

    func consumeClaimedDiscard(from seat: Int) {
        if discards.indices.contains(seat), !discards[seat].isEmpty {
            discards[seat].removeLast()
        }
    }

    func remove(_ tiles: [MahjongTile], from seat: Int) {
        for tile in tiles {
            if let index = hands[seat].firstIndex(of: tile) {
                hands[seat].remove(at: index)
            }
        }
    }

    func drawTurnTile() {
        guard !wall.isEmpty else {
            finishDraw()
            return
        }
        let tile = wall.removeFirst()
        hands[turn].append(tile)
        justDrew = true
        needsDiscard = true
        phase = .playing
        if Self.isWinningHand(hands[turn], meldCount: melds[turn].count, missingSuit: missingSuits[turn]) {
            if humanSeats.contains(turn) {
                message = "\(seatName(turn)) 摸到和牌 · 可选择自摸或继续打牌"
            } else {
                finishRound(winner: turn, tile: tile, byDiscard: false)
            }
        } else {
            message = "\(seatName(turn)) 摸牌"
        }
    }

    func drawSupplement(for seat: Int) {
        guard !wall.isEmpty else {
            finishDraw()
            return
        }
        hands[seat].append(wall.removeLast())
        justDrew = true
        needsDiscard = true
        phase = .playing
        if Self.isWinningHand(hands[seat], meldCount: melds[seat].count, missingSuit: missingSuits[seat]) {
            if humanSeats.contains(seat) {
                message = "\(seatName(seat)) 补牌后和牌 · 可选择自摸或继续打牌"
            } else {
                finishRound(winner: seat, tile: hands[seat].last, byDiscard: false)
            }
        }
    }

    func performKong(_ tile: MahjongTile, for seat: Int) {
        if let tripletIndex = melds[seat].firstIndex(where: { $0.kind == .triplet && $0.tiles.first == tile }),
           let handIndex = hands[seat].firstIndex(of: tile)
        {
            announceVoice("action-added-kong", for: seat)
            hands[seat].remove(at: handIndex)
            melds[seat][tripletIndex] = MahjongMeld(kind: .addedKong, tiles: melds[seat][tripletIndex].tiles + [tile])
        } else {
            announceVoice("action-concealed-kong", for: seat)
            let four = Array(hands[seat].filter { $0 == tile }.prefix(4))
            remove(four, from: seat)
            melds[seat].append(MahjongMeld(kind: .concealedKong, tiles: four))
        }
        message = "\(seatName(seat)) 宣告杠牌 · 补一张牌"
        drawSupplement(for: seat)
    }
}
