import AppKit
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

@MainActor
@Observable
final class MahjongArchiveStore {
    static let initialBalance = 10000
    static let dailyReward = 5000
    static let bankruptcyAid = 5000

    private(set) var player: MahjongPlayerArchive
    private(set) var aiProfiles: [MahjongPlayerArchive]
    private(set) var lastCheckInDay: String?
    private(set) var lastBankruptcyAidDay: String?
    private(set) var lastAIRosterCheckDay: String?
    private(set) var lastNotice: String?

    private let defaults: UserDefaults
    private let storageKey = "jarvis.mahjong.archive.v1"
    private let calendar: Calendar

    private struct Snapshot: Codable {
        var player: MahjongPlayerArchive
        var aiProfiles: [MahjongPlayerArchive]
        var lastCheckInDay: String?
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
            lastBankruptcyAidDay = snapshot.lastBankruptcyAidDay
            lastAIRosterCheckDay = snapshot.lastAIRosterCheckDay
        } else {
            player = Self.playerSeed
            aiProfiles = Self.roster
            lastCheckInDay = nil
            lastBankruptcyAidDay = nil
            lastAIRosterCheckDay = nil
        }
        if player.id != Self.playerSeed.id {
            player = Self.playerSeed
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
        player.balance += Self.dailyReward
        save()
        return true
    }

    func updatePlayerProfile(
        nickname: String? = nil,
        avatarStyle: MahjongArchiveAvatarStyle? = nil,
        voiceGender: MahjongVoiceGender? = nil
    ) {
        if let nickname {
            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                player.nickname = String(trimmed.prefix(16))
            }
        }
        if let avatarStyle {
            player.avatarStyle = avatarStyle
        }
        if let voiceGender {
            player.voiceGender = voiceGender
        }
        save()
    }

    func updateAIVoiceGender(profileID: String, voiceGender: MahjongVoiceGender) {
        guard let index = aiProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        aiProfiles[index].voiceGender = voiceGender
        save()
    }

    func updatePlayerAvatar(from sourceURL: URL) throws {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let side = min(image.size.width, image.size.height)
        guard side > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: 512,
                  pixelsHigh: 512,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bitmapFormat: [],
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw CocoaError(.fileReadUnknown)
        }
        bitmap.size = NSSize(width: 512, height: 512)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: 512, height: 512),
            from: NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side),
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fileName = "player-avatar.png"
        let directory = Self.avatarDirectoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        try pngData.write(to: destination, options: .atomic)
        player.customAvatarFilename = fileName
        save()
    }

    static var avatarDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jarvis/MahjongAvatars", isDirectory: true)
    }

    /// Validate the AI roster once on the first match of the local calendar day.
    func prepareAIOpponents() -> [String] {
        if lastAIRosterCheckDay != dayKey {
            for index in aiProfiles.indices where aiProfiles[index].balance < Self.initialBalance {
                aiProfiles[index].balance = Self.initialBalance
            }
            lastAIRosterCheckDay = dayKey
        }
        let eligible = aiProfiles.filter { $0.balance > 0 && $0.eliminatedDay != dayKey }.shuffled()
        save()
        return Array(eligible.prefix(3).map(\.id))
    }

    /// After a round, preserve funded opponents and fill bankrupt seats from the unused roster.
    func replacingBankruptOpponents(_ currentIDs: [String]) -> [String] {
        var next = currentIDs
        let eligible = aiProfiles.filter { profile in
            profile.balance > 0 && profile.eliminatedDay != dayKey && !currentIDs.contains(profile.id)
        }.shuffled()
        var replacementIndex = 0
        for index in next.indices {
            guard (profile(id: next[index])?.balance ?? 0) <= 0 else { continue }
            if replacementIndex < eligible.count {
                next[index] = eligible[replacementIndex].id
                replacementIndex += 1
            } else {
                next[index] = ""
            }
        }
        return next
    }

    func settle(
        winnerSeat: Int,
        discarderSeat: Int?,
        handType: MahjongWinningHandType,
        byDiscard: Bool,
        seatProfileIDs: [String]
    ) -> MahjongArchiveSettlement {
        guard (0 ..< 4).contains(winnerSeat) else {
            return MahjongArchiveSettlement(transfers: [], notice: nil, campaignComplete: false, playerBankrupt: false, playerNeedsExit: false)
        }

        let amount = byDiscard ? handType.discardPayment : handType.selfDrawPayment
        let losers = byDiscard
            ? (discarderSeat.map { [$0] } ?? [])
            : (0 ..< 4).filter { $0 != winnerSeat }
        guard !losers.isEmpty else {
            return MahjongArchiveSettlement(transfers: [], notice: nil, campaignComplete: false, playerBankrupt: false, playerNeedsExit: false)
        }

        var transfers: [String] = []
        var totalPaid = 0
        var balanceChanges = Array(repeating: 0, count: 4)
        for loserSeat in losers {
            let payerID = archiveID(for: loserSeat, seatProfileIDs: seatProfileIDs)
            let winnerID = archiveID(for: winnerSeat, seatProfileIDs: seatProfileIDs)
            guard !payerID.isEmpty, !winnerID.isEmpty else { continue }
            debit(payerID, amount: amount)
            credit(winnerID, amount: amount)
            balanceChanges[loserSeat] -= amount
            balanceChanges[winnerSeat] += amount
            totalPaid += amount
            let payerName = nickname(for: payerID)
            let winnerName = nickname(for: winnerID)
            transfers.append("\(payerName) 向 \(winnerName) 支付 \(amount.formatted()) 毛格子")
        }
        let winnerID = archiveID(for: winnerSeat, seatProfileIDs: seatProfileIDs)
        if !winnerID.isEmpty {
            markResult(id: winnerID, won: true)
        }
        for seat in 0 ..< 4 where seat != winnerSeat {
            let loserID = archiveID(for: seat, seatProfileIDs: seatProfileIDs)
            if !loserID.isEmpty {
                markResult(id: loserID, won: false)
            }
        }

        var notice: String?
        var playerBankrupt = false
        var playerNeedsExit = false
        if player.balance <= 0 {
            playerBankrupt = true
            if canClaimBankruptcyAid {
                lastBankruptcyAidDay = dayKey
                player.balance += Self.bankruptcyAid
                notice = "余额已耗尽，今日破产补助已自动发放 5,000 毛格子，可继续对局。"
            } else {
                playerNeedsExit = true
                notice = "余额再次耗尽，今日破产补助已用完，请退出游戏。"
            }
        }

        for index in aiProfiles.indices where aiProfiles[index].balance <= 0 {
            aiProfiles[index].eliminatedDay = dayKey
        }
        let campaignComplete = aiProfiles.allSatisfy { $0.balance <= 0 || $0.eliminatedDay == dayKey }
        if campaignComplete, !playerNeedsExit {
            notice = "七位 AI 对手均已破产，本次挑战获胜！"
        }
        if totalPaid > 0, notice == nil {
            let playerChange = winnerID == Self.playerSeed.id ? "+\(totalPaid)" : (losers.contains(where: { archiveID(for: $0, seatProfileIDs: seatProfileIDs) == Self.playerSeed.id }) ? "-\(amount)" : nil)
            notice = playerChange.map { "本局结算：\($0) 毛格子" }
        }
        let seatNames = ["东家", "南家", "西家", "北家"]
        let playerResults = (0 ..< 4).map { seat in
            let profileID = archiveID(for: seat, seatProfileIDs: seatProfileIDs)
            let profile = profileID.isEmpty ? nil : self.profile(id: profileID)
            return MahjongPlayerRoundSettlement(
                profileID: profileID.isEmpty ? "empty-seat-\(seat)" : profileID,
                nickname: profile?.nickname ?? seatNames[seat],
                balanceChange: balanceChanges[seat],
                balanceAfter: profile?.balance ?? 0
            )
        }
        lastNotice = notice
        save()
        return MahjongArchiveSettlement(
            transfers: transfers,
            playerResults: playerResults,
            notice: notice,
            campaignComplete: campaignComplete,
            playerBankrupt: playerBankrupt,
            playerNeedsExit: playerNeedsExit
        )
    }

    /// The host settles all four LAN seats once, then distributes the resulting profiles.
    func settleLAN(
        winnerSeat: Int,
        discarderSeat: Int?,
        handType: MahjongWinningHandType,
        byDiscard: Bool,
        seatProfiles: [MahjongPlayerArchive]
    ) -> (settlement: MahjongArchiveSettlement, profiles: [MahjongPlayerArchive]) {
        guard (0 ..< 4).contains(winnerSeat), seatProfiles.count == 4 else {
            return (MahjongArchiveSettlement(transfers: [], campaignComplete: false, playerBankrupt: false, playerNeedsExit: false), seatProfiles)
        }

        var profiles = seatProfiles
        let amount = byDiscard ? handType.discardPayment : handType.selfDrawPayment
        let losers = byDiscard ? (discarderSeat.map { [$0] } ?? []) : (0 ..< 4).filter { $0 != winnerSeat }
        var changes = Array(repeating: 0, count: 4)
        var transfers: [String] = []
        for loser in losers where (0 ..< 4).contains(loser) {
            profiles[loser].balance -= amount
            profiles[winnerSeat].balance += amount
            changes[loser] -= amount
            changes[winnerSeat] += amount
            transfers.append("\(profiles[loser].nickname) 向 \(profiles[winnerSeat].nickname) 支付 \(amount.formatted()) 毛格子")
        }
        for seat in profiles.indices {
            if seat == winnerSeat {
                profiles[seat].wins += 1
            } else {
                profiles[seat].losses += 1
            }
        }

        // LAN AI profiles belong to the host's archive; the visiting player's own device
        // persists their account when this authoritative result arrives.
        player.balance = profiles[0].balance
        player.wins = profiles[0].wins
        player.losses = profiles[0].losses
        for profile in profiles.dropFirst() {
            if let index = aiProfiles.firstIndex(where: { $0.id == profile.id }) {
                aiProfiles[index].balance = profile.balance
                aiProfiles[index].wins = profile.wins
                aiProfiles[index].losses = profile.losses
                aiProfiles[index].eliminatedDay = profile.balance <= 0 ? dayKey : nil
            }
        }

        let results = profiles.indices.map { seat in
            MahjongPlayerRoundSettlement(
                profileID: profiles[seat].id,
                nickname: profiles[seat].nickname,
                balanceChange: changes[seat],
                balanceAfter: profiles[seat].balance
            )
        }
        let notice = "本局结算完成：\(profiles[winnerSeat].nickname) 获胜"
        lastNotice = notice
        save()
        return (
            MahjongArchiveSettlement(
                transfers: transfers,
                playerResults: results,
                notice: notice,
                campaignComplete: false,
                playerBankrupt: profiles[0].balance <= 0,
                playerNeedsExit: false
            ),
            profiles
        )
    }

    /// Applies the authoritative LAN account data while preserving this device's
    /// local nickname/avatar and account identifier.
    func applyLANPlayerProfile(_ remote: MahjongPlayerArchive) {
        guard player.balance != remote.balance || player.wins != remote.wins || player.losses != remote.losses else { return }
        player.balance = remote.balance
        player.wins = remote.wins
        player.losses = remote.losses
        save()
    }

    func recordVoluntaryEscape(profileID: String = "player") {
        if profileID == Self.playerSeed.id {
            player.escapes += 1
        } else if let index = aiProfiles.firstIndex(where: { $0.id == profileID }) {
            aiProfiles[index].escapes += 1
        }
        save()
    }

    func profile(id: String) -> MahjongPlayerArchive? {
        if id == player.id {
            return player
        }
        return aiProfiles.first(where: { $0.id == id })
    }

    private var dayKey: String {
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func archiveID(for seat: Int, seatProfileIDs: [String]) -> String {
        seat == 0 ? Self.playerSeed.id : (seatProfileIDs.indices.contains(seat) ? seatProfileIDs[seat] : "")
    }

    private func nickname(for id: String) -> String {
        profile(id: id)?.nickname ?? "未知玩家"
    }

    private func credit(_ id: String, amount: Int) {
        if id == player.id {
            player.balance += amount
        } else if let index = aiProfiles.firstIndex(where: { $0.id == id }) {
            aiProfiles[index].balance += amount
        }
    }

    private func debit(_ id: String, amount: Int) {
        if id == player.id {
            player.balance -= amount
        } else if let index = aiProfiles.firstIndex(where: { $0.id == id }) {
            aiProfiles[index].balance -= amount
        }
    }

    private func markResult(id: String, won: Bool) {
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

    private func save() {
        let snapshot = Snapshot(
            player: player,
            aiProfiles: aiProfiles,
            lastCheckInDay: lastCheckInDay,
            lastBankruptcyAidDay: lastBankruptcyAidDay,
            lastAIRosterCheckDay: lastAIRosterCheckDay
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static let playerSeed = MahjongPlayerArchive(id: "player", nickname: "玩家", avatarStyle: .player, voiceGender: .female, balance: initialBalance)
    private static let roster: [MahjongPlayerArchive] = [
        MahjongPlayerArchive(id: "iron-man", nickname: "团团", avatarStyle: .panda, voiceGender: .male, balance: initialBalance),
        MahjongPlayerArchive(id: "spider-man", nickname: "小橘", avatarStyle: .cat, voiceGender: .female, balance: initialBalance),
        MahjongPlayerArchive(id: "captain-america", nickname: "云朵兔", avatarStyle: .rabbit, voiceGender: .female, balance: initialBalance),
        MahjongPlayerArchive(id: "thor", nickname: "星星鸮", avatarStyle: .owl, voiceGender: .male, balance: initialBalance),
        MahjongPlayerArchive(id: "hulk", nickname: "阿福熊", avatarStyle: .bear, voiceGender: .male, balance: initialBalance),
        MahjongPlayerArchive(id: "black-widow", nickname: "机灵狐", avatarStyle: .fox, voiceGender: .female, balance: initialBalance),
        MahjongPlayerArchive(id: "hawkeye", nickname: "小斑", avatarStyle: .tiger, voiceGender: .male, balance: initialBalance)
    ]
}

enum MahjongWinningHandType: String, Codable {
    case standard = "普通胡牌"
    case sevenPairs = "七对"
    case thirteenOrphans = "十三幺"

    var discardPayment: Int {
        switch self {
        case .standard: 1000
        case .sevenPairs: 1500
        case .thirteenOrphans: 2000
        }
    }

    var selfDrawPayment: Int {
        switch self {
        case .standard: 500
        case .sevenPairs: 700
        case .thirteenOrphans: 900
        }
    }
}
