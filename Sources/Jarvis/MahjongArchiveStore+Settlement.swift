import Foundation
import Observation

extension MahjongArchiveStore {
    func settle(
        winnerSeat: Int,
        discarderSeat: Int?,
        handType: MahjongWinningHandType,
        byDiscard: Bool,
        winnerConcealed: Bool,
        seatProfileIDs: [String],
        multipliers: [Int] = [1, 1, 1, 1]
    ) -> MahjongArchiveSettlement {
        guard (0 ..< 4).contains(winnerSeat) else {
            return MahjongArchiveSettlement(transfers: [], notice: nil, campaignComplete: false, playerBankrupt: false, playerNeedsExit: false)
        }

        let losers = (0 ..< 4).filter { $0 != winnerSeat }
        guard !byDiscard || discarderSeat.map({ losers.contains($0) }) == true else {
            return MahjongArchiveSettlement(transfers: [], notice: nil, campaignComplete: false, playerBankrupt: false, playerNeedsExit: false)
        }
        guard !losers.isEmpty else {
            return MahjongArchiveSettlement(transfers: [], notice: nil, campaignComplete: false, playerBankrupt: false, playerNeedsExit: false)
        }

        var transfers: [String] = []
        var totalPaid = 0
        var balanceChanges = Array(repeating: 0, count: 4)
        for loserSeat in losers {
            let payerID = archiveID(for: loserSeat, seatProfileIDs: seatProfileIDs)
            let winnerID = archiveID(for: winnerSeat, seatProfileIDs: seatProfileIDs)
            guard !payerID.isEmpty, !winnerID.isEmpty,
                  payerID != winnerID,
                  let payer = profile(id: payerID), profile(id: winnerID) != nil
            else { continue }
            let baseAmount = MahjongCompetitionPayout.payment(
                handType: handType, byDiscard: byDiscard, winnerConcealed: winnerConcealed,
                isDiscarder: loserSeat == discarderSeat
            )
            let winnerMultiplier = multipliers.indices.contains(winnerSeat) ? multipliers[winnerSeat] : 1
            let payerMultiplier = multipliers.indices.contains(loserSeat) ? multipliers[loserSeat] : 1
            let amount = baseAmount * winnerMultiplier * payerMultiplier
            let paid = min(amount, max(0, payer.balance))
            guard paid > 0 else { continue }
            debit(payerID, amount: paid)
            credit(winnerID, amount: paid)
            balanceChanges[loserSeat] -= paid
            balanceChanges[winnerSeat] += paid
            totalPaid += paid
            let payerName = nickname(for: payerID)
            let winnerName = nickname(for: winnerID)
            transfers.append("\(payerName) → \(winnerName)：基础 \(baseAmount) × 胜方 \(winnerMultiplier) × 支付方 \(payerMultiplier) = \(amount.formatted())，实付 \(paid.formatted()) 毛格子")
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
            let playerChange = balanceChanges[0] > 0 ? "+\(balanceChanges[0])" : (balanceChanges[0] < 0 ? "\(balanceChanges[0])" : nil)
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
        winnerConcealed: Bool,
        seatProfiles: [MahjongPlayerArchive],
        multipliers: [Int] = [1, 1, 1, 1]
    ) -> (settlement: MahjongArchiveSettlement, profiles: [MahjongPlayerArchive]) {
        guard (0 ..< 4).contains(winnerSeat), seatProfiles.count == 4 else {
            return (MahjongArchiveSettlement(transfers: [], campaignComplete: false, playerBankrupt: false, playerNeedsExit: false), seatProfiles)
        }

        var profiles = seatProfiles
        for seat in profiles.indices {
            profiles[seat].balance = max(0, profiles[seat].balance)
        }
        let losers = (0 ..< 4).filter { $0 != winnerSeat }
        guard !byDiscard || discarderSeat.map({ losers.contains($0) }) == true else {
            return (MahjongArchiveSettlement(transfers: [], campaignComplete: false, playerBankrupt: false, playerNeedsExit: false), seatProfiles)
        }
        var changes = Array(repeating: 0, count: 4)
        var transfers: [String] = []
        for loser in losers where (0 ..< 4).contains(loser) && loser != winnerSeat {
            let baseAmount = MahjongCompetitionPayout.payment(
                handType: handType, byDiscard: byDiscard, winnerConcealed: winnerConcealed,
                isDiscarder: loser == discarderSeat
            )
            let winnerMultiplier = multipliers.indices.contains(winnerSeat) ? multipliers[winnerSeat] : 1
            let payerMultiplier = multipliers.indices.contains(loser) ? multipliers[loser] : 1
            let amount = baseAmount * winnerMultiplier * payerMultiplier
            let paid = min(amount, max(0, profiles[loser].balance))
            guard paid > 0 else { continue }
            profiles[loser].balance -= paid
            profiles[winnerSeat].balance += paid
            changes[loser] -= paid
            changes[winnerSeat] += paid
            transfers.append("\(profiles[loser].nickname) → \(profiles[winnerSeat].nickname)：基础 \(baseAmount) × 胜方 \(winnerMultiplier) × 支付方 \(payerMultiplier) = \(amount.formatted())，实付 \(paid.formatted()) 毛格子")
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
        let balance = max(0, remote.balance)
        guard player.balance != balance || player.wins != remote.wins || player.losses != remote.losses
            || player.escapes != remote.escapes || player.eliminatedDay != remote.eliminatedDay else { return }
        player.balance = balance
        player.wins = remote.wins
        player.losses = remote.losses
        player.escapes = remote.escapes
        player.eliminatedDay = remote.eliminatedDay
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
}
