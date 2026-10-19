@testable import Jarvis
import XCTest

@MainActor
final class MahjongEconomyTests: XCTestCase {
    func testMultiplierEligibilityAndAIRollBoundaries() {
        XCTAssertEqual(MahjongDoubling.options(for: 2_999), [1])
        XCTAssertEqual(MahjongDoubling.options(for: 3_000), [1, 2])
        XCTAssertEqual(MahjongDoubling.options(for: 7_999), [1, 2])
        XCTAssertEqual(MahjongDoubling.options(for: 8_000), [1, 2, 4])
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 2_999, roll: 99), 1)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 3_000, roll: 59), 1)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 3_000, roll: 60), 2)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8_000, roll: 49), 1)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8_000, roll: 50), 2)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8_000, roll: 84), 2)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8_000, roll: 85), 4)
    }

    func testMultiplierChoiceValidatesOpeningBalanceAndResumesPlay() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .choosingMultiplier
        snapshot.isStarted = true
        snapshot.roundStartingBalances = [5_000, 8_000, 2_000, 8_000]
        snapshot.multipliers = [nil, 4, 1, 2]
        snapshot.pendingMultiplierSeats = [0]
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: true)

        game.chooseMultiplier(4)
        XCTAssertEqual(game.phase, .choosingMultiplier)
        XCTAssertNil(game.multipliers[0])

        game.chooseMultiplier(2)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.multipliers.compactMap { $0 }, [2, 4, 1, 2])
    }

    func testLANMultiplierSnapshotLetsGuestChooseOnlyAffordableOption() throws {
        let host = MahjongGame()
        var snapshot = host.makeLANSnapshot()
        snapshot.mode = .lan
        snapshot.phase = .choosingMultiplier
        snapshot.roundStartingBalances = [10_000, 2_000, 3_000, 8_000]
        snapshot.multipliers = [nil, 1, nil, 4]
        snapshot.pendingMultiplierSeats = [0, 2]
        snapshot.multiplierDeadline = Date().addingTimeInterval(10)

        let guest = MahjongGame()
        guest.mode = .lan
        guest.configureLAN(humanSeats: [0, 2], localSeat: 2, authority: false)
        guest.applyLANSnapshot(try JSONDecoder().decode(
            MahjongGameSnapshot.self, from: JSONEncoder().encode(snapshot)
        ))

        XCTAssertEqual(guest.localMultiplierOptions, [1, 2])
        XCTAssertNotNil(guest.multiplierDeadline)
        var sentValue: Int?
        guest.onLANAction = { action in
            if case let .multiplier(value) = action { sentValue = value }
        }
        guest.chooseMultiplier(4)
        XCTAssertNil(sentValue)
        guest.chooseMultiplier(2)
        XCTAssertEqual(sentValue, 2)
    }

    func testLANPaymentsMultiplyPerOpponentAndCapAtAvailableBalance() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let seats = [10_000, 500, 10_000, 10_000].enumerated().map { seat, balance in
            MahjongPlayerArchive(id: "seat-\(seat)", nickname: "玩家\(seat)", avatarStyle: .player, balance: balance)
        }
        let result = archive.settleLAN(
            winnerSeat: 0, discarderSeat: nil, handType: .standard,
            byDiscard: false, winnerConcealed: false, seatProfiles: seats,
            multipliers: [2, 4, 1, 2]
        )
        // Standard self draw is 340: 340×2×4 is capped by seat 1's 500.
        XCTAssertEqual(result.settlement.playerResults.map(\.balanceChange), [2_540, -500, -680, -1_360])
        XCTAssertEqual(result.profiles.map(\.balance).reduce(0, +), seats.map(\.balance).reduce(0, +))
        XCTAssertTrue(result.settlement.transfers[0].contains("2,720"))
        XCTAssertTrue(result.settlement.transfers[0].contains("实付 500"))
    }

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
