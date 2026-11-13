@testable import Jarvis
import XCTest

final class HomeNetworkLookupPlanTests: XCTestCase {
    func testHomepageVisitLooksUpOnceUntilThePathChanges() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let visit = HomeNetworkLookupPlan.beginVisit()
        XCTAssertTrue(HomeNetworkLookupPlan.isDue(
            now: now, nextLookup: visit, generation: 3, handledGeneration: 3
        ))

        let settled = HomeNetworkLookupPlan.afterSuccess()
        XCTAssertFalse(HomeNetworkLookupPlan.isDue(
            now: now.addingTimeInterval(30 * 60),
            nextLookup: settled,
            generation: 3,
            handledGeneration: 3
        ))
        XCTAssertTrue(HomeNetworkLookupPlan.isDue(
            now: now, nextLookup: settled, generation: 4, handledGeneration: 3
        ))

        let failed = HomeNetworkLookupPlan.afterFailure(now: now, attempt: 0)
        XCTAssertEqual(failed.date, now.addingTimeInterval(60))
        XCTAssertEqual(failed.attempt, 1)
        XCTAssertFalse(HomeNetworkLookupPlan.isDue(
            now: now.addingTimeInterval(59),
            nextLookup: failed.date,
            generation: 3,
            handledGeneration: 3
        ))
    }
}
