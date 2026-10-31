import AppKit
@testable import Jarvis
import XCTest

final class FunctionShortcutMigrationTests: XCTestCase {
    func testMigrationReassignsAllPrimaryKeysAndPreservesWindowLayoutSettings() throws {
        let suite = "jarvis-shortcut-migration-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let encoder = JSONEncoder()
        let custom = ScreenshotShortcut(keyCode: 15, modifiers: NSEvent.ModifierFlags.command.rawValue)
        let layoutData = try encoder.encode(custom)
        defaults.set(layoutData, forKey: "jarvis.window-layout.shortcut.halfLeft")
        try defaults.set(encoder.encode(ScreenshotShortcut(keyCode: 120, modifiers: 0)), forKey: "jarvis.clipboard.shortcut")
        try defaults.set(encoder.encode(ScreenshotShortcut(keyCode: 99, modifiers: 0)), forKey: "jarvis.meeting.shortcut")
        try defaults.set(encoder.encode(["open": custom, "stop": custom]), forKey: JarvisFunctionShortcutMigration.recordingKey)

        JarvisFunctionShortcutMigration.apply(to: defaults)

        XCTAssertEqual(try binding("jarvis.screenshot.shortcut", in: defaults), .default)
        XCTAssertEqual(try binding("jarvis.clipboard.shortcut", in: defaults), .clipboardDefault)
        XCTAssertEqual(try binding("jarvis.meeting.shortcut", in: defaults), .meetingDefault)
        let recording = try recordingBindings(in: defaults)
        XCTAssertEqual(recording["open"], .screenRecordingDefault)
        XCTAssertEqual(recording["stop"], custom)
        XCTAssertEqual(defaults.data(forKey: "jarvis.window-layout.shortcut.halfLeft"), layoutData)
    }

    func testMigrationOnlyRunsOnceAndPreservesLaterUserChoices() throws {
        let suite = "jarvis-shortcut-migration-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        JarvisFunctionShortcutMigration.apply(to: defaults)
        let custom = ScreenshotShortcut(keyCode: 15, modifiers: NSEvent.ModifierFlags.command.rawValue)
        try defaults.set(JSONEncoder().encode(custom), forKey: "jarvis.clipboard.shortcut")
        try defaults.set(JSONEncoder().encode([String: ScreenshotShortcut]()), forKey: JarvisFunctionShortcutMigration.recordingKey)

        JarvisFunctionShortcutMigration.apply(to: defaults)

        XCTAssertEqual(try binding("jarvis.clipboard.shortcut", in: defaults), custom)
        XCTAssertTrue(try recordingBindings(in: defaults).isEmpty, "Clearing a recording shortcut after migration must remain effective")
    }

    func testMigrationRemovesAnOldStopBindingThatWouldAlsoTriggerAPrimaryAction() throws {
        let suite = "jarvis-shortcut-migration-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try defaults.set(
            JSONEncoder().encode(["stop": ScreenshotShortcut.clipboardDefault]),
            forKey: JarvisFunctionShortcutMigration.recordingKey
        )
        JarvisFunctionShortcutMigration.apply(to: defaults)
        XCTAssertNil(try recordingBindings(in: defaults)["stop"])
        XCTAssertEqual(try recordingBindings(in: defaults)["open"], .screenRecordingDefault)
    }

    func testWindowLayoutRemainsAModuleButHasNoSidebarEntry() {
        XCTAssertTrue(SkillID.allCases.contains(.windowLayout))
        XCTAssertFalse(SkillID.sidebarCases.contains(.windowLayout))
        XCTAssertEqual(SkillID.sidebarCases, SkillID.allCases.filter { $0 != .windowLayout })
    }

    private func binding(_ key: String, in defaults: UserDefaults) throws -> ScreenshotShortcut {
        try JSONDecoder().decode(ScreenshotShortcut.self, from: XCTUnwrap(defaults.data(forKey: key)))
    }

    private func recordingBindings(in defaults: UserDefaults) throws -> [String: ScreenshotShortcut] {
        try JSONDecoder().decode(
            [String: ScreenshotShortcut].self,
            from: XCTUnwrap(defaults.data(forKey: JarvisFunctionShortcutMigration.recordingKey))
        )
    }
}
