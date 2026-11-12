@testable import Jarvis
import XCTest

final class JarvisScrollToTopTests: XCTestCase {
    func testReturnControlAppearsAfterTheSameDistanceAsWallpaper() {
        XCTAssertEqual(JarvisScrollToTop.visibilityThreshold, 500)
        XCTAssertFalse(JarvisScrollToTop.shouldShow(visibleMinY: 0))
        XCTAssertFalse(JarvisScrollToTop.shouldShow(visibleMinY: 499))
        XCTAssertTrue(JarvisScrollToTop.shouldShow(visibleMinY: 500))
        XCTAssertTrue(JarvisScrollToTop.shouldShow(visibleMinY: 1200))
    }
}
