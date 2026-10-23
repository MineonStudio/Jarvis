@testable import Jarvis
import Network
import XCTest

final class MahjongLANRoomDiscoveryTests: XCTestCase {
    func testDiscoveredRoomShowsTheHostNickname() {
        let record = NWTXTRecord([
            "ruleset": MahjongRuleset.sichuan.rawValue,
            "humans": "2",
            "host": "小橘子"
        ])
        let room = discovered(record)

        XCTAssertEqual(room.hostNickname, "小橘子")
        XCTAssertEqual(room.ruleset, .sichuan)
        XCTAssertEqual(room.humanCount, 2)
        XCTAssertEqual(room.displayName, "缺一门 · 2/4 · 小橘子的房间")
    }

    func testDiscoveredRoomFallsBackWhenTheHostNameIsMissing() {
        let room = discovered(nil)

        XCTAssertEqual(room.hostNickname, "房主")
        XCTAssertEqual(room.ruleset, .national)
        XCTAssertEqual(room.humanCount, 1)
        XCTAssertEqual(room.displayName, "标准和牌 · 1/4 · 房主的房间")
    }

    func testDiscoveredRoomKeepsALongHostNameWithinSixteenCharacters() {
        let record = NWTXTRecord(["host": "一二三四五六七八九十甲乙丙丁戊己庚辛"])
        let room = discovered(record)

        XCTAssertEqual(room.hostNickname, "一二三四五六七八九十甲乙丙丁戊己")
        XCTAssertEqual(room.hostNickname.count, 16)
    }

    func testPlaqueTagsFollowTheScreenSideForEveryLocalSeat() {
        for localSeat in 0 ..< 4 {
            for seat in 0 ..< 4 {
                let view = (seat - localSeat + 4) % 4
                XCTAssertEqual(
                    MahjongPlaqueTags.stacksVertically(viewPosition: view),
                    view == 1 || view == 3,
                    "local \(localSeat) seat \(seat)"
                )
            }
        }
    }

    func testGuestBottomPlaqueUsesTheSameRowAsTheHost() {
        let guestSeat = 1
        let ownView = (guestSeat - guestSeat + 4) % 4
        let hostView = (0 - guestSeat + 4) % 4

        XCTAssertFalse(MahjongPlaqueTags.stacksVertically(viewPosition: ownView))
        XCTAssertEqual(ownView, 0)
        XCTAssertTrue(MahjongPlaqueTags.stacksVertically(viewPosition: hostView))
        XCTAssertEqual(hostView, 3)
    }

    private func discovered(_ record: NWTXTRecord?) -> MahjongLANRoom {
        MahjongLANRoom.discovered(
            code: "123456",
            endpoint: .hostPort(host: "127.0.0.1", port: 9),
            serviceName: "Jarvis-Mahjong-123456",
            txtRecord: record
        )
    }
}
