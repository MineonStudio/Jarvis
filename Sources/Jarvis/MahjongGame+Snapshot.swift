import Foundation
import Observation

struct MahjongGameSnapshot: Codable {
    var mode: MahjongPlayMode
    var ruleset: MahjongRuleset
    var seatNicknames: [String]
    var hands: [[MahjongTile]]
    var melds: [[MahjongMeld]]
    var discards: [[MahjongTile]]
    var wall: [MahjongTile]
    var turn: Int
    var dealer: Int
    var roundNumber: Int
    var roundStartedAt: Date?
    var roundEndedAt: Date?
    var humanSeats: [Int]
    var dice: [Int]
    var dealtCount: Int
    var justDrew: Bool
    var needsDiscard: Bool
    var message: String
    var winner: Int?
    var discarder: Int?
    var winningTile: MahjongTile?
    var winningHandType: MahjongWinningHandType
    var aiProfileIDs: [String]
    var winByDiscard: Bool
    var isStarted: Bool
    var phase: MahjongRoundPhase
    var readySeats: [Bool]
    var missingSuits: [MahjongSuit?]
    var roundResult: String
    var roundStartingBalances: [Int]
    var multipliers: [Int?]
    var multiplierDeadline: Date?
    var pendingMultiplierSeats: [Int]
    var turnSecondsRemaining: Int?
    var turnTimerSeat: Int?
    var responseCountdowns: [Int: Int]
    var turnCountdownDeadline: Date?
    var responseCountdownDeadlines: [Int: Date]
    var pendingTile: MahjongTile?
    var pendingDiscarder: Int?
    var pendingHumanSeats: [Int]
    var pendingOptions: [Int: [MahjongCallOption]]
    var chosenResponses: [Int: MahjongCallOption]
    var pendingAISeats: [Int]
    var preservedTurnDeadline: Date?
}

extension MahjongTile {
    func matches(_ suit: MahjongSuit) -> Bool {
        if case let .suited(tileSuit, _) = self {
            return tileSuit == suit
        }
        return false
    }
}
