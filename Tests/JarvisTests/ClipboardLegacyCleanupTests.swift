import Foundation
@testable import Jarvis
import XCTest

final class ClipboardLegacyCleanupTests: XCTestCase {
    func testCleanupDeletesOwnedFilesButKeepsExternalFilesAndTheCacheRoot() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanup() }
        let owned = try XCTUnwrap(fixture.store.storeData(Data("cached".utf8), fileExtension: "txt"))
        let external = try fixture.externalFile(named: "document.pdf")
        let sibling = fixture.root.appendingPathComponent("cache-copy", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let similarPrefix = sibling.appendingPathComponent("item-user-document.txt")
        try Data("user file".utf8).write(to: similarPrefix)

        fixture.store.removeLegacyFiles(atPaths: [owned, external.path, similarPrefix.path, fixture.cache.path])

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: similarPrefix.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.cache.path))
    }

    func testCleanupCannotFollowACacheDirectorySymlinkToAnExternalFile() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanup() }
        let external = try fixture.externalFile(named: "item-external.txt")
        let link = fixture.cache.appendingPathComponent("linked-directory")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.external)
        let path = link.appendingPathComponent(external.lastPathComponent).path
        let item = ClipboardItem(kind: .file, filePath: path, isStoredCopy: true)

        XCTAssertFalse(fixture.store.hasManagedReferences(for: item))
        XCTAssertTrue(fixture.store.removeManagedFiles(for: [item]))
        fixture.store.removeLegacyFiles(atPaths: [path])

        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    }

    func testMigrationCleanupRequiresTheExplicitPreviousCacheDirectory() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanup() }
        let original = try XCTUnwrap(fixture.store.storeData(Data("cached".utf8), fileExtension: "txt"))
        let external = try fixture.externalFile(named: "document.pdf")
        let item = ClipboardItem(kind: .text, text: "cached", textPath: original, isStoredCopy: true)
        let migration = try fixture.store.migrateManagedFiles(
            for: [item], to: fixture.root.appendingPathComponent("new-cache", isDirectory: true)
        )
        let migrated = try XCTUnwrap(migration.items.first?.textPath)

        fixture.store.removeLegacyFiles(atPaths: migration.legacyPaths)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        fixture.store.removeLegacyFiles(atPaths: migration.legacyPaths + [external.path], ownedBy: fixture.cache)

        XCTAssertFalse(FileManager.default.fileExists(atPath: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: migrated))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    func testRollbackCleanupKeepsTheRestoredCacheAndExternalFiles() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanup() }
        let original = try XCTUnwrap(fixture.store.storeData(Data("cached".utf8), fileExtension: "txt"))
        let external = try fixture.externalFile(named: "document.pdf")
        let item = ClipboardItem(kind: .text, text: "cached", textPath: original, isStoredCopy: true)
        let destination = fixture.root.appendingPathComponent("new-cache", isDirectory: true)
        let migration = try fixture.store.migrateManagedFiles(for: [item], to: destination)
        let migrated = try XCTUnwrap(migration.items.first?.textPath)
        let rollback = try fixture.store.migrateManagedFiles(for: migration.items, to: fixture.cache)
        let restored = try XCTUnwrap(rollback.items.first?.textPath)

        fixture.store.removeLegacyFiles(atPaths: rollback.legacyPaths + [external.path], ownedBy: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: migrated))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }
}

private struct CleanupFixture {
    let root: URL
    let cache: URL
    let external: URL
    let suite: String
    let defaults: UserDefaults
    let store: ClipboardCacheStore

    init() throws {
        suite = "jarvis-legacy-cleanup-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        cache = root.appendingPathComponent("cache", isDirectory: true)
        external = root.appendingPathComponent("documents", isDirectory: true)
        defaults.set(cache.path, forKey: "jarvis.clipboard.cache.directory")
        store = ClipboardCacheStore(defaults: defaults)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    }

    func externalFile(named name: String) throws -> URL {
        let url = external.appendingPathComponent(name)
        try Data("user document".utf8).write(to: url)
        return url
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
