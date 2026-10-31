import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class ScreenshotEditingSurfaceTests: XCTestCase {
    func testCanvasAndToolbarShareTheEditingWindow() throws {
        _ = NSApplication.shared
        let controller = ScreenshotCaptureController()
        defer { controller.dismissResult() }
        let image = NSImage(size: CGSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        image.unlockFocus()
        try controller.showHistoryResult(data: XCTUnwrap(image.tiffRepresentation)) { _ in }

        let window = try XCTUnwrap(controller.resultWindow)
        let surface = try XCTUnwrap(window.contentView as? ScreenshotEditingSurface)
        XCTAssertTrue(surface.canvas.window === window)
        XCTAssertTrue(surface.toolbar.window === window)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isKeyWindow, "截图编辑激活后，操作栏所在窗口必须真正成为 key window")
        XCTAssertTrue(window.firstResponder === surface.canvas)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true, "操作栏不应再放在始终失焦的子窗口里")
    }

    func testExpandingToolbarPreservesCanvasScreenCoordinates() {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let surface = ScreenshotEditingSurface(canvas: NSView(), toolbar: NSView())
        surface.canvas.autoresizingMask = [.width, .height]
        window.contentView = surface
        let canvas = CGRect(x: -900, y: 300, width: 500, height: 300)
        let compact = CGRect(x: -920, y: 232, width: 546, height: 52)
        let expanded = CGRect(x: -920, y: 182, width: 546, height: 102)

        surface.place(canvasFrame: canvas, toolbarFrame: compact, in: window)
        XCTAssertEqual(surface.canvasFrameOnScreen, canvas)
        surface.place(canvasFrame: surface.canvasFrameOnScreen, toolbarFrame: expanded, in: window)
        XCTAssertEqual(surface.canvasFrameOnScreen, canvas)
        XCTAssertEqual(window.convertToScreen(surface.toolbar.frame), expanded)
        surface.place(canvasFrame: surface.canvasFrameOnScreen, toolbarFrame: compact, in: window)
        XCTAssertEqual(surface.canvasFrameOnScreen, canvas)
    }

    func testToolbarClicksDoNotCountAsCanvasDoubleClicksOrColorSampling() {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let surface = ScreenshotEditingSurface(canvas: NSView(), toolbar: NSView())
        window.contentView = surface
        surface.place(
            canvasFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            toolbarFrame: CGRect(x: 200, y: 120, width: 546, height: 52),
            in: window
        )

        XCTAssertFalse(surface.isCanvasLocation(NSPoint(x: 200, y: 40)))
        XCTAssertTrue(surface.isCanvasLocation(NSPoint(x: 200, y: 200)))
        XCTAssertFalse(surface.isCanvasLocation(NSPoint(x: -1, y: 200)))
    }
}
