import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class WindowLayoutPickerTests: XCTestCase {
    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 180, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func testNativeCaptureRejectsPickerPanelsAndClosedWindows() {
        let original = window()
        XCTAssertNotNil(WindowDragTarget.captureNativeWindow(original))
        original.identifier = NSUserInterfaceItemIdentifier("Jarvis.WindowSnapOption.leftRight")
        XCTAssertNil(WindowDragTarget.captureNativeWindow(original))
        original.identifier = nil
        original.close()
        XCTAssertNil(WindowDragTarget.captureNativeWindow(original))
    }

    func testClickAppliesToCapturedWindowEvenAfterAnotherWindowBecomesKey() throws {
        let original = window()
        let other = window()
        defer { original.close(); other.close() }
        let target = try XCTUnwrap(WindowDragTarget.captureNativeWindow(original))
        let screen = try XCTUnwrap(NSScreen.main)
        var feedback: [String] = []
        let controller = WindowLayoutPickerController(
            layoutController: WindowLayoutController { feedback.append($0) },
            overlay: WindowSnapOverlayController(animationsEnabled: false)
        )
        defer { controller.cancel() }
        controller.present(target: target, on: screen)
        let geometry = try XCTUnwrap(controller.overlay.geometry)
        let rect = geometry.localRect(for: .halfTop)
        let pointer = CGPoint(x: geometry.frame.minX + rect.midX, y: geometry.frame.minY + rect.midY)
        for panel in controller.overlay.optionPanels.values {
            XCTAssertFalse(panel.ignoresMouseEvents)
            XCTAssertFalse(panel.canBecomeKey)
        }
        let otherFrame = other.frame
        other.makeKey()
        controller.mouseDown(at: pointer)
        controller.mouseUp(at: pointer)
        XCTAssertEqual(original.frame, WindowSnapPlacement.halfTop.frame(in: WindowLayoutScreenArea.visibleFrame(for: screen)))
        XCTAssertEqual(other.frame, otherFrame)
        XCTAssertTrue(feedback.isEmpty)
        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(controller.overlay.optionPanels.values.allSatisfy(\.ignoresMouseEvents))
    }

    func testCancellationAndMismatchedPressReleaseNeverChangeTheTarget() throws {
        let original = window()
        defer { original.close() }
        let frame = original.frame
        let target = try XCTUnwrap(WindowDragTarget.captureNativeWindow(original))
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = WindowLayoutPickerController(
            layoutController: WindowLayoutController { _ in },
            overlay: WindowSnapOverlayController(animationsEnabled: false)
        )
        defer { controller.cancel() }
        controller.present(target: target, on: screen)
        let geometry = try XCTUnwrap(controller.overlay.geometry)
        let left = geometry.localRect(for: .halfLeft)
        let right = geometry.localRect(for: .halfRight)
        controller.mouseDown(at: CGPoint(x: geometry.frame.minX + left.midX, y: geometry.frame.minY + left.midY))
        controller.mouseUp(at: CGPoint(x: geometry.frame.minX + right.midX, y: geometry.frame.minY + right.midY))
        XCTAssertEqual(original.frame, frame)
        XCTAssertFalse(controller.isPresented)
        controller.present(target: target, on: screen)
        controller.mouseDown(at: CGPoint(x: screen.frame.minX, y: screen.frame.minY))
        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(original.frame, frame)
        controller.present(target: target, on: screen)
        controller.cancel()
        XCTAssertEqual(original.frame, frame)
    }

    func testPresentationDoesNotRequirePointerToBeOnTheTargetScreen() throws {
        let original = window()
        defer { original.close() }
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = WindowLayoutPickerController(
            layoutController: WindowLayoutController { _ in },
            overlay: WindowSnapOverlayController(animationsEnabled: false)
        )
        defer { controller.cancel() }
        try controller.present(target: XCTUnwrap(WindowDragTarget.captureNativeWindow(original)), on: screen)
        controller.overlay.updateSelection(at: CGPoint(x: screen.frame.minX - 1000, y: screen.frame.minY - 1000))
        XCTAssertTrue(controller.isPresented)
        XCTAssertTrue(controller.overlay.optionPanels.values.allSatisfy(\.isVisible))
        XCTAssertNil(controller.overlay.selection)
    }

    func testLegacyLayoutPreferencesAreRemovedWithoutChangingOtherShortcuts() throws {
        let suite = "jarvis-layout-migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy", forKey: "jarvis.window-layout.shortcut.halfLeft")
        defaults.set("screenshot", forKey: "jarvis.screenshot.shortcut")
        defaults.set(true, forKey: WindowDragLayoutPreference.key)
        WindowLayoutShortcutMigration.apply(to: defaults)
        WindowLayoutShortcutMigration.apply(to: defaults)
        XCTAssertNil(defaults.object(forKey: "jarvis.window-layout.shortcut.halfLeft"))
        XCTAssertEqual(defaults.string(forKey: "jarvis.screenshot.shortcut"), "screenshot")
        XCTAssertTrue(defaults.bool(forKey: WindowDragLayoutPreference.key))
    }
}
