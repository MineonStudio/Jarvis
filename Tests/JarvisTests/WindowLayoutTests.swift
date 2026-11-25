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
        XCTAssertEqual(right.minX - left.maxX, WindowSnapPlacement.windowGap)
        XCTAssertEqual(left.width + right.width + WindowSnapPlacement.windowGap, visibleFrame.width)
        XCTAssertEqual(left.width, visibleFrame.width / 2 - WindowSnapPlacement.windowGap)
        XCTAssertEqual(right.width, visibleFrame.width / 2)
    }

    func testCornerFramesTileTheVisibleArea() {
        let visibleFrame = NSRect(x: 0, y: 23, width: 1280, height: 755)
        let upperLeft = WindowSnapPlacement.upperLeft.frame(in: visibleFrame)
        let upperRight = WindowSnapPlacement.upperRight.frame(in: visibleFrame)
        let lowerLeft = WindowSnapPlacement.lowerLeft.frame(in: visibleFrame)
        let lowerRight = WindowSnapPlacement.lowerRight.frame(in: visibleFrame)

        XCTAssertEqual(upperRight.minX - upperLeft.maxX, WindowSnapPlacement.windowGap)
        XCTAssertEqual(lowerRight.minX - lowerLeft.maxX, WindowSnapPlacement.windowGap)
        XCTAssertEqual(upperLeft.minY - lowerLeft.maxY, WindowSnapPlacement.windowGap)
        XCTAssertEqual(upperRight.minY - lowerRight.maxY, WindowSnapPlacement.windowGap)
        XCTAssertEqual(upperLeft.minX, visibleFrame.minX)
        XCTAssertEqual(upperRight.maxX, visibleFrame.maxX)
        XCTAssertEqual(upperLeft.maxY, visibleFrame.maxY)
        XCTAssertEqual(lowerLeft.minY, visibleFrame.minY)
    }
}
