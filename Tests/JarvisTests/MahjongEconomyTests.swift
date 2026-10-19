@testable import Jarvis
import XCTest

@MainActor
final class MahjongEconomyTests: XCTestCase {
    func testDailyRewardIs2500AndCanOnlyBeClaimedOncePerDay() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())

        XCTAssertTrue(archive.claimDailyReward())
        XCTAssertEqual(archive.player.balance, MahjongArchiveStore.initialBalance + 2_500)
        XCTAssertFalse(archive.claimDailyReward())
        XCTAssertEqual(archive.player.balance, MahjongArchiveStore.initialBalance + 2_500)
        XCTAssertEqual(MahjongArchiveStore.bankruptcyAid, 5_000)
    }

    func testSoloDiscardCapsPaymentAndBankruptcyAidStartsFromZero() throws {
        let defaults = makeDefaults()
        let initial = MahjongArchiveStore(defaults: defaults)
        try setBalance(200, for: "player", defaults: defaults)
        let archive = MahjongArchiveStore(defaults: defaults)
        let opponentID = try XCTUnwrap(initial.aiProfiles.first?.id)
        let opponentBalance = try XCTUnwrap(archive.profile(id: opponentID)?.balance)

        let result = archive.settle(
            winnerSeat: 1, discarderSeat: 0, handType: .thirteenOrphans,
            byDiscard: true, winnerConcealed: true,
            seatProfileIDs: ["player", opponentID, "", ""]
        )

        XCTAssertEqual(result.playerResults[0].balanceChange, -200)
        XCTAssertEqual(result.playerResults[1].balanceChange, 200)
        XCTAssertEqual(result.playerResults.map(\.balanceChange).reduce(0, +), 0)
        XCTAssertEqual(archive.player.balance, MahjongArchiveStore.bankruptcyAid)
        XCTAssertEqual(archive.profile(id: opponentID)?.balance, opponentBalance + 200)
        XCTAssertEqual(result.transfers.count, 1)
        XCTAssertTrue(result.transfers[0].contains("200"))
        XCTAssertTrue(result.playerBankrupt)
        XCTAssertFalse(result.playerNeedsExit)
    }

    func testLANSelfDrawCapsEachPayerAndConservesBalances() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let seats = [100, 200, 0, 300].enumerated().map { seat, balance in
            MahjongPlayerArchive(id: "seat-\(seat)", nickname: "玩家\(seat)", avatarStyle: .player, balance: balance)
        }

        let result = archive.settleLAN(
            winnerSeat: 3, discarderSeat: nil, handType: .sevenPairs,
            byDiscard: false, winnerConcealed: true, seatProfiles: seats
        )

        XCTAssertEqual(result.profiles.map(\.balance), [0, 0, 0, 600])
        XCTAssertEqual(result.settlement.playerResults.map(\.balanceChange), [-100, -200, 0, 300])
        XCTAssertEqual(result.profiles.map(\.balance).reduce(0, +), seats.map(\.balance).reduce(0, +))
        XCTAssertEqual(result.settlement.transfers.count, 2)
    }

    func testCompetitionPayoutTable() {
        let payment = MahjongCompetitionPayout.payment

        XCTAssertEqual(payment(.standard, true, false, true), 320)
        XCTAssertEqual(payment(.standard, true, false, false), 160)
        XCTAssertEqual(payment(.standard, false, false, false), 340)
        XCTAssertEqual(payment(.standard, true, true, true), 360)
        XCTAssertEqual(payment(.standard, false, true, false), 400)
        XCTAssertEqual(payment(.sevenPairs, true, true, true), 640)
        XCTAssertEqual(payment(.sevenPairs, false, true, false), 720)
        XCTAssertEqual(payment(.thirteenOrphans, true, true, true), 1_920)
        XCTAssertEqual(payment(.thirteenOrphans, false, true, false), 2_000)
    }

    func testLANDiscardCollectsBaseFromEveryOpponent() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let seats = (0 ..< 4).map { seat in
            MahjongPlayerArchive(id: "seat-\(seat)", nickname: "玩家\(seat)", avatarStyle: .player, balance: 10_000)
        }

        let result = archive.settleLAN(
            winnerSeat: 1, discarderSeat: 0, handType: .sevenPairs,
            byDiscard: true, winnerConcealed: true, seatProfiles: seats
        )

        XCTAssertEqual(result.settlement.playerResults.map(\.balanceChange), [-640, 960, -160, -160])
        XCTAssertEqual(result.profiles.map(\.balance).reduce(0, +), 40_000)
        XCTAssertEqual(result.settlement.transfers.count, 3)
    }

    func testSoloDiscardCollectsBaseFromEveryOpponent() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let opponents = Array(archive.aiProfiles.prefix(3).map(\.id))

        let result = archive.settle(
            winnerSeat: 1, discarderSeat: 0, handType: .standard,
            byDiscard: true, winnerConcealed: false,
            seatProfileIDs: ["player"] + opponents
        )

        XCTAssertEqual(result.playerResults.map(\.balanceChange), [-320, 640, -160, -160])
        XCTAssertEqual(result.playerResults.map(\.balanceChange).reduce(0, +), 0)
        XCTAssertEqual(result.transfers.count, 3)
    }

    func testLegacyNegativeBalanceIsClampedWhenArchiveLoads() throws {
        let defaults = makeDefaults()
        let initial = MahjongArchiveStore(defaults: defaults)
        let opponentID = try XCTUnwrap(initial.aiProfiles.first?.id)
        try setBalance(-250, for: "player", defaults: defaults)
        try setBalance(-100, for: opponentID, defaults: defaults)

        let reloaded = MahjongArchiveStore(defaults: defaults)

        XCTAssertEqual(reloaded.player.balance, 0)
        XCTAssertEqual(reloaded.profile(id: opponentID)?.balance, 0)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mahjong-economy-\(UUID().uuidString)")!
    }

    private func setBalance(_ balance: Int, for profileID: String, defaults: UserDefaults) throws {
        let key = "jarvis.mahjong.archive.v1"
        let data = try XCTUnwrap(defaults.data(forKey: key))
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if profileID == "player" {
            var player = try XCTUnwrap(snapshot["player"] as? [String: Any])
            player["balance"] = balance
            snapshot["player"] = player
        } else {
            var roster = try XCTUnwrap(snapshot["aiProfiles"] as? [[String: Any]])
            let index = try XCTUnwrap(roster.firstIndex { $0["id"] as? String == profileID })
            roster[index]["balance"] = balance
            snapshot["aiProfiles"] = roster
        }
        defaults.set(try JSONSerialization.data(withJSONObject: snapshot), forKey: key)
    }
}
