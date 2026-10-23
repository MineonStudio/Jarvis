import Foundation
import Observation

extension MahjongArchiveStore {
    func profile(id: String) -> MahjongPlayerArchive? {
        if id == player.id {
            return player
        }
        return aiProfiles.first(where: { $0.id == id })
    }

    var dayKey: String {
        dayKey(for: Date())
    }

    func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func archiveID(for seat: Int, seatProfileIDs: [String]) -> String {
        seat == 0 ? Self.playerSeed.id : (seatProfileIDs.indices.contains(seat) ? seatProfileIDs[seat] : "")
    }

    func nickname(for id: String) -> String {
        profile(id: id)?.nickname ?? "未知玩家"
    }

    func credit(_ id: String, amount: Int) {
        if id == player.id {
            player.balance += amount
        } else if let index = aiProfiles.firstIndex(where: { $0.id == id }) {
            aiProfiles[index].balance += amount
        }
    }

    func debit(_ id: String, amount: Int) {
        if id == player.id {
            player.balance -= amount
        } else if let index = aiProfiles.firstIndex(where: { $0.id == id }) {
            aiProfiles[index].balance -= amount
        }
    }

    func markResult(id: String, won: Bool) {
        if id == player.id {
            if won {
                player.wins += 1
            } else {
                player.losses += 1
            }
        } else if let index = aiProfiles.firstIndex(where: { $0.id == id }) {
            if won {
                aiProfiles[index].wins += 1
            } else {
                aiProfiles[index].losses += 1
            }
        }
    }

    func save() {
        let snapshot = Snapshot(
            player: player,
            aiProfiles: aiProfiles,
            lastCheckInDay: lastCheckInDay,
            checkInDays: checkInDays,
            matchHistory: matchHistory,
            aiMatchHistory: aiMatchHistory,
            lastBankruptcyAidDay: lastBankruptcyAidDay,
            lastAIRosterCheckDay: lastAIRosterCheckDay
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static let playerSeed = MahjongPlayerArchive(id: "player", nickname: "玩家", avatarStyle: .player, voiceGender: .female, balance: initialBalance)
    static let roster: [MahjongPlayerArchive] = [
        MahjongPlayerArchive(id: "iron-man", nickname: "团团", avatarStyle: .panda, voiceGender: .male, balance: initialBalance),
        MahjongPlayerArchive(id: "spider-man", nickname: "小橘", avatarStyle: .cat, voiceGender: .female, balance: initialBalance),
        MahjongPlayerArchive(id: "captain-america", nickname: "云朵兔", avatarStyle: .rabbit, voiceGender: .female, balance: initialBalance),
        MahjongPlayerArchive(id: "thor", nickname: "星星鸮", avatarStyle: .owl, voiceGender: .male, balance: initialBalance),
        MahjongPlayerArchive(id: "hulk", nickname: "阿福熊", avatarStyle: .bear, voiceGender: .male, balance: initialBalance),
        MahjongPlayerArchive(id: "black-widow", nickname: "机灵狐", avatarStyle: .fox, voiceGender: .female, balance: initialBalance),
        MahjongPlayerArchive(id: "hawkeye", nickname: "小斑", avatarStyle: .tiger, voiceGender: .male, balance: initialBalance)
    ]
}
