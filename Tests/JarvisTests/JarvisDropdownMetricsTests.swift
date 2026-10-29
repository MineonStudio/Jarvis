import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

final class JarvisDropdownMetricsTests: XCTestCase {
    private let wallpaperSortingOptions = [
        JarvisDropdownOption(id: "toplist", title: "热门"),
        JarvisDropdownOption(id: "dateAdded", title: "最新"),
        JarvisDropdownOption(id: "views", title: "浏览量"),
        JarvisDropdownOption(id: "favorites", title: "收藏数")
    ]

    func testTriggerWidthFollowsTheCurrentTitleInsteadOfTheLongestOption() {
        let shortTitle = JarvisDropdownMetrics.triggerWidth(for: "最新")
        let longTitle = JarvisDropdownMetrics.triggerWidth(for: "浏览量")

        XCTAssertLessThan(shortTitle, longTitle)
        XCTAssertLessThan(shortTitle, JarvisDropdownMetrics.menuWidth(
            for: "最新",
            options: wallpaperSortingOptions
        ))
    }

    func testTriggerWidthKeepsASmallFloorForVeryShortTitles() {
        XCTAssertGreaterThanOrEqual(
            JarvisDropdownMetrics.triggerWidth(for: "热"),
            JarvisDropdownMetrics.minimumTriggerWidth
        )
    }

    func testMenuWidthStillReservesTheLongestOption() {
        let menuWidth = JarvisDropdownMetrics.menuWidth(
            for: "最新",
            options: wallpaperSortingOptions
        )
        let widestOptionWidth = JarvisDropdownMetrics.triggerWidth(for: "浏览量")

        XCTAssertGreaterThanOrEqual(menuWidth, widestOptionWidth)
        XCTAssertGreaterThanOrEqual(menuWidth, JarvisDropdownMetrics.minimumMenuWidth)
    }

    func testWidthsRespectTheMaximumCap() {
        let longTitle = "5120 × 1440 及以上，以及更长的分辨率描述文本"

        XCTAssertLessThanOrEqual(
            JarvisDropdownMetrics.triggerWidth(for: longTitle, maximumWidth: 480),
            480
        )
        XCTAssertLessThanOrEqual(
            JarvisDropdownMetrics.menuWidth(
                for: longTitle,
                options: [JarvisDropdownOption(id: "any", title: longTitle)],
                maximumWidth: 480
            ),
            480
        )
    }

    func testMenuPanelAlignsItsLeftEdgeWithTheTrigger() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertEqual(
            JarvisDropdownMetrics.menuOriginX(
                anchorMinX: 400,
                panelWidth: 200,
                visibleFrame: visibleFrame
            ),
            400 - JarvisDropdownMetrics.menuEdgePadding
        )
    }

    func testMenuPanelStaysOnScreenNearBothEdges() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertEqual(
            JarvisDropdownMetrics.menuOriginX(
                anchorMinX: 980,
                panelWidth: 200,
                visibleFrame: visibleFrame
            ),
            800
        )
        XCTAssertEqual(
            JarvisDropdownMetrics.menuOriginX(
                anchorMinX: -50,
                panelWidth: 200,
                visibleFrame: visibleFrame
            ),
            0
        )
    }

    func testMenuPanelPinsToTheScreenEdgeWhenItIsWiderThanTheScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 150, height: 800)

        XCTAssertEqual(
            JarvisDropdownMetrics.menuOriginX(
                anchorMinX: 100,
                panelWidth: 200,
                visibleFrame: visibleFrame
            ),
            0
        )
    }

    func testWidthsDropTheArrowWhenTheControlHidesIt() {
        let withArrow = JarvisDropdownMetrics.triggerWidth(for: "最新", includesArrow: true)
        let withoutArrow = JarvisDropdownMetrics.triggerWidth(for: "最新", includesArrow: false)

        XCTAssertGreaterThan(withArrow, withoutArrow)
    }

    func testMenuOpensAboveTriggerNearBottomOfScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(JarvisDropdownMetrics.menuOriginY(
            anchor: CGRect(x: 400, y: 50, width: 200, height: 30),
            panelHeight: 400,
            visibleFrame: screen
        ), 80 + JarvisDropdownMetrics.triggerGap)
    }

    func testMenuClampsToScreenWhenNeitherSideHasEnoughRoom() {
        let screen = CGRect(x: 0, y: 100, width: 1000, height: 600)
        let origin = JarvisDropdownMetrics.menuOriginY(
            anchor: CGRect(x: 400, y: 350, width: 200, height: 30),
            panelHeight: 400,
            visibleFrame: screen
        )
        XCTAssertGreaterThanOrEqual(origin, screen.minY)
        XCTAssertLessThanOrEqual(origin + 400, screen.maxY)
    }

    @MainActor
    func testHundredsOfModelsFitInsideScrollablePanel() {
        let view = NSHostingView(rootView: JarvisDropdownPillMenuList(
            options: (0 ..< 500).map { JarvisDropdownOption(id: "model-\($0)", title: "Model \($0)") },
            selectionID: "model-0",
            showsSelectedOption: true,
            controlWidth: 320,
            searchThreshold: 10,
            maximumHeight: 400,
            onSelect: { _ in }
        ))
        XCTAssertGreaterThan(view.fittingSize.height, 200)
        XCTAssertLessThanOrEqual(view.fittingSize.height, 400)
    }
}
