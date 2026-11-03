import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class MenuBarConfigurationTests: XCTestCase {
    func testApplicationUsesRegularPolicySoTheDockIconRemainsVisible() {
        XCTAssertEqual(JarvisApplicationPresentation.activationPolicy, .regular)
    }

    func testClosingLastWindowKeepsTheMenuBarApplicationRunning() {
        XCTAssertFalse(JarvisApplicationPresentation.terminateAfterLastWindowClosed)
    }

    func testConfiguredMenuItemsHaveExplicitControllerTargets() {
        let controller = JarvisMenuBarController()
        let menu = controller.configuredMenuForTesting()
        let actionableItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(actionableItems.count, 6)
        XCTAssertFalse(actionableItems.contains { $0.title.contains("\u{63a7}\u{5236}\u{6761}") })
        for item in actionableItems {
            XCTAssertNotNil(item.action, item.title)
            XCTAssertIdentical(item.target, controller, item.title)
            XCTAssertTrue(item.isEnabled, item.title)
        }
    }

    func testWindowLayoutHasOneF5MenuItemInsteadOfIndividualBindings() throws {
        let controller = JarvisMenuBarController()
        let menu = controller.configuredMenuForTesting()
        let item = try XCTUnwrap(menu.items.first { $0.title == "窗口布局…" })
        XCTAssertEqual(item.keyEquivalent, ScreenshotShortcut.windowLayoutDefault.menuKeyEquivalent)
        XCTAssertEqual(item.keyEquivalentModifierMask, [])
        XCTAssertFalse(menu.items.contains { item in WindowSnapPlacement.allCases.contains { $0.title == item.title } })
    }

    func testScreenRecordingMenuUsesF2() throws {
        let controller = JarvisMenuBarController()
        let menu = controller.configuredMenuForTesting()
        let item = try XCTUnwrap(menu.items.first { $0.title == "屏幕录制…" })
        XCTAssertEqual(item.keyEquivalent, ScreenshotShortcut.screenRecordingDefault.menuKeyEquivalent)
        XCTAssertEqual(item.keyEquivalentModifierMask, [])
    }

    func testStatusItemUsesStableNamespacedAutosaveName() {
        let autosaveName = JarvisMenuBarController.menuBarAutosaveName

        XCTAssertEqual(
            autosaveName,
            "\(JarvisAppIdentity.bundleIdentifier).primary-status-item"
        )
    }

    func testMenuBarUsesVectorMascotIconWithAccessibleTitle() {
        let image = JarvisMenuBarController.makeMenuBarIcon()

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, JarvisMenuBarController.menuBarIconPointSize)
        XCTAssertEqual(
            JarvisMenuBarController.menuBarTitle,
            "JARVIS"
        )
    }
}
