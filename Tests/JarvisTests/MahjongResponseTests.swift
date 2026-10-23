@testable import Jarvis
import XCTest

@MainActor
final class MahjongResponseTests: XCTestCase {
    func testResponseDeadlineIsAvailableForNeutralCompass() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .responding
        snapshot.pendingHumanSeats = [1]
        snapshot.responseCountdowns = [1: 5]
        let deadline = Date().addingTimeInterval(5)
        snapshot.responseCountdownDeadlines = [1: deadline]

        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)

        XCTAssertEqual(game.responseDecisionDeadline, deadline)
        XCTAssertEqual(game.responseDecisionDuration, 5)
        XCTAssertFalse(game.isCountdownActive(for: 1))
        XCTAssertNil(game.countdownDeadline(for: 1))
    }

    func testAIResponseDeadlineIsShownAfterHumanWindow() {
        let game = MahjongGame()
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .responding
        snapshot.pendingAISeats = [2]
        let deadline = Date().addingTimeInterval(20)
        snapshot.responseCountdownDeadlines = [2: deadline]

        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)

        XCTAssertEqual(game.responseDecisionDeadline, deadline)
        XCTAssertEqual(game.responseDecisionDuration, 20)
    }

    func testHumanChiResolvesBeforeCompetingAIClaim() {
        let game = MahjongGame()
        let discard = MahjongTile.suited(.characters, 3)
        let chi = MahjongCallOption(
            kind: .chi,
            heldTiles: [.suited(.characters, 1), .suited(.characters, 2)]
        )
        var snapshot = game.makeLANSnapshot()
        snapshot.mode = .lan
        snapshot.phase = .responding
        snapshot.isStarted = true
        snapshot.humanSeats = [0]
        snapshot.turn = 3
        snapshot.hands = [chi.heldTiles, [], [], []]
        snapshot.discards = [[], [], [], [discard]]
        snapshot.pendingTile = discard
        snapshot.pendingDiscarder = 3
        snapshot.pendingHumanSeats = [0]
        snapshot.pendingOptions = [0: [chi], 1: [MahjongCallOption(kind: .pong, heldTiles: [discard, discard])]]
        snapshot.pendingAISeats = [1]

        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: true)
        game.respond(to: chi)

        XCTAssertEqual(game.turn, 0)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.melds[0].first?.kind, .sequence)
        XCTAssertTrue(game.discards[3].isEmpty)
    }

    func testNewMatchDealerIsNotAlwaysTheLocalSeat() {
        let game = MahjongGame()
        var seen = Set<Int>()
        for _ in 0 ..< 40 {
            game.leaveTable()
            game.start()
            seen.insert(game.dealer)
            XCTAssertEqual(game.roundNumber, 1)
            XCTAssertEqual(game.turn, game.dealer)
        }
        XCTAssertGreaterThan(seen.count, 1)
    }

    func testNextRoundKeepsWinningDealerAndRotatesOtherwise() {
        let game = MahjongGame()
        game.start()
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .roundEnded
        snapshot.isStarted = true
        snapshot.dealer = 2
        snapshot.winner = 2
        snapshot.roundNumber = 1
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: true)

        game.nextRound()
        XCTAssertEqual(game.dealer, 2)
        XCTAssertEqual(game.roundNumber, 2)

        snapshot = game.makeLANSnapshot()
        snapshot.phase = .roundEnded
        snapshot.isStarted = true
        snapshot.dealer = 2
        snapshot.winner = 0
        snapshot.roundNumber = 2
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        game.applyLANSnapshot(snapshot)
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: true)

        game.nextRound()
        XCTAssertEqual(game.dealer, 3)
        XCTAssertEqual(game.roundNumber, 3)
    }

    func testMissingSuitCountdownMatchesDoubling() async throws {
        let game = MahjongGame()
        game.ruleset = .sichuan
        game.start()
        game.markReady()

        let timeout = Date().addingTimeInterval(8)
        while game.phase != .choosingMissingSuit, Date() < timeout {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(game.phase, .choosingMissingSuit)
        let remaining = try XCTUnwrap(game.multiplierDeadline).timeIntervalSinceNow
        XCTAssertGreaterThan(remaining, 8)
        XCTAssertLessThanOrEqual(remaining, MahjongDoubling.duration)
        XCTAssertNil(game.missingSuits[0])
        XCTAssertTrue(game.missingSuits.dropFirst().allSatisfy { $0 != nil })
        XCTAssertTrue(game.message.contains("\(Int(MahjongDoubling.duration))"))

        game.chooseMissingSuit(.dots)
        XCTAssertEqual(game.missingSuits[0], .dots)
        XCTAssertEqual(game.phase, .choosingMultiplier)
        let multiplierRemaining = try XCTUnwrap(game.multiplierDeadline).timeIntervalSinceNow
        XCTAssertGreaterThan(multiplierRemaining, 8)
        XCTAssertLessThanOrEqual(multiplierRemaining, MahjongDoubling.duration)
        game.leaveTable()
    }
}
