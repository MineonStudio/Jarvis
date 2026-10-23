import Foundation
import Observation

extension MahjongGame {
    func runAutomatedTurns() async {
        while phase == .playing, !isHumanSeatTurn {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard phase == .playing, !isHumanSeatTurn else { return }
            if !needsDiscard {
                drawTurnTile()
                guard phase == .playing else { return }
            }
            if justDrew, Self.isWinningHand(hands[turn], meldCount: melds[turn].count, missingSuit: missingSuits[turn]) {
                finishRound(winner: turn, tile: hands[turn].last, byDiscard: false)
                return
            }
            startTurnTimerIfNeeded()
            let decision = await aiTurnDecision(for: turn)
            guard phase == .playing, !isHumanSeatTurn else { return }
            if case let .kong(kong) = decision {
                stopTurnTimer()
                performKong(kong, for: turn)
                guard phase == .playing else { return }
                if Self.isWinningHand(hands[turn], meldCount: melds[turn].count, missingSuit: missingSuits[turn]) {
                    finishRound(winner: turn, tile: hands[turn].last, byDiscard: false)
                    return
                }
                continue
            }
            guard case let .discard(tile) = decision else { continue }
            stopTurnTimer()
            let discarder = turn
            performDiscard(tile, by: discarder)
            beginResponses(to: tile, from: discarder)
            guard phase == .playing else { return }
        }
        if phase == .playing, needsDiscard, humanSeats.contains(turn) {
            startTurnTimerIfNeeded()
        }
    }

    func aiTurnDecision(for seat: Int) async -> MahjongAIDecision {
        let hand = hands[seat]
        guard let firstTile = hand.first else { return .discard(.honor(0)) }
        let forcedSuit = missingSuits[seat].flatMap { suit in
            hand.contains(where: { $0.matches(suit) }) ? suit : nil
        }
        let candidates = forcedSuit.map { suit in hand.filter { $0.matches(suit) } } ?? hand
        let discards = Array(Set(candidates)).sorted { $0.sortKey < $1.sortKey }
        let kongs = aiKongTiles(for: seat)
        let meldText = melds[seat].map(\.label).joined(separator: "；")

        if kongs.isEmpty {
            let tileNames = Array(Set(discards.map(\.aiName))).sorted()
            let userPrompt = """
            \(ruleset.title)。手牌：\(hand.map(\.accessibilityName).joined(separator: "、"))。副露：\(meldText.isEmpty ? "无" : meldText)。定缺：\(missingSuits[seat]?.shortName ?? "无")。牌墙：\(wall.count)张。
            从以下合法可打出的牌中选最有利的一张，只返回牌名：\(tileNames.joined(separator: "、"))
            """
            if let answer = await requestMahjongAI(userPrompt: userPrompt, outputFormat: .tileName) {
                let normalized = normalizeAIAnswer(answer)
                if let tile = discards.first(where: { normalizeAIAnswer($0.aiName) == normalized }) {
                    return .discard(tile)
                }
            }
            return .discard(Self.aiDiscard(from: hand, missingSuit: missingSuits[seat]) ?? firstTile)
        }

        let decisions = kongs.map(MahjongAIDecision.kong) + discards.map(MahjongAIDecision.discard)
        let choices = decisions.map { decision -> String in
            switch decision {
            case let .kong(tile): "杠\(tile.aiName)"
            case let .discard(tile): "出\(tile.aiName)"
            }
        }
        let choiceText = choices.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let userPrompt = """
        \(ruleset.title)。手牌：\(hand.map(\.accessibilityName).joined(separator: "、"))。副露：\(meldText.isEmpty ? "无" : meldText)。定缺：\(missingSuits[seat]?.shortName ?? "无")。牌墙：\(wall.count)张。
        可选操作（只返回对应序号）：
        \(choiceText)
        """
        if let answer = await requestMahjongAI(userPrompt: userPrompt, outputFormat: .optionIndex),
           let index = parseAIOptionIndex(answer, count: decisions.count)
        {
            return decisions[index]
        }
        return .discard(Self.aiDiscard(from: hand, missingSuit: missingSuits[seat]) ?? firstTile)
    }

    func requestMahjongAI(userPrompt: String, outputFormat: MahjongAIOutputFormat) async -> String? {
        let configuration = AIAPIConfiguration.load()
        guard configuration.isConfigured else { return nil }
        let systemPrompt = switch outputFormat {
        case .tileName:
            "你是麻将选牌判定器。只能从用户消息给出的合法牌名中选择一张，并且只输出牌名本身。禁止输出操作、序号、解释、标点、引号、JSON、Markdown或其他内容。"
        case .optionIndex:
            "你是麻将操作判定器。只能选择用户消息中的一项，只输出该项从1开始的十进制序号。禁止输出操作名称、解释、标点、引号、JSON、Markdown或其他内容。"
        }
        return await withCheckedContinuation { continuation in
            let gate = MahjongAIRequestGate(continuation)
            let requestTask = Task.detached(priority: .userInitiated) {
                do {
                    let answer = try await OpenAICompatibleAPIClient().complete(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        configuration: configuration,
                        options: .mahjongDecision
                    )
                    gate.resolve(answer)
                } catch {
                    JarvisLog.error(category: .network, event: "mahjong.ai-decision.failed", error: error)
                    gate.resolve(nil)
                }
            }
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if gate.resolve(nil) {
                    requestTask.cancel()
                    JarvisLog.notice(
                        category: .network,
                        event: "mahjong.ai-decision.deadline",
                        result: "local-fallback",
                        fields: ["deadlineSeconds": "10"]
                    )
                }
            }
        }
    }

    func normalizeAIAnswer(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "萬", with: "万")
            .replacingOccurrences(of: "條", with: "条")
            .replacingOccurrences(of: "東", with: "东")
            .replacingOccurrences(of: "紅", with: "红")
            .replacingOccurrences(of: "發", with: "发")
    }

    func parseAIOptionIndex(_ raw: String, count: Int) -> Int? {
        let answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty,
              answer.allSatisfy(\.isNumber),
              let number = Int(answer),
              (1 ... count).contains(number) else { return nil }
        return number - 1
    }

    func startTurnTimerIfNeeded() {
        guard phase == .playing, needsDiscard else {
            stopTurnTimer()
            return
        }
        guard turnTimerTask == nil || timedSeat != turn else { return }
        let deadline = preservedTurnDeadline
        preservedTurnDeadline = nil
        stopTurnTimer()
        let seat = turn
        timedSeat = seat
        turnTimerSeat = seat
        let turnDeadline = deadline ?? Date().addingTimeInterval(20)
        let initialSeconds = max(1, Int(ceil(turnDeadline.timeIntervalSinceNow)))
        turnCountdownDeadline = turnDeadline
        turnSecondsRemaining = initialSeconds
        turnTimerTask = Task { [weak self] in
            for seconds in stride(from: initialSeconds, through: 1, by: -1) {
                guard let self, !Task.isCancelled,
                      self.phase == .playing, self.turn == seat, self.needsDiscard else { return }
                self.turnSecondsRemaining = seconds
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled,
                  self.phase == .playing, self.turn == seat, self.needsDiscard else { return }
            let tile = self.timeoutDiscardTile(for: seat)
            if let tile {
                self.autoDiscardAfterTimeout(tile, for: seat)
            }
        }
    }

    func timeoutDiscardTile(for seat: Int) -> MahjongTile? {
        guard hands.indices.contains(seat), !hands[seat].isEmpty else { return nil }
        let hand = hands[seat]

        if ruleset == .sichuan,
           let missingSuit = missingSuits[seat],
           hand.contains(where: { $0.matches(missingSuit) })
        {
            // Hand order follows each seat's own view: east/south read from the
            // first tile, west/north from the last tile.
            if seat <= 1 {
                return hand.first(where: { $0.matches(missingSuit) })
            }
            return hand.reversed().first(where: { $0.matches(missingSuit) })
        }

        if justDrew {
            return hand.last
        }
        return Self.aiDiscard(from: hand, missingSuit: missingSuits[seat])
    }

    func startResponseTimer(for seat: Int) {
        guard responseTimerTasks[seat] == nil else { return }
        let duration = humanSeats.contains(seat) ? 5 : 20
        responseCountdowns[seat] = duration
        responseCountdownDeadlines[seat] = Date().addingTimeInterval(TimeInterval(duration))
        responseTimerTasks[seat] = Task { [weak self] in
            for seconds in stride(from: duration, through: 1, by: -1) {
                guard let self, !Task.isCancelled, self.phase == .responding,
                      self.pendingHumanSeats.contains(seat) || self.pendingAISeats.contains(seat) else { return }
                self.responseCountdowns[seat] = seconds
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled, self.phase == .responding else { return }
            self.timeoutResponse(for: seat)
        }
    }

    func stopResponseTimer(for seat: Int) {
        responseTimerTasks.removeValue(forKey: seat)?.cancel()
        responseCountdowns.removeValue(forKey: seat)
        responseCountdownDeadlines.removeValue(forKey: seat)
    }

    func timeoutResponse(for seat: Int) {
        guard phase == .responding else { return }
        stopResponseTimer(for: seat)
        if pendingHumanSeats.contains(seat) || pendingAISeats.contains(seat) {
            announceVoice("action-pass", for: seat)
        }
        pendingHumanSeats.removeAll { $0 == seat }
        pendingAISeats.remove(seat)
        if pendingHumanSeats.isEmpty, pendingAISeats.isEmpty {
            resolveResponses()
            Task { await runAutomatedTurns() }
        } else if pendingHumanSeats.isEmpty {
            continueResponsesAfterHumans()
        } else if let responder = currentResponderSeat {
            message = "\(seatName(responder))，请回应这张弃牌"
        }
    }

    func autoDiscardAfterTimeout(_ tile: MahjongTile, for seat: Int) {
        guard phase == .playing, turn == seat, needsDiscard, hands[seat].contains(tile) else { return }
        stopTurnTimer()
        performDiscard(tile, by: seat)
        beginResponses(to: tile, from: seat)
        Task { await runAutomatedTurns() }
    }

    func stopTurnTimer() {
        turnTimerTask?.cancel()
        turnTimerTask = nil
        timedSeat = nil
        turnTimerSeat = nil
        turnSecondsRemaining = nil
        turnCountdownDeadline = nil
    }
}
