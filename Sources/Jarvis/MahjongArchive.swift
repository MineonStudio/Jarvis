import Foundation
import Observation

enum MahjongVoiceGender: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String {
        rawValue
    }

    var displayName: String {
        self == .male ? "男声" : "女声"
    }

    static func defaultProfile(for id: String) -> MahjongVoiceGender {
        switch id {
        case "iron-man", "thor", "hulk", "hawkeye": .male
        default: .female
        }
    }
}

enum MahjongArchiveAvatarStyle: String, Codable, CaseIterable {
    case player, iron, spider, captain, thor, hulk, widow, hawkeye
    case panda, fox, cat, rabbit, bear, tiger, owl
    case dog, penguin, hamster, deer, koala, frog, lion, lamb, monkey, pig

    static let playerChoices: [Self] = [
        .player, .panda, .fox, .cat, .rabbit, .bear, .tiger, .owl,
        .dog, .penguin, .hamster, .deer, .koala, .frog, .lion, .lamb, .monkey, .pig
    ]

    var displayName: String {
        switch self {
        case .player: "默认头像"
        case .iron: "钢铁侠"
        case .spider: "蜘蛛侠"
        case .captain: "美国队长"
        case .thor: "雷神"
        case .hulk: "浩克"
        case .widow: "黑寡妇"
        case .hawkeye: "鹰眼"
        case .panda: "熊猫"
        case .fox: "狐狸"
        case .cat: "小猫"
        case .rabbit: "兔子"
        case .bear: "小熊"
        case .tiger: "老虎"
        case .owl: "猫头鹰"
        case .dog: "柴犬"
        case .penguin: "企鹅"
        case .hamster: "仓鼠"
        case .deer: "小鹿"
        case .koala: "考拉"
        case .frog: "青蛙"
        case .lion: "小狮"
        case .lamb: "小羊"
        case .monkey: "猴子"
        case .pig: "小猪"
        }
    }

    var generatedAssetName: String? {
        switch self {
        case .player: "player"
        case .panda: "panda"
        case .fox: "fox"
        case .cat: "cat"
        case .rabbit: "rabbit"
        case .bear: "bear"
        case .tiger: "tiger"
        case .owl: "owl"
        case .dog: "dog"
        case .penguin: "penguin"
        case .hamster: "hamster"
        case .deer: "deer"
        case .koala: "koala"
        case .frog: "frog"
        case .lion: "lion"
        case .lamb: "lamb"
        case .monkey: "monkey"
        case .pig: "pig"
        default: nil
        }
    }
}

struct MahjongPlayerArchive: Codable, Identifiable, Equatable {
    var id: String
    var nickname: String
    var avatarStyle: MahjongArchiveAvatarStyle
    var voiceGender: MahjongVoiceGender = .female
    var customAvatarFilename: String? = nil
    var balance: Int
    var wins: Int = 0
    var losses: Int = 0
    var escapes: Int = 0
    var eliminatedDay: String?

    var winRate: Int {
        let decidedGames = wins + losses
        guard decidedGames > 0 else { return 0 }
        return Int((Double(wins) / Double(decidedGames) * 100).rounded())
    }
}

extension MahjongPlayerArchive {
    private enum CodingKeys: String, CodingKey {
        case id, nickname, avatarStyle, voiceGender, customAvatarFilename
        case balance, wins, losses, escapes, eliminatedDay
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        nickname = try values.decode(String.self, forKey: .nickname)
        avatarStyle = try values.decode(MahjongArchiveAvatarStyle.self, forKey: .avatarStyle)
        voiceGender = try values.decodeIfPresent(MahjongVoiceGender.self, forKey: .voiceGender)
            ?? MahjongVoiceGender.defaultProfile(for: id)
        customAvatarFilename = try values.decodeIfPresent(String.self, forKey: .customAvatarFilename)
        balance = try values.decode(Int.self, forKey: .balance)
        wins = try values.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try values.decodeIfPresent(Int.self, forKey: .losses) ?? 0
        escapes = try values.decodeIfPresent(Int.self, forKey: .escapes) ?? 0
        eliminatedDay = try values.decodeIfPresent(String.self, forKey: .eliminatedDay)
    }
}

struct MahjongPlayerRoundSettlement: Codable, Identifiable, Equatable {
    var id: String {
        profileID
    }

    let profileID: String
    let nickname: String
    let balanceChange: Int
    let balanceAfter: Int
}

struct MahjongArchiveSettlement: Codable, Equatable {
    var transfers: [String]
    var playerResults: [MahjongPlayerRoundSettlement] = []
    var notice: String?
    var campaignComplete: Bool
    var playerBankrupt: Bool
    var playerNeedsExit: Bool
}

struct MahjongRoundArchiveInput {
    let mode: MahjongPlayMode
    let ruleset: MahjongRuleset
    let roundNumber: Int
    let winnerSeat: Int?
    let localSeat: Int
    let humanSeats: [Int]
    let seatProfileIDs: [String]
    let seatNames: [String]
    let settlement: MahjongArchiveSettlement?
}

struct MahjongMatchRecord: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable {
        case win, loss, draw

        var title: String {
            switch self {
            case .win: "胜利"
            case .loss: "失利"
            case .draw: "流局"
            }
        }
    }

    var id = UUID()
    var playedAt = Date()
    var mode: MahjongPlayMode
    var ruleset: MahjongRuleset
    var roundNumber: Int
    var outcome: Outcome
    var winnerNickname: String?
    var balanceChange: Int
    var balanceAfter: Int
}

@MainActor
@Observable
final class MahjongArchiveStore {
    static let initialBalance = 10000
    static let dailyReward = 2500
    static let bankruptcyAid = 5000

    var player: MahjongPlayerArchive
    var aiProfiles: [MahjongPlayerArchive]
    var lastCheckInDay: String?
    var checkInDays: Set<String>
    var matchHistory: [MahjongMatchRecord]
    var aiMatchHistory: [String: [MahjongMatchRecord]]
    var lastBankruptcyAidDay: String?
    var lastAIRosterCheckDay: String?
    var lastNotice: String?

    let defaults: UserDefaults
    let storageKey = "jarvis.mahjong.archive.v1"
    let calendar: Calendar

    struct Snapshot: Codable {
        var player: MahjongPlayerArchive
        var aiProfiles: [MahjongPlayerArchive]
        var lastCheckInDay: String?
        var checkInDays: Set<String>?
        var matchHistory: [MahjongMatchRecord]?
        var aiMatchHistory: [String: [MahjongMatchRecord]]?
        var lastBankruptcyAidDay: String?
        var lastAIRosterCheckDay: String?
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            player = snapshot.player
            let saved = Dictionary(uniqueKeysWithValues: snapshot.aiProfiles.map { ($0.id, $0) })
            aiProfiles = Self.roster.compactMap { seed in
                guard var profile = saved[seed.id] else { return seed }
                profile.nickname = seed.nickname
                profile.avatarStyle = seed.avatarStyle
                return profile
            }
            lastCheckInDay = snapshot.lastCheckInDay
            checkInDays = snapshot.checkInDays ?? Set(snapshot.lastCheckInDay.map { [$0] } ?? [])
            matchHistory = snapshot.matchHistory ?? []
            aiMatchHistory = snapshot.aiMatchHistory ?? [:]
            lastBankruptcyAidDay = snapshot.lastBankruptcyAidDay
            lastAIRosterCheckDay = snapshot.lastAIRosterCheckDay
        } else {
            player = Self.playerSeed
            aiProfiles = Self.roster
            lastCheckInDay = nil
            checkInDays = []
            matchHistory = []
            aiMatchHistory = [:]
            lastBankruptcyAidDay = nil
            lastAIRosterCheckDay = nil
        }
        if player.id != Self.playerSeed.id {
            player = Self.playerSeed
        }
        if !MahjongArchiveAvatarStyle.playerChoices.contains(player.avatarStyle) {
            player.avatarStyle = .player
        }
        player.customAvatarFilename = nil
        // Older settlements could leave accounts in debt. Keep saved balances
        // consistent with the amount a player can actually pay in a round.
        player.balance = max(0, player.balance)
        for index in aiProfiles.indices {
            aiProfiles[index].balance = max(0, aiProfiles[index].balance)
        }
        save()
    }

    var canClaimDailyReward: Bool {
        lastCheckInDay != dayKey
    }

    var canClaimBankruptcyAid: Bool {
        lastBankruptcyAidDay != dayKey
    }

    var totalAICount: Int {
        aiProfiles.count
    }

    var eliminatedAICount: Int {
        aiProfiles.filter { $0.eliminatedDay == dayKey }.count
    }

    func isEliminatedToday(_ profile: MahjongPlayerArchive) -> Bool {
        profile.eliminatedDay == dayKey
    }

    func claimDailyReward() -> Bool {
        guard canClaimDailyReward else { return false }
        lastCheckInDay = dayKey
        checkInDays.insert(dayKey)
        player.balance += Self.dailyReward
        save()
        return true
    }

    func hasCheckedIn(on date: Date) -> Bool {
        checkInDays.contains(dayKey(for: date))
    }

    var currentCheckInStreak: Int {
        var date = Date()
        if !hasCheckedIn(on: date) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var count = 0
        while hasCheckedIn(on: date) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    func recordMatch(_ record: MahjongMatchRecord) {
        matchHistory.insert(record, at: 0)
        if matchHistory.count > 200 {
            matchHistory.removeLast(matchHistory.count - 200)
        }
        save()
    }

    func history(for profileID: String) -> [MahjongMatchRecord] {
        profileID == player.id ? matchHistory : (aiMatchHistory[profileID] ?? [])
    }

    /// Saves one local result and a result for every AI seat in the same round.
    func recordRound(_ input: MahjongRoundArchiveInput) {
        let playedAt = Date()
        let winnerNickname = input.winnerSeat.flatMap { seat in
            input.settlement?.playerResults.indices.contains(seat) == true
                ? input.settlement?.playerResults[seat].nickname
                : (input.seatNames.indices.contains(seat) ? input.seatNames[seat] : nil)
        }
        func makeRecord(seat: Int, fallbackBalance: Int) -> MahjongMatchRecord {
            let result = input.settlement?.playerResults.indices.contains(seat) == true
                ? input.settlement?.playerResults[seat] : nil
            let outcome: MahjongMatchRecord.Outcome = switch input.winnerSeat {
            case nil: .draw
            case seat: .win
            default: .loss
            }
            return MahjongMatchRecord(
                playedAt: playedAt,
                mode: input.mode,
                ruleset: input.ruleset,
                roundNumber: input.roundNumber,
                outcome: outcome,
                winnerNickname: winnerNickname,
                balanceChange: result?.balanceChange ?? 0,
                balanceAfter: result?.balanceAfter ?? fallbackBalance
            )
        }

        matchHistory.insert(makeRecord(seat: input.localSeat, fallbackBalance: player.balance), at: 0)
        if matchHistory.count > 200 {
            matchHistory.removeLast(matchHistory.count - 200)
        }
        for seat in 0 ..< 4 where !input.humanSeats.contains(seat) && input.seatProfileIDs.indices.contains(seat) {
            let profileID = input.seatProfileIDs[seat]
            guard let profile = aiProfiles.first(where: { $0.id == profileID }) else { continue }
            var records = aiMatchHistory[profileID] ?? []
            records.insert(makeRecord(seat: seat, fallbackBalance: profile.balance), at: 0)
            if records.count > 200 {
                records.removeLast(records.count - 200)
            }
            aiMatchHistory[profileID] = records
        }
        save()
    }
}

enum MahjongWinningHandType: String, Codable, CaseIterable {
    case standard = "普通胡牌"
    case sevenPairs = "七对"
    case thirteenOrphans = "十三幺"

    var competitionPoints: Int {
        switch self {
        case .standard: 8
        case .sevenPairs: 24
        case .thirteenOrphans: 88
        }
    }
}

/// A compact competition-style score: all non-winners pay the 8-point base;
/// the discarder additionally pays the hand points, while every opponent pays
/// the hand points on a self-draw. Only the three hand types recognized by the
/// game are scored, so this does not implement the complete 81-fan ruleset.
enum MahjongCompetitionPayout {
    static let coinsPerPoint = 20
    static let basePoints = 8

    static func payment(
        handType: MahjongWinningHandType,
        byDiscard: Bool,
        winnerConcealed: Bool,
        isDiscarder: Bool
    ) -> Int {
        let concealed = winnerConcealed || handType != .standard
        if byDiscard {
            let handPoints = handType.competitionPoints + (concealed && handType == .standard ? 2 : 0)
            return (basePoints + (isDiscarder ? handPoints : 0)) * coinsPerPoint
        }
        let winMethodPoints = concealed ? 4 : 1
        return (basePoints + handType.competitionPoints + winMethodPoints) * coinsPerPoint
    }
}
