@testable import Jarvis
import XCTest

@MainActor
final class MahjongEconomyTests: XCTestCase {
    func testMultiplierEligibilityAndAIRollBoundaries() {
        XCTAssertEqual(MahjongDoubling.options(for: 2999), [1])
        XCTAssertEqual(MahjongDoubling.options(for: 3000), [1, 2])
        XCTAssertEqual(MahjongDoubling.options(for: 7999), [1, 2])
        XCTAssertEqual(MahjongDoubling.options(for: 8000), [1, 2, 4])
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 2999, roll: 99), 1)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 3000, roll: 59), 1)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 3000, roll: 60), 2)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8000, roll: 49), 1)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8000, roll: 50), 2)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8000, roll: 84), 2)
        XCTAssertEqual(MahjongDoubling.aiChoice(balance: 8000, roll: 85), 4)
    }

    func testMultiplierChoiceValidatesOpeningBalanceAndResumesPlay() async {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .choosingMultiplier
        snapshot.isStarted = true
        snapshot.roundStartingBalances = [5000, 8000, 2000, 8000]
        snapshot.multipliers = [nil, 4, 1, 2]
        snapshot.pendingMultiplierSeats = [0]
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: true)
        var spokenCue: String?
        game.onMahjongVoiceCue = { spokenCue = $0.key }

        game.chooseMultiplier(4)
        XCTAssertEqual(game.phase, .choosingMultiplier)
        XCTAssertNil(game.multipliers[0])

        game.chooseMultiplier(2)
        XCTAssertEqual(game.phase, .choosingMultiplier)
        try? await Task.sleep(for: .seconds(MahjongDoubling.revealPause + 0.25))
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.multipliers.compactMap { $0 }, [2, 4, 1, 2])
        XCTAssertEqual(spokenCue, "action-double")
    }

    func testNextRoundWaitsForHumanReadiness() {
        let game = MahjongGame()
        game.start()
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .roundEnded
        snapshot.roundNumber = 2
        snapshot.readySeats = [true, true, true, true]
        game.configureLAN(humanSeats: [0, 2], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        game.configureLAN(humanSeats: [0, 2], localSeat: 0, authority: true)

        game.nextRound()

        XCTAssertEqual(game.phase, .waitingForReady)
        XCTAssertEqual(game.roundNumber, 3)
        XCTAssertEqual(game.readySeats, [false, true, false, true])
    }

    func testAIChoicesAppearAfterVisibleDelay() async {
        let game = MahjongGame()
        game.onRoundBalancesRequested = { [10000, 10000, 5000, 2000] }
        game.start()
        game.markReady()
        for _ in 0 ..< 70 where game.phase != .choosingMultiplier {
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(game.phase, .choosingMultiplier)
        XCTAssertTrue(game.multipliers[1 ... 3].allSatisfy { $0 == nil })

        try? await Task.sleep(for: .seconds(5))
        XCTAssertTrue(game.multipliers[1 ... 3].allSatisfy { $0 != nil })
        XCTAssertEqual(game.phase, .choosingMultiplier)
        game.chooseMultiplier(1)
        try? await Task.sleep(for: .seconds(MahjongDoubling.revealPause + 0.25))
        XCTAssertEqual(game.phase, .playing)
    }

    func testLANMultiplierSnapshotLetsGuestChooseOnlyAffordableOption() throws {
        let host = MahjongGame()
        var snapshot = host.makeLANSnapshot()
        snapshot.mode = .lan
        snapshot.phase = .choosingMultiplier
        snapshot.roundStartingBalances = [10000, 2000, 3000, 8000]
        snapshot.multipliers = [nil, 1, nil, 4]
        snapshot.pendingMultiplierSeats = [0, 2]
        snapshot.multiplierDeadline = Date().addingTimeInterval(10)

        let guest = MahjongGame()
        guest.mode = .lan
        guest.configureLAN(humanSeats: [0, 2], localSeat: 2, authority: false)
        try guest.applyLANSnapshot(JSONDecoder().decode(
            MahjongGameSnapshot.self, from: JSONEncoder().encode(snapshot)
        ))

        XCTAssertEqual(guest.localMultiplierOptions, [1, 2])
        XCTAssertNotNil(guest.multiplierDeadline)
        var sentValue: Int?
        guest.onLANAction = { action in
            if case let .multiplier(value) = action {
                sentValue = value
            }
        }
        guest.chooseMultiplier(4)
        XCTAssertNil(sentValue)
        guest.chooseMultiplier(2)
        XCTAssertEqual(sentValue, 2)
    }

    func testLANPaymentsMultiplyPerOpponentAndCapAtAvailableBalance() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let seats = [10000, 500, 10000, 10000].enumerated().map { seat, balance in
            MahjongPlayerArchive(id: "seat-\(seat)", nickname: "玩家\(seat)", avatarStyle: .player, balance: balance)
        }
        let result = archive.settleLAN(
            winnerSeat: 0, discarderSeat: nil, handType: .standard,
            byDiscard: false, winnerConcealed: false, seatProfiles: seats,
            multipliers: [2, 4, 1, 2]
        )
        // Standard self draw is 340: 340×2×4 is capped by seat 1's 500.
        XCTAssertEqual(result.settlement.playerResults.map(\.balanceChange), [2540, -500, -680, -1360])
        XCTAssertEqual(result.profiles.map(\.balance).reduce(0, +), seats.map(\.balance).reduce(0, +))
        XCTAssertTrue(result.settlement.transfers[0].contains("2,720"))
        XCTAssertTrue(result.settlement.transfers[0].contains("实付 500"))
    }

    func testDailyRewardIs2500AndCanOnlyBeClaimedOncePerDay() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())

        XCTAssertTrue(archive.claimDailyReward())
        XCTAssertEqual(archive.player.balance, MahjongArchiveStore.initialBalance + 2500)
        XCTAssertFalse(archive.claimDailyReward())
        XCTAssertEqual(archive.player.balance, MahjongArchiveStore.initialBalance + 2500)
        XCTAssertEqual(MahjongArchiveStore.bankruptcyAid, 5000)
    }

    func testCheckInCalendarAndMatchHistorySurviveReload() {
        let defaults = makeDefaults()
        let archive = MahjongArchiveStore(defaults: defaults)
        XCTAssertTrue(archive.claimDailyReward())
        archive.recordMatch(MahjongMatchRecord(
            mode: .solo, ruleset: .national, roundNumber: 3,
            outcome: .win, winnerNickname: "玩家", balanceChange: 340,
            balanceAfter: archive.player.balance
        ))

        let reloaded = MahjongArchiveStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasCheckedIn(on: Date()))
        XCTAssertEqual(reloaded.checkInDays.count, 1)
        XCTAssertEqual(reloaded.currentCheckInStreak, 1)
        XCTAssertEqual(reloaded.matchHistory.count, 1)
        XCTAssertEqual(reloaded.matchHistory.first?.roundNumber, 3)
        XCTAssertEqual(reloaded.matchHistory.first?.balanceChange, 340)
    }

    func testRoundHistoryRecordsEachAISeatAndSurvivesReload() {
        let defaults = makeDefaults()
        let archive = MahjongArchiveStore(defaults: defaults)
        let ai = Array(archive.aiProfiles.prefix(3))
        let ids = [archive.player.id] + ai.map(\.id)
        let names = [archive.player.nickname] + ai.map(\.nickname)
        let results = zip(ids, names).enumerated().map { seat, pair in
            MahjongPlayerRoundSettlement(
                profileID: pair.0, nickname: pair.1,
                balanceChange: seat == 1 ? 300 : -100,
                balanceAfter: seat == 1 ? 10300 : 9900
            )
        }
        let settlement = MahjongArchiveSettlement(
            transfers: [], playerResults: results, notice: nil,
            campaignComplete: false, playerBankrupt: false, playerNeedsExit: false
        )

        archive.recordRound(MahjongRoundArchiveInput(
            mode: .solo, ruleset: .national, roundNumber: 2,
            winnerSeat: 1, localSeat: 0, humanSeats: [0],
            seatProfileIDs: ids, seatNames: names, settlement: settlement
        ))

        let reloaded = MahjongArchiveStore(defaults: defaults)
        XCTAssertEqual(reloaded.history(for: reloaded.player.id).first?.outcome, .loss)
        XCTAssertEqual(reloaded.history(for: ai[0].id).first?.outcome, .win)
        XCTAssertEqual(reloaded.history(for: ai[0].id).first?.balanceChange, 300)
        XCTAssertEqual(reloaded.history(for: ai[1].id).first?.balanceChange, -100)
        XCTAssertEqual(reloaded.history(for: ai[2].id).count, 1)
        XCTAssertEqual(reloaded.aiMatchHistory.values.map(\.count).reduce(0, +), 3)
    }

    func testLANRoundHistoryExcludesOtherHumanSeats() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let ai = Array(archive.aiProfiles.prefix(2))
        archive.recordRound(MahjongRoundArchiveInput(
            mode: .lan, ruleset: .national, roundNumber: 1,
            winnerSeat: nil, localSeat: 2, humanSeats: [0, 2],
            seatProfileIDs: ["host", ai[0].id, archive.player.id, ai[1].id],
            seatNames: ["房主", ai[0].nickname, archive.player.nickname, ai[1].nickname],
            settlement: nil
        ))

        XCTAssertEqual(archive.matchHistory.first?.outcome, .draw)
        XCTAssertEqual(archive.aiMatchHistory.values.map(\.count).reduce(0, +), 2)
        XCTAssertEqual(archive.history(for: ai[0].id).first?.outcome, .draw)
    }

    func testLegacyArchiveMigratesLastCheckInAndMarvelAvatar() throws {
        let defaults = makeDefaults()
        let archive = MahjongArchiveStore(defaults: defaults)
        XCTAssertTrue(archive.claimDailyReward())
        let key = "jarvis.mahjong.archive.v1"
        let data = try XCTUnwrap(defaults.data(forKey: key))
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        snapshot.removeValue(forKey: "checkInDays")
        snapshot.removeValue(forKey: "matchHistory")
        snapshot.removeValue(forKey: "aiMatchHistory")
        var player = try XCTUnwrap(snapshot["player"] as? [String: Any])
        player["avatarStyle"] = "iron"
        snapshot["player"] = player
        try defaults.set(JSONSerialization.data(withJSONObject: snapshot), forKey: key)

        let reloaded = MahjongArchiveStore(defaults: defaults)
        XCTAssertEqual(reloaded.player.avatarStyle, .player)
        XCTAssertEqual(reloaded.checkInDays.count, 1)
        XCTAssertTrue(reloaded.hasCheckedIn(on: Date()))
        XCTAssertTrue(reloaded.matchHistory.isEmpty)
        XCTAssertTrue(reloaded.aiMatchHistory.isEmpty)
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
        XCTAssertEqual(payment(.thirteenOrphans, true, true, true), 1920)
        XCTAssertEqual(payment(.thirteenOrphans, false, true, false), 2000)
    }

    func testLANDiscardCollectsBaseFromEveryOpponent() {
        let archive = MahjongArchiveStore(defaults: makeDefaults())
        let seats = (0 ..< 4).map { seat in
            MahjongPlayerArchive(id: "seat-\(seat)", nickname: "玩家\(seat)", avatarStyle: .player, balance: 10000)
        }

        let result = archive.settleLAN(
            winnerSeat: 1, discarderSeat: 0, handType: .sevenPairs,
            byDiscard: true, winnerConcealed: true, seatProfiles: seats
        )

        XCTAssertEqual(result.settlement.playerResults.map(\.balanceChange), [-640, 960, -160, -160])
        XCTAssertEqual(result.profiles.map(\.balance).reduce(0, +), 40000)
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
        try defaults.set(JSONSerialization.data(withJSONObject: snapshot), forKey: key)
    }
}
