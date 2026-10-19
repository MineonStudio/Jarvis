@testable import Jarvis
import XCTest

final class MahjongHandLayoutTests: XCTestCase {
    func testHoverMovesOneQuarterOfTheTileHeight() {
        XCTAssertEqual(MahjongHandLayout.hoverTravel(tileHeight: 1.10), 0.275, accuracy: 0.00001)
    }

    func testEveryConcealedRowStaysCenteredAsItsTileCountChanges() throws {
        for count in 1 ... 14 {
            let offsets = MahjongHandLayout.centeredOffsets(count: count, tileWidth: 0.78, gap: 0.02)
            XCTAssertEqual(offsets.reduce(0, +) / Float(count), 0, accuracy: 0.00001)
            XCTAssertEqual(try XCTUnwrap(offsets.first) + offsets.last!, 0, accuracy: 0.00001)
        }
    }

    func testDrawnTileLeavesOneTileWidthToTheRightWithoutMovingTheRow() throws {
        for count in [1, 4, 7, 10, 13] {
            let row = MahjongHandLayout.centeredOffsets(count: count, tileWidth: 0.78, gap: 0.02)
            let drawn = MahjongHandLayout.drawnOffset(after: count, tileWidth: 0.78, gap: 0.02)
            let emptySpace = try (drawn - 0.78 / 2) - (XCTUnwrap(row.last) + 0.78 / 2)
            XCTAssertEqual(emptySpace, 0.78, accuracy: 0.00001)
            XCTAssertEqual(try (XCTUnwrap(row.first) + row.last!) / 2, 0, accuracy: 0.00001)
            XCTAssertGreaterThan(drawn, try XCTUnwrap(row.last))
        }
    }

    func testEmptyHandHasNoSlots() {
        XCTAssertTrue(MahjongHandLayout.centeredOffsets(count: 0, tileWidth: 0.78, gap: 0.02).isEmpty)
        XCTAssertEqual(MahjongHandLayout.drawnOffset(after: 0, tileWidth: 0.78, gap: 0.02), 0)
    }
}
