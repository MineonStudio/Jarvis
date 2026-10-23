import Foundation
import Observation

extension MahjongGame {
    func aiKongTiles(for seat: Int) -> [MahjongTile] {
        let unique = Set(hands[seat]).sorted { $0.sortKey < $1.sortKey }
        return unique.filter { tile in
            hands[seat].filter { $0 == tile }.count == 4 ||
                (melds[seat].contains(where: { $0.kind == .triplet && $0.tiles.first == tile }) && hands[seat].contains(tile))
        }
    }

    func finishRound(winner: Int, tile: MahjongTile?, byDiscard: Bool) {
        finishRound(winner: winner, tile: tile, byDiscard: byDiscard, discarder: nil)
    }

    func finishRound(winner: Int, tile: MahjongTile?, byDiscard: Bool, discarder: Int?) {
        announceVoice(byDiscard ? "action-win" : "action-self-draw", for: winner)
        stopTurnTimer()
        roundEndedAt = Date()
        self.winner = winner
        self.discarder = byDiscard ? discarder : nil
        winningTile = tile
        winByDiscard = byDiscard
        var completedHand = hands.indices.contains(winner) ? hands[winner] : []
        if byDiscard, let tile {
            completedHand.append(tile)
        }
        winningHandType = Self.winningHandType(completedHand, meldCount: melds.indices.contains(winner) ? melds[winner].count : 0)
        phase = .roundEnded
        isStarted = true
        justDrew = false
        needsDiscard = false
        roundResult = "\(byDiscard ? "荣和" : "自摸")\(tile.map { " · \($0.accessibilityName)" } ?? "")"
        message = "\(roundResult) · 本局结束"
        readySeats = (0 ..< 4).map { !humanSeats.contains($0) }
        clearPendingResponses()
    }

    func finishDraw() {
        announceVoice("action-draw", for: turn)
        stopTurnTimer()
        roundEndedAt = Date()
        phase = .roundEnded
        isStarted = true
        justDrew = false
        needsDiscard = false
        winner = nil
        roundResult = "牌墙摸完 · 流局"
        message = roundResult
        readySeats = (0 ..< 4).map { !humanSeats.contains($0) }
        clearPendingResponses()
    }

    func clearPendingResponses() {
        for seat in Array(responseTimerTasks.keys) {
            stopResponseTimer(for: seat)
        }
        pendingResponseID = UUID()
        pendingTile = nil
        pendingDiscarder = nil
        pendingHumanSeats = []
        pendingOptions = [:]
        chosenResponses = [:]
        pendingAISeats = []
        pendingAIStarted = false
    }

    func concealedCountRequired(for seat: Int, onTurn: Bool) -> Int {
        (onTurn ? 14 : 13) - melds[seat].count * 3
    }

    static func makeWall(for ruleset: MahjongRuleset) -> [MahjongTile] {
        var tiles: [MahjongTile] = []
        for suit in MahjongSuit.allCases {
            for value in 1 ... 9 {
                for _ in 0 ..< 4 {
                    tiles.append(.suited(suit, value))
                }
            }
        }
        if ruleset.includesHonors {
            for value in 0 ..< 7 {
                for _ in 0 ..< 4 {
                    tiles.append(.honor(value))
                }
            }
        }
        return tiles
    }

    static func leastFrequentSuit(in hand: [MahjongTile]) -> MahjongSuit {
        MahjongSuit.allCases.min { lhs, rhs in
            hand.filter { $0.matches(lhs) }.count < hand.filter { $0.matches(rhs) }.count
        } ?? .characters
    }

    static func aiDiscard(from hand: [MahjongTile], missingSuit: MahjongSuit? = nil) -> MahjongTile? {
        guard !hand.isEmpty else { return nil }
        let missing = missingSuit.map { suit in hand.filter { $0.matches(suit) } } ?? []
        let candidates = missing.isEmpty ? hand : missing
        let counts = Dictionary(grouping: candidates, by: { $0 }).mapValues(\.count)
        return candidates.min { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            let lhsScore = lhsCount * 8 + neighborCount(lhs, counts: counts)
            let rhsScore = rhsCount * 8 + neighborCount(rhs, counts: counts)
            return lhsScore < rhsScore
        }
    }

    static func neighborCount(_ tile: MahjongTile, counts: [MahjongTile: Int]) -> Int {
        guard case let .suited(suit, value) = tile else { return 0 }
        return [-2, -1, 1, 2].reduce(0) { result, offset in
            result + counts[.suited(suit, value + offset), default: 0]
        }
    }

    static func isWinningHand(_ hand: [MahjongTile], meldCount: Int = 0, missingSuit: MahjongSuit? = nil) -> Bool {
        guard hand.count == 14 - meldCount * 3 else { return false }
        if let missingSuit, hand.contains(where: { $0.matches(missingSuit) }) {
            return false
        }
        var counts = Dictionary(grouping: hand, by: { $0 }).mapValues(\.count)
        if meldCount == 0 {
            let pairCount = counts.values.reduce(0) { $0 + $1 / 2 }
            if counts.values.allSatisfy({ $0.isMultiple(of: 2) }), pairCount == 7 {
                return true
            }

            let orphans: Set<MahjongTile> = Set(MahjongSuit.allCases.flatMap { suit in
                [MahjongTile.suited(suit, 1), .suited(suit, 9)]
            } + (0 ..< 7).map(MahjongTile.honor))
            if hand.allSatisfy(orphans.contains),
               orphans.allSatisfy({ counts[$0, default: 0] > 0 }),
               counts.values.contains(2)
            {
                return true
            }
        }
        for tile in counts.keys where counts[tile, default: 0] >= 2 {
            counts[tile, default: 0] -= 2
            if canFormMelds(&counts) {
                return true
            }
            counts[tile, default: 0] += 2
        }
        return false
    }

    static func winningHandType(_ hand: [MahjongTile], meldCount: Int) -> MahjongWinningHandType {
        guard meldCount == 0 else { return .standard }
        let counts = Dictionary(grouping: hand, by: { $0 }).mapValues(\.count)
        if counts.values.allSatisfy({ $0 == 2 }), counts.count == 7 {
            return .sevenPairs
        }
        let orphans: Set<MahjongTile> = Set(MahjongSuit.allCases.flatMap { suit in
            [MahjongTile.suited(suit, 1), .suited(suit, 9)]
        } + (0 ..< 7).map(MahjongTile.honor))
        if hand.count == 14,
           hand.allSatisfy(orphans.contains),
           orphans.allSatisfy({ counts[$0, default: 0] > 0 }),
           counts.values.contains(2)
        {
            return .thirteenOrphans
        }
        return .standard
    }

    static func canFormMelds(_ counts: inout [MahjongTile: Int]) -> Bool {
        guard let tile = counts.keys.filter({ counts[$0, default: 0] > 0 }).min(by: { $0.sortKey < $1.sortKey }) else {
            return true
        }
        if counts[tile, default: 0] >= 3 {
            counts[tile, default: 0] -= 3
            if canFormMelds(&counts) {
                return true
            }
            counts[tile, default: 0] += 3
        }
        if case let .suited(suit, value) = tile, value <= 7 {
            let next = MahjongTile.suited(suit, value + 1)
            let last = MahjongTile.suited(suit, value + 2)
            if counts[next, default: 0] > 0, counts[last, default: 0] > 0 {
                counts[tile, default: 0] -= 1
                counts[next, default: 0] -= 1
                counts[last, default: 0] -= 1
                if canFormMelds(&counts) {
                    return true
                }
                counts[tile, default: 0] += 1
                counts[next, default: 0] += 1
                counts[last, default: 0] += 1
            }
        }
        return false
    }
}
