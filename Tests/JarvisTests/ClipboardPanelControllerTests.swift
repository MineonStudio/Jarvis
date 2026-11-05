import AppKit
@testable import Jarvis
import QuartzCore
import SwiftUI
import XCTest

@MainActor
final class ClipboardPanelControllerTests: XCTestCase {
    func testShelfHasNoWindowControlsAndCanCloseAndReopenWithoutRecreatingContent() throws {
        _ = NSApplication.shared
        let controller = ClipboardPanelController(animationsEnabled: false)
        defer { controller.hide() }
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)

        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertNil(panel.standardWindowButton(kind))
        }
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
        controller.show {
            XCTFail("Reopening must preserve the existing content and its filters")
            return AnyView(Color.clear)
        }
        XCTAssertTrue(controller.panel === panel)
        XCTAssertTrue(panel.isVisible)
        controller.hide()
        XCTAssertFalse(panel.isVisible)
    }

    func testResizingKeepsTheShelfAtFullScreenWidthAndTheVisibleScreenTop() throws {
        _ = NSApplication.shared
        let controller = ClipboardPanelController(animationsEnabled: false)
        defer { controller.hide() }
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)
        let screen = try XCTUnwrap(panel.screen)
        let area = screen.visibleFrame

        for zoom in HistoryGridZoomLevel.allCases {
            let galleryHeight = ClipboardPanelLayout.galleryHeight(
                availableWidth: panel.frame.width - ClipboardPanelLayout.inset * 2, zoom: zoom
            )
            let height = ClipboardPanelLayout.inset * 2 + ClipboardPanelLayout.controlsHeight
                + ClipboardPanelLayout.controlSpacing + galleryHeight
            controller.updateHeight(height)
            XCTAssertEqual(panel.frame.height, ceil(height), accuracy: 1)
            XCTAssertEqual(panel.frame.maxY, area.maxY, accuracy: 1)
            XCTAssertEqual(panel.frame.minX, screen.frame.minX, accuracy: 1)
            XCTAssertEqual(panel.frame.width, screen.frame.width, accuracy: 1)
        }
        let frame = panel.frame
        controller.updateHeight(.nan)
        controller.updateHeight(-1)
        XCTAssertEqual(panel.frame, frame)
    }

    func testOutsideClicksDismissButShelfAndDropdownClicksKeepItOpen() throws {
        _ = NSApplication.shared
        let controller = ClipboardPanelController(animationsEnabled: false)
        defer { controller.hide() }
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)
        let inside = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let outside = CGPoint(x: panel.frame.midX, y: panel.frame.minY - 50)
        controller.dismissIfClickOutside(at: inside)
        XCTAssertTrue(panel.isVisible)

        let dropdown = NSPanel(
            contentRect: CGRect(x: outside.x - 40, y: outside.y - 40, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        dropdown.isReleasedWhenClosed = false
        panel.addChildWindow(dropdown, ordered: .above)
        dropdown.orderFrontRegardless()
        controller.dismissIfClickOutside(at: outside, in: dropdown)
        XCTAssertTrue(panel.isVisible)
        controller.dismissIfClickOutside(at: outside)
        XCTAssertTrue(panel.isVisible)
        panel.removeChildWindow(dropdown)
        dropdown.close()

        // A global event has no local window; a local event names the other
        // Jarvis window. Both must dismiss, including after reopening the shelf.
        controller.dismissIfClickOutside(at: outside)
        XCTAssertFalse(panel.isVisible)
        controller.show { AnyView(Color.clear) }
        let other = NSWindow(
            contentRect: CGRect(x: outside.x - 40, y: outside.y - 40, width: 80, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        other.isReleasedWhenClosed = false
        defer { other.close() }
        controller.dismissIfClickOutside(at: outside, in: other)
        XCTAssertFalse(panel.isVisible)
    }

    func testBottomCornerMaskTracksEveryResizeWithoutAnimation() throws {
        _ = NSApplication.shared
        let controller = ClipboardPanelController(animationsEnabled: false)
        defer { controller.hide() }
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)
        let hosting = try XCTUnwrap(panel.contentView)
        // Deliberately inspect each frame synchronously, without yielding for
        // SwiftUI to redraw; this is where shrinking used to expose square edges.
        for height in [480.0, 440.0, 400.0, 360.0, 320.0, 440.0] as [CGFloat] {
            controller.updateHeight(height)
            let mask = try XCTUnwrap(hosting.layer?.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            let bounds = hosting.bounds
            XCTAssertEqual(mask.frame.size, bounds.size)
            let top = hosting.isFlipped ? bounds.minY + 1 : bounds.maxY - 1
            let bottom = hosting.isFlipped ? bounds.maxY - 1 : bounds.minY + 1
            XCTAssertTrue(path.contains(CGPoint(x: bounds.minX + 1, y: top)))
            XCTAssertTrue(path.contains(CGPoint(x: bounds.maxX - 1, y: top)))
            XCTAssertFalse(path.contains(CGPoint(x: bounds.minX + 1, y: bottom)))
            XCTAssertFalse(path.contains(CGPoint(x: bounds.maxX - 1, y: bottom)))
            XCTAssertTrue(path.contains(CGPoint(x: bounds.midX, y: bottom)))
            XCTAssertNil(mask.animationKeys())
        }
    }

    func testReopeningDuringDismissalKeepsTheShelfVisibleAndInteractive() async throws {
        _ = NSApplication.shared
        let controller = ClipboardPanelController()
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)
        controller.hide()
        XCTAssertFalse(controller.isPresented)
        controller.show { AnyView(Color.clear) }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(controller.isPresented)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
        let top = try XCTUnwrap(panel.screen).visibleFrame.maxY
        XCTAssertEqual(panel.frame.maxY, top, accuracy: 1)
        controller.hide()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(panel.isVisible)
    }

    func testTwoRowHeightMatchesTheMainWindowAdaptiveGrid() throws {
        for available in [700.0, 1008.0, 1400.0, 1888.0] as [CGFloat] {
            for zoom in HistoryGridZoomLevel.allCases {
                // Render the main window's adaptive grid, rather than assuming
                // that the zoom target is the final, expanded card width.
                let row = LazyVGrid(columns: [GridItem(
                    .adaptive(minimum: zoom.cardWidth, maximum: .infinity),
                    spacing: HistoryGridMetrics.clipboardGridSpacing
                )], spacing: HistoryGridMetrics.clipboardGridSpacing) {
                    Color.clear.aspectRatio(HistoryGridLayout.aspectRatio, contentMode: .fit)
                }
                .frame(width: available)
                let renderer = ImageRenderer(content: row)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                let renderedRowHeight = CGFloat(image.height) / renderer.scale
                XCTAssertEqual(
                    ClipboardPanelLayout.galleryHeight(availableWidth: available, zoom: zoom),
                    renderedRowHeight * 2 + HistoryGridMetrics.clipboardGridSpacing,
                    accuracy: 1,
                    "available=\(available), zoom=\(zoom)"
                )
            }
        }
    }
}
