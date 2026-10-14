import Foundation
@testable import LANTransfer
import XCTest

final class SharedFileImporterTests: XCTestCase {
    func testDirectoriesStayInsideJarvisApplicationSupport() {
        let production = LANTransferDirectories.root(bundleIdentifier: "com.jarvis.mac")
        let development = LANTransferDirectories.root(bundleIdentifier: "com.jarvis.mac.dev")
        XCTAssertTrue(production.path.hasSuffix("/Application Support/Jarvis/局域网传输"))
        XCTAssertTrue(development.path.hasSuffix("/Application Support/Jarvis-Dev/局域网传输"))
        XCTAssertEqual(ShareStore.maxFileBytes, 2 * 1_073_741_824)
    }

    func testImportCopiesFilesAndKeepsExistingNames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let shared = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = source.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)
        let importer = SharedFileImporter()
        let result = await importer.importFiles([file, file], into: shared, maxBytes: ShareStore.maxFileBytes)

        XCTAssertEqual(result.importedNames, ["note.txt", "note(1).txt"])
        XCTAssertTrue(result.failedNames.isEmpty)
        XCTAssertEqual(try Data(contentsOf: shared.appendingPathComponent("note.txt")), Data("hello".utf8))
        XCTAssertEqual(try Data(contentsOf: shared.appendingPathComponent("note(1).txt")), Data("hello".utf8))
    }

    func testImportRejectsOversizedAndSymbolicLinkFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let oversized = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(ShareStore.maxFileBytes + 1))
        try handle.close()
        let link = root.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: oversized)

        let result = await SharedFileImporter().importFiles(
            [oversized, link], into: shared, maxBytes: ShareStore.maxFileBytes
        )
        XCTAssertTrue(result.importedNames.isEmpty)
        XCTAssertEqual(result.failedNames.count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shared.path), [])
    }
}
