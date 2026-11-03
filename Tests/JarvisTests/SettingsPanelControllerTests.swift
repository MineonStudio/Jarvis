import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class SettingsPanelControllerTests: XCTestCase {
    func testSettingsUsesAnIndependentNonactivatingUtilityPanel() throws {
        let controller = SettingsPanelController()
        defer { controller.close() }
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)

        XCTAssertEqual(panel.title, "设置")
        XCTAssertEqual(panel.identifier?.rawValue, "Jarvis.SettingsPanel")
        XCTAssertNil(panel.parent)
        XCTAssertNil(panel.sheetParent)
        XCTAssertTrue(panel.styleMask.contains([.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel]))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        let hosting = try XCTUnwrap(panel.contentView as? NSHostingView<AnyView>)
        XCTAssertTrue(hosting.sizingOptions.isEmpty)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertTrue(try XCTUnwrap(panel.standardWindowButton(button)).isEnabled)
        }
    }

    func testOpeningClosingAndReopeningSettingsKeepsTheMainWindowUntouched() async throws {
        let main = NSWindow(
            contentRect: NSRect(x: 40, y: 60, width: 1169, height: 811),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        main.isReleasedWhenClosed = false
        main.contentView = NSView(frame: main.contentLayoutRect)
        let originalFrame = main.frame
        let originalContent = main.contentView
        let controller = SettingsPanelController()
        defer {
            controller.close()
            main.close()
        }
        var contentCreations = 0
        for _ in 0 ..< 3 {
            controller.show {
                contentCreations += 1
                return AnyView(Color.clear)
            }
            let panel = try XCTUnwrap(controller.panel)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel !== main)
            XCTAssertFalse(main.childWindows?.contains(panel) ?? false)
            XCTAssertEqual(main.frame, originalFrame)
            XCTAssertTrue(main.contentView === originalContent)
            controller.close()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(main.frame, originalFrame)
            XCTAssertTrue(controller.panel === panel)
        }
        XCTAssertEqual(contentCreations, 1)
    }

    func testRepeatedShowPreservesThePanelAndUserChosenSize() async throws {
        let controller = SettingsPanelController()
        defer { controller.close() }
        controller.show { AnyView(Color.clear) }
        let panel = try XCTUnwrap(controller.panel)
        // AppKit constrains a reopened window to the screen. CI uses a 1024pt
        // display, so exercise user sizes that fit its actual visible bounds.
        let available = try XCTUnwrap(panel.screen ?? NSScreen.main).visibleFrame.insetBy(dx: 20, dy: 20)
        let expanded = NSSize(width: min(1100, available.width), height: min(750, available.height))
        for size in [SettingsLayout.minimumWindowSize, expanded] {
            panel.setContentSize(size)
            let resizedSize = panel.frame.size
            controller.show {
                XCTFail("A visible settings window must be reused")
                return AnyView(Color.clear)
            }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(controller.panel === panel)
            XCTAssertEqual(panel.frame.size, resizedSize)
            controller.close()
            controller.show {
                XCTFail("Reopening settings must retain its existing content")
                return AnyView(Color.clear)
            }
            XCTAssertTrue(controller.panel === panel)
            XCTAssertEqual(panel.frame.size, resizedSize)
        }
    }
}
