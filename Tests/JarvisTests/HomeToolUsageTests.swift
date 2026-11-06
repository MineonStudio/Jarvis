@testable import Jarvis
import XCTest

@MainActor
final class HomeToolUsageTests: XCTestCase {
    func testRepeatedEntryClicksEachCountOnceEvenAtTheSameTime() throws {
        let name = "HomeToolUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HomeToolUsageStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 100)
        for _ in 0 ..< 6 {
            store.recordOpen(.screenshot, at: date)
        }
        XCTAssertEqual(store.count(for: .screenshot), 6)
        XCTAssertEqual(store.count(for: .screenRecording), 0)
    }

    func testRanksEightToolsByActualOpensAndPersistsAcrossLaunches() throws {
        let name = "HomeToolUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HomeToolUsageStore(defaults: defaults)
        XCTAssertEqual(store.rankedTools.count, 8)
        XCTAssertEqual(Set(store.rankedTools), Set(SkillID.allCases))
        XCTAssertTrue(store.recentTools.isEmpty)
        XCTAssertTrue(store.rankedTools.allSatisfy { store.count(for: $0) == 0 })

        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        store.recordOpen(.wallpaper, at: first)
        store.recordOpen(.resume, at: first)
        store.recordOpen(.wallpaper, at: first)
        store.recordOpen(.resume, at: second)
        store.recordOpen(.wallpaper, at: first)
        XCTAssertEqual(Array(store.rankedTools.prefix(2)), [.wallpaper, .resume])
        XCTAssertEqual(store.recentTools, [.resume, .wallpaper])

        let reloaded = HomeToolUsageStore(defaults: defaults)
        XCTAssertEqual(reloaded.count(for: .wallpaper), 3)
        XCTAssertEqual(reloaded.lastOpened(.resume), second)
        XCTAssertEqual(reloaded.rankedTools, store.rankedTools)
        XCTAssertEqual(reloaded.recentTools, store.recentTools)
    }

    func testTiesRemainStableAndCorruptStorageStartsEmpty() throws {
        let name = "HomeToolUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid".utf8), forKey: "home.tool-usage.v1")
        let store = HomeToolUsageStore(defaults: defaults)
        XCTAssertEqual(store.rankedTools, HomeToolUsageStore.tools)
        let date = Date(timeIntervalSince1970: 100)
        store.recordOpen(.resume, at: date)
        store.recordOpen(.screenshot, at: date)
        XCTAssertEqual(Array(store.rankedTools.prefix(2)), [.screenshot, .resume])
        XCTAssertEqual(store.recentTools, [.resume, .screenshot])
    }
}
