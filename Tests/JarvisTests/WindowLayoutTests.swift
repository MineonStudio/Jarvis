import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class WindowLayoutTests: XCTestCase {
    func testScreenshotGalleryUsesClipboardGridMetrics() {
        XCTAssertEqual(
            HistoryGridMetrics.clipboardCardHeight,
            HistoryGridMetrics.clipboardCardWidth * 9 / 16,
            accuracy: 0.001
        )
        XCTAssertEqual(HistoryGridMetrics.clipboardActionButtonSize, 32)
        XCTAssertEqual(HistoryGridMetrics.clipboardCornerRadius, 12)
        XCTAssertEqual(HistoryGridMetrics.clipboardGridSpacing, 12)
    }

    func testLowerLayoutsStayAboveBottomDock() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let safeFrame = WindowLayoutScreenArea.safeVisibleFrame(
            screenFrame: screenFrame,
            visibleFrame: screenFrame,
            dockFrame: NSRect(x: 0, y: 0, width: 1440, height: 96)
        )

        let lowerLeft = WindowSnapPlacement.lowerLeft.frame(in: safeFrame)
        let lowerRight = WindowSnapPlacement.lowerRight.frame(in: safeFrame)

        XCTAssertEqual(safeFrame.minY, 96)
        XCTAssertGreaterThanOrEqual(lowerLeft.minY, 96)
        XCTAssertGreaterThanOrEqual(lowerRight.minY, 96)
        XCTAssertLessThanOrEqual(lowerLeft.minY, lowerLeft.maxY)
        XCTAssertLessThanOrEqual(lowerRight.minY, lowerRight.maxY)
    }

    func testHalfFramesUseTheCompleteVisibleArea() {
        let visibleFrame = NSRect(x: 12, y: 24, width: 1001, height: 777)
        let left = WindowSnapPlacement.halfLeft.frame(in: visibleFrame)
        let right = WindowSnapPlacement.halfRight.frame(in: visibleFrame)

        XCTAssertEqual(left.minX, visibleFrame.minX)
        XCTAssertEqual(right.maxX, visibleFrame.maxX)
        XCTAssertEqual(left.minY, visibleFrame.minY)
        XCTAssertEqual(right.maxY, visibleFrame.maxY)
        XCTAssertGreaterThanOrEqual(right.minX - left.maxX, WindowSnapPlacement.windowGap)
        XCTAssertLessThanOrEqual(left.maxX, right.minX - WindowSnapPlacement.windowGap)
        XCTAssertEqual(left.maxX, floor(left.maxX))
        XCTAssertEqual(right.minX, ceil(right.minX))
        XCTAssertEqual(left.minX, floor(left.minX))
        XCTAssertEqual(right.maxX, floor(right.maxX))
    }

    func testCornerFramesTileTheVisibleArea() {
        let visibleFrame = NSRect(x: 0, y: 23, width: 1280, height: 755)
        let upperLeft = WindowSnapPlacement.upperLeft.frame(in: visibleFrame)
        let upperRight = WindowSnapPlacement.upperRight.frame(in: visibleFrame)
        let lowerLeft = WindowSnapPlacement.lowerLeft.frame(in: visibleFrame)
        let lowerRight = WindowSnapPlacement.lowerRight.frame(in: visibleFrame)

        XCTAssertGreaterThanOrEqual(upperRight.minX - upperLeft.maxX, WindowSnapPlacement.windowGap)
        XCTAssertGreaterThanOrEqual(lowerRight.minX - lowerLeft.maxX, WindowSnapPlacement.windowGap)
        XCTAssertGreaterThanOrEqual(upperLeft.minY - lowerLeft.maxY, WindowSnapPlacement.windowGap)
        XCTAssertGreaterThanOrEqual(upperRight.minY - lowerRight.maxY, WindowSnapPlacement.windowGap)
        XCTAssertEqual(lowerLeft.maxY, floor(lowerLeft.maxY))
        XCTAssertEqual(upperLeft.minY, ceil(upperLeft.minY))
        XCTAssertEqual(upperLeft.minX, visibleFrame.minX)
        XCTAssertEqual(upperRight.maxX, visibleFrame.maxX)
        XCTAssertEqual(upperLeft.maxY, visibleFrame.maxY)
        XCTAssertEqual(lowerLeft.minY, visibleFrame.minY)
    }
}
