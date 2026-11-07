import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class WindowLayoutAccessibilityAdjustmentTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 79, width: 2560, height: 1331)

    func testSuccessfulAXResizeClampedToMinimumHeightKeepsLowerLayoutsAboveDock() {
        for placement: WindowSnapPlacement in [.lowerLeft, .lowerRight, .halfBottom] {
            let window = LayoutAXWindow(minimumSize: CGSize(width: 800, height: 750))

            let result = apply(placement, to: window)

            XCTAssertEqual(result, .constrained)
            XCTAssertEqual(window.frame.height, 750)
            XCTAssertEqual(window.frame.minY, visibleFrame.minY, accuracy: 0.001)
            XCTAssertTrue(visibleFrame.contains(window.frame))
        }
    }

    func testSizeLimitsKeepAllLayoutsInsideAnOffsetDisplayWithSideDock() {
        let visible = CGRect(x: -1840, y: 1100, width: 1840, height: 1000)
        for placement in WindowSnapPlacement.allCases {
            let window = LayoutAXWindow(minimumSize: CGSize(width: 1100, height: 750))

            XCTAssertEqual(apply(placement, to: window, in: visible), .constrained)
            XCTAssertTrue(visible.contains(window.frame))
            if placement.unitRect.minX > 0 {
                XCTAssertEqual(window.frame.maxX, visible.maxX)
            }
        }
    }

    func testUnconstrainedResizeStillUsesExactRequestedFrame() {
        for placement in WindowSnapPlacement.allCases {
            let window = LayoutAXWindow()

            XCTAssertEqual(apply(placement, to: window), .applied)
            XCTAssertEqual(window.frame, placement.frame(in: visibleFrame))
        }
    }

    func testRejectedResizeMovesTheActualUnchangedSizeAboveDock() {
        let window = LayoutAXWindow()
        window.acceptsSize = false
        let size = window.frame.size

        XCTAssertEqual(apply(.lowerLeft, to: window), .constrained)
        XCTAssertEqual(window.frame.size, size)
        XCTAssertEqual(window.frame.minY, visibleFrame.minY)
    }

    func testFixedSizeWindowIsMovedWithoutRequestingResize() {
        let window = LayoutAXWindow()

        XCTAssertEqual(apply(.lowerRight, to: window, supportsResizing: false), .constrained)
        XCTAssertEqual(window.sizeWrites, 0)
        XCTAssertEqual(window.frame.maxX, visibleFrame.maxX)
        XCTAssertEqual(window.frame.minY, visibleFrame.minY)
    }

    func testUnreadableSizeDoesNotReapplyPositionUsingAnAssumedSize() {
        var positionWrites = 0
        let adjustment = WindowLayoutAccessibilityAdjustment(
            readSize: { nil }, setSize: { _ in true },
            setPosition: { _ in positionWrites += 1; return true }
        )
        XCTAssertEqual(adjustment.apply(.lowerLeft, in: visibleFrame, supportsResizing: true), .failed)
        XCTAssertEqual(positionWrites, 1)
    }

    func testFailedFinalPositionIsReportedAsFailure() {
        let adjustment = WindowLayoutAccessibilityAdjustment(
            readSize: { CGSize(width: 1280, height: 750) },
            setSize: { _ in true }, setPosition: { _ in false }
        )
        XCTAssertEqual(adjustment.apply(.lowerLeft, in: visibleFrame, supportsResizing: true), .failed)
    }

    private func apply(
        _ placement: WindowSnapPlacement,
        to window: LayoutAXWindow,
        in bounds: CGRect? = nil,
        supportsResizing: Bool = true
    ) -> WindowLayoutAccessibilityAdjustment.Result {
        WindowLayoutAccessibilityAdjustment(
            readSize: { window.frame.size },
            setSize: { window.setSize($0) },
            setPosition: { window.setPosition($0); return true }
        ).apply(placement, in: bounds ?? visibleFrame, supportsResizing: supportsResizing)
    }
}

/// Models an application that accepts AX writes while enforcing minimum size.
/// Resizing preserves the AX top-left position, rather than AppKit's bottom-left.
@MainActor
private final class LayoutAXWindow {
    private var axFrame = CGRect(x: 260, y: 200, width: 1400, height: 800)
    private let minimumSize: CGSize
    var acceptsSize = true
    private(set) var sizeWrites = 0

    init(minimumSize: CGSize = .zero) {
        self.minimumSize = minimumSize
    }

    var frame: CGRect {
        WindowLayoutCoordinates.flipped(axFrame, primaryDisplayTop: 1440)
    }

    func setPosition(_ frame: CGRect) {
        axFrame.origin = WindowLayoutCoordinates.flipped(frame, primaryDisplayTop: 1440).origin
    }

    func setSize(_ size: CGSize) -> Bool {
        sizeWrites += 1
        guard acceptsSize else { return false }
        axFrame.size = CGSize(
            width: max(size.width, minimumSize.width),
            height: max(size.height, minimumSize.height)
        )
        return true
    }
}
