import AppKit
import AVKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class ScreenshotHistoryPreviewTests: XCTestCase {
    func testNativeVideoFillsTheZoomFrameWithoutAnIntrinsicPlayerSizeLimit() throws {
        for size in [CGSize(width: 1600, height: 900), CGSize(width: 500, height: 1200), CGSize(width: 2400, height: 1600)] {
            let player = AVPlayer()
            let hosting = NSHostingView(rootView: NativeVideoPreviewView(player: player)
                .frame(width: size.width, height: size.height))
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            let surface = try XCTUnwrap(videoSurface(in: hosting))
            XCTAssertEqual(surface.playerView.frame.width, size.width, accuracy: 1)
            XCTAssertEqual(surface.playerView.frame.height, size.height, accuracy: 1)
        }
    }

    private func videoSurface(in view: NSView) -> NativeVideoPreviewSurface? {
        if let surface = view as? NativeVideoPreviewSurface {
            return surface
        }
        return view.subviews.lazy.compactMap { self.videoSurface(in: $0) }.first
    }

    func testMouseZoomUsesBoundedTenPercentSteps() {
        let model = FullscreenMediaPreviewModel()

        XCTAssertEqual(model.zoom, 1)
        model.adjustZoom(by: 0.1)
        XCTAssertEqual(model.zoom, 1.1, accuracy: 0.001)

        model.adjustZoom(by: -0.1)
        XCTAssertEqual(model.zoom, 1, accuracy: 0.001)

        model.setZoom(0.2)
        XCTAssertEqual(model.zoom, 0.2, accuracy: 0.001)

        model.adjustZoom(by: -0.1)
        XCTAssertEqual(model.zoom, 0.2, accuracy: 0.001)

        model.setZoom(4)
        model.adjustZoom(by: 0.1)
        XCTAssertEqual(model.zoom, 4, accuracy: 0.001)
    }

    func testZoomAlwaysUsesTenPercentIncrements() {
        let model = FullscreenMediaPreviewModel()

        model.setZoom(1.55)

        XCTAssertEqual(model.zoom, 1.6, accuracy: 0.001)
    }

    func testTextPreviewUsesADocumentCardInsteadOfImageAspectScaling() {
        let maximumSize = CGSize(width: 1280, height: 800)
        let short = FullscreenMediaPreviewSizing.textDisplaySize(
            for: "简短文本",
            maximumSize: maximumSize
        )
        let long = FullscreenMediaPreviewSizing.textDisplaySize(
            for: String(repeating: "预览文本。", count: 400),
            maximumSize: maximumSize
        )

        XCTAssertEqual(short.width, FullscreenMediaPreviewSizing.textPanelWidth, accuracy: 0.5)
        XCTAssertEqual(long.width, short.width, accuracy: 0.5)
        XCTAssertEqual(short.height, FullscreenMediaPreviewSizing.textPanelMinimumHeight, accuracy: 0.5)
        XCTAssertEqual(long.height, FullscreenMediaPreviewSizing.textPanelMaximumHeight, accuracy: 0.5)
        XCTAssertLessThan(short.width / short.height, 1.8)
        XCTAssertGreaterThan(short.width / short.height, 1.2)
    }

    func testZoomChangesTheImageLayoutSizeDirectly() {
        let model = FullscreenMediaPreviewModel()
        model.setZoom(1.5)

        XCTAssertEqual(
            model.displaySize(for: CGSize(width: 800, height: 600)),
            CGSize(width: 1200, height: 900)
        )
    }

    func testBorderlessPreviewSizingDoesNotReserveTitlebarSpace() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screenFrame

        XCTAssertEqual(
            PreviewWindowSupport.maximumContentSize(
                for: screenFrame,
                topChromeHeight: 0
            ).height,
            screenFrame.height - PreviewWindowSupport.screenInset
        )
        XCTAssertEqual(
            PreviewWindowSupport.centeredFrame(
                contentSize: CGSize(width: 600, height: 400),
                visibleFrame: visibleFrame,
                topChromeHeight: 0
            ).midY,
            visibleFrame.midY,
            accuracy: 0.001
        )
    }

    func testBorderlessPreviewConfigurationRemovesWindowChrome() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        PreviewWindowSupport.configureBorderlessPreviewPanel(panel)

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertEqual(panel.title, "")
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
    }

    func testDimmingPanelConsumesMouseEventsWithoutPassingThrough() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        PreviewWindowSupport.configureDimmingPanel(
            panel,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isMovableByWindowBackground)
    }
}
