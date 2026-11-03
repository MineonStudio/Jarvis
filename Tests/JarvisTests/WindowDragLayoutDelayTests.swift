@testable import Jarvis
import XCTest

final class WindowDragLayoutDelayTests: XCTestCase {
    func testDraggingWaitsAFullSecondAfterWindowMotionBegins() {
        var delay = WindowDragLayoutDelay()
        delay.observe(isMoving: false, at: 10)
        XCTAssertFalse(delay.isReady(at: 20), "Holding the mouse without moving a window must not arm the picker")
        delay.observe(isMoving: true, at: 20)
        delay.observe(isMoving: true, at: 20.5)
        XCTAssertFalse(delay.isReady(at: 20.999))
        XCTAssertTrue(delay.isReady(at: 21))
        XCTAssertTrue(delay.isReady(at: 22))
    }

    func testCancellationAndAnotherDragAlwaysStartANewDelay() {
        var delay = WindowDragLayoutDelay()
        delay.observe(isMoving: true, at: 10)
        XCTAssertTrue(delay.isReady(at: 11))
        delay.reset()
        XCTAssertFalse(delay.isReady(at: 100))
        delay.observe(isMoving: true, at: 100)
        XCTAssertFalse(delay.isReady(at: 100.999))
        XCTAssertTrue(delay.isReady(at: 101))
    }

    func testShortDragNeverBecomesReadyBeforeMouseRelease() {
        var delay = WindowDragLayoutDelay()
        delay.observe(isMoving: true, at: 30)
        XCTAssertFalse(delay.isReady(at: 30.5))
        delay.reset()
        XCTAssertFalse(delay.isReady(at: 31.5), "An ended drag must not reveal or apply a stale layout")
    }
}
