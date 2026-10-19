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
}
