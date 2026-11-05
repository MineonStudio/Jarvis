import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class FunctionShortcutSettingsTests: XCTestCase {
    func testWindowLayoutShortcutLoadsSavedChoiceAndFallsBackForMissingOrInvalidData() throws {
        let suite = "jarvis-window-layout-shortcut-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(WindowLayoutShortcutPreference.load(from: defaults), .windowLayoutDefault)

        let custom = candidate(keyCode: 37)
        try defaults.set(JSONEncoder().encode(custom), forKey: WindowLayoutShortcutPreference.key)
        XCTAssertEqual(WindowLayoutShortcutPreference.load(from: defaults), custom)

        defaults.set(Data("invalid".utf8), forKey: WindowLayoutShortcutPreference.key)
        XCTAssertEqual(WindowLayoutShortcutPreference.load(from: defaults), .windowLayoutDefault)
    }

    func testBatchShortcutUpdateSupportsSwappingOccupiedKeys() throws {
        let firstKey = candidate(keyCode: 0)
        let secondKey = candidate(keyCode: 1)
        try requireAvailable([firstKey, secondKey])
        let first = ScreenshotShortcutManager(binding: firstKey, hotKeyID: 21001) {}
        let second = ScreenshotShortcutManager(binding: secondKey, hotKeyID: 21002) {}
        XCTAssertTrue(first.isRegistered)
        XCTAssertTrue(second.isRegistered)

        XCTAssertTrue(ScreenshotShortcutManager.updateTogether([(first, secondKey), (second, firstKey)]))
        XCTAssertTrue(first.isRegistered)
        XCTAssertTrue(second.isRegistered)
        XCTAssertEqual(first.validate(secondKey), .available)
        XCTAssertEqual(first.validate(firstKey), .conflict)
        XCTAssertEqual(second.validate(firstKey), .available)
        XCTAssertEqual(second.validate(secondKey), .conflict)
    }

    func testFailedBatchShortcutUpdateRestoresEveryPreviousRegistration() throws {
        let firstKey = candidate(keyCode: 0)
        let secondKey = candidate(keyCode: 1)
        let blockedKey = candidate(keyCode: 2)
        try requireAvailable([firstKey, secondKey, blockedKey])
        let first = ScreenshotShortcutManager(binding: firstKey, hotKeyID: 21001) {}
        let second = ScreenshotShortcutManager(binding: secondKey, hotKeyID: 21002) {}
        let blocker = ScreenshotShortcutManager(binding: blockedKey, hotKeyID: 21003) {}
        defer { withExtendedLifetime(blocker) {} }

        XCTAssertFalse(ScreenshotShortcutManager.updateTogether([(first, secondKey), (second, blockedKey)]))
        XCTAssertTrue(first.isRegistered)
        XCTAssertTrue(second.isRegistered)
        XCTAssertTrue(blocker.isRegistered)
        XCTAssertEqual(first.validate(firstKey), .available)
        XCTAssertEqual(second.validate(secondKey), .available)
        XCTAssertEqual(first.validate(secondKey), .conflict)
        XCTAssertEqual(second.validate(firstKey), .conflict)
    }

    private func candidate(keyCode: UInt16) -> ScreenshotShortcut {
        ScreenshotShortcut(keyCode: keyCode, modifiers: NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue)
    }

    private func requireAvailable(_ shortcuts: [ScreenshotShortcut]) throws {
        for (index, shortcut) in shortcuts.enumerated() {
            try XCTSkipUnless(
                ScreenshotShortcutManager.availability(of: shortcut, probeID: UInt32(22000 + index)) == .available,
                "A test shortcut is already used by another application"
            )
        }
    }
}
