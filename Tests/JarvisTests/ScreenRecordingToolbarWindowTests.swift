import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class ScreenRecordingToolbarWindowTests: XCTestCase {
    func testGlassHasRenderingSpaceAndReopeningPreservesItsPosition() throws {
        _ = NSApplication.shared
        let recorder = ScreenRecordingCoordinator()
        let controller = ScreenRecordingPanelController(recorder: recorder)
        defer { controller.hide() }
        controller.showLauncher()
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.contentView is NSHostingView<ScreenRecordingToolbar>
        })
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = try XCTUnwrap(controller.launcherFrame)
        XCTAssertEqual(visible.size, CGSize(width: 320, height: 52), "留白不能改变可见操作栏尺寸")
        XCTAssertGreaterThan(visible.minX, window.frame.minX)
        XCTAssertGreaterThan(visible.minY, window.frame.minY)
        XCTAssertLessThan(visible.maxX, window.frame.maxX)
        XCTAssertLessThan(visible.maxY, window.frame.maxY)
        XCTAssertEqual(window.frame.size, try XCTUnwrap(window.contentView).fittingSize)
        let scale = window.backingScaleFactor
        XCTAssertEqual(window.frame.minX * scale, (window.frame.minX * scale).rounded(), accuracy: 0.001)
        XCTAssertEqual(window.frame.minY * scale, (window.frame.minY * scale).rounded(), accuracy: 0.001)

        controller.hide()
        controller.showLauncher()
        XCTAssertEqual(controller.launcherFrame, visible)
    }

    func testCountdownResizePreservesTheVisibleBottomAndGlassMargin() async throws {
        _ = NSApplication.shared
        let recorder = ScreenRecordingCoordinator()
        let controller = ScreenRecordingPanelController(recorder: recorder)
        recorder.panelController = controller
        defer { controller.hide() }
        controller.showLauncher()
        let initial = try XCTUnwrap(controller.launcherFrame)
        recorder.phase = .countdown(3)
        await Task.yield()
        controller.resizeLauncher()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let visible = try XCTUnwrap(controller.launcherFrame)
        XCTAssertEqual(visible.height, initial.height)
        XCTAssertEqual(visible.minY, initial.minY)
        XCTAssertLessThan(visible.width, initial.width)
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.contentView is NSHostingView<ScreenRecordingToolbar>
        })
        XCTAssertGreaterThan(window.frame.height, visible.height)
        XCTAssertGreaterThan(window.frame.width, visible.width)
    }

    func testOptionsExpansionKeepsTheVisibleToolbarFrame() throws {
        _ = NSApplication.shared
        let recorder = ScreenRecordingCoordinator()
        let controller = ScreenRecordingPanelController(recorder: recorder)
        defer { controller.hide() }
        controller.showLauncher()
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.contentView is NSHostingView<ScreenRecordingToolbar>
        })
        let visible = try XCTUnwrap(controller.launcherFrame)
        let toolbar = try XCTUnwrap(window.contentView)
        let frame = window.frame
        let expanded = frame.insetBy(dx: -40, dy: -200)
        let container = ScreenRecordingOptionsContainer(frame: CGRect(origin: .zero, size: expanded.size), toolbar: toolbar)
        window.contentView = container
        container.addSubview(toolbar)
        window.setFrame(expanded, display: false)
        toolbar.frame = frame.offsetBy(dx: -expanded.minX, dy: -expanded.minY)
        XCTAssertEqual(controller.launcherFrame, visible)
        controller.hide()
        controller.showLauncher()
        XCTAssertEqual(controller.launcherFrame, visible)
    }
}
