@testable import Jarvis
import XCTest

final class HomeMetricLevelTests: XCTestCase {
    func testColorLevelsChangeAtTwentyPercentBoundaries() {
        let samples: [(Double, HomeMetricLevel)] = [
            (0, .green), (0.1999, .green),
            (0.2, .yellowGreen), (0.3999, .yellowGreen),
            (0.4, .yellow), (0.5999, .yellow),
            (0.6, .orange), (0.7999, .orange),
            (0.8, .red), (1, .red)
        ]
        for (fraction, expected) in samples {
            XCTAssertEqual(HomeMetricLevel(fraction: fraction), expected, "fraction: \(fraction)")
        }
    }

    func testFiniteOutOfRangeFractionsClampToEndColors() {
        XCTAssertEqual(HomeMetricLevel(fraction: -0.1), .green)
        XCTAssertEqual(HomeMetricLevel(fraction: 1.1), .red)
    }

    func testUnavailableValuesDoNotLookLikeLowUsage() {
        XCTAssertNil(HomeMetricLevel(fraction: nil))
        XCTAssertNil(HomeMetricLevel(fraction: .nan))
        XCTAssertNil(HomeMetricLevel(fraction: .infinity))
        XCTAssertNil(HomeMetricLevel(fraction: -.infinity))
    }
}
