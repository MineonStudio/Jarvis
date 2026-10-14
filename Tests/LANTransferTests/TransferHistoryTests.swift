import AppKit
import Foundation
@testable import LANTransfer
import XCTest

final class TransferHistoryTests: XCTestCase {
    @MainActor
    func testRestoresSavedResourcesAndEndsInterruptedTask() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("saved.txt")
        try Data("saved".utf8).write(to: file)
        var completed = Transfer(id: UUID(), name: "saved.txt", direction: .upload, total: 5)
        completed.done = 5
        completed.status = .completed
        completed.resourceURL = file
        var interrupted = Transfer(id: UUID(), name: "pending.txt", direction: .download, total: 10)
        interrupted.status = .pending
        try JSONEncoder().encode([completed, interrupted]).write(to: root.appendingPathComponent("transfers.json"))

        let store = ShareStore(rootDirectory: root)
        XCTAssertEqual(store.transfers.count, 2)
        XCTAssertEqual(store.transfers[0].resourceURL, file)
        XCTAssertEqual(store.transfers[0].status, .completed)
        XCTAssertEqual(store.transfers[1].status, .failed)
        XCTAssertEqual(store.transfers[1].detail, "传输已中断")
    }

    @MainActor
    func testAdoptsExistingFilesIntoMacTaskHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("共享")
        let received = root.appendingPathComponent("接收")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentFile = shared.appendingPathComponent("sent.txt")
        let receivedFile = received.appendingPathComponent("received.txt")
        try Data("sent".utf8).write(to: sentFile)
        try Data("received".utf8).write(to: receivedFile)

        let store = ShareStore(rootDirectory: root)
        XCTAssertEqual(store.transfers.count, 2)
        XCTAssertTrue(store.transfers.contains {
            $0.resourceURL?.resolvingSymlinksInPath() == sentFile.resolvingSymlinksInPath()
                && $0.direction == .download && $0.status == .completed && $0.detail == "历史文件"
        })
        XCTAssertTrue(store.transfers.contains {
            $0.resourceURL?.resolvingSymlinksInPath() == receivedFile.resolvingSymlinksInPath()
                && $0.direction == .upload && $0.status == .completed && $0.detail == "历史文件"
        })
        let persisted = try JSONDecoder().decode([Transfer].self, from: Data(contentsOf: root.appendingPathComponent("transfers.json")))
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(ShareStore(rootDirectory: root).transfers.count, 2)
    }

    @MainActor
    func testDeleteRemovesTaskAndManagedSourceFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("共享")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = shared.appendingPathComponent("photo.png")
        try Data("image".utf8).write(to: file)
        var saved = Transfer(id: UUID(), name: "photo.png", direction: .download, total: 5)
        saved.done = 5
        saved.status = .completed
        saved.resourceURL = file
        try JSONEncoder().encode([saved]).write(to: root.appendingPathComponent("transfers.json"))

        let store = ShareStore(rootDirectory: root)
        XCTAssertEqual(store.transfers.count, 1)
        store.delete(saved.id)
        XCTAssertTrue(store.transfers.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let persisted = try JSONDecoder().decode([Transfer].self, from: Data(contentsOf: root.appendingPathComponent("transfers.json")))
        XCTAssertTrue(persisted.isEmpty)
    }

    @MainActor
    func testDeleteLeavesFilesOutsideManagedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-keep.txt")
        try Data("keep".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        var saved = Transfer(id: UUID(), name: "keep.txt", direction: .upload, total: 4)
        saved.done = 4
        saved.status = .completed
        saved.resourceURL = outside
        try JSONEncoder().encode([saved]).write(to: root.appendingPathComponent("transfers.json"))

        let store = ShareStore(rootDirectory: root)
        store.delete(saved.id)
        XCTAssertTrue(store.transfers.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    @MainActor
    func testCopyResourceWritesFileURLToPasteboard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("共享")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = shared.appendingPathComponent("note.txt")
        try Data("copy-me".utf8).write(to: file)
        var saved = Transfer(id: UUID(), name: "note.txt", direction: .download, total: 7)
        saved.done = 7
        saved.status = .completed
        saved.resourceURL = file
        try JSONEncoder().encode([saved]).write(to: root.appendingPathComponent("transfers.json"))

        let store = ShareStore(rootDirectory: root)
        NSPasteboard.general.clearContents()
        XCTAssertTrue(store.copyResource(store.transfers[0]))
        let copied = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(
            copied?.first?.resolvingSymlinksInPath(),
            file.resolvingSymlinksInPath()
        )
    }

    func testTaskFilterMatchesDirectionAndFailure() {
        var sent = Transfer(id: UUID(), name: "a.txt", direction: .download, total: 1)
        sent.status = .completed
        var sending = Transfer(id: UUID(), name: "a2.txt", direction: .download, total: 1)
        sending.status = .active
        var received = Transfer(id: UUID(), name: "b.txt", direction: .upload, total: 1)
        received.status = .completed
        var failed = Transfer(id: UUID(), name: "c.txt", direction: .download, total: 1)
        failed.status = .failed
        var cancelled = Transfer(id: UUID(), name: "d.txt", direction: .upload, total: 1)
        cancelled.status = .cancelled

        XCTAssertTrue(TransferTaskFilter.all.matches(sent))
        XCTAssertTrue(TransferTaskFilter.sent.matches(sent))
        XCTAssertTrue(TransferTaskFilter.sent.matches(sending))
        XCTAssertTrue(TransferTaskFilter.sent.matches(failed))
        XCTAssertFalse(TransferTaskFilter.received.matches(sent))
        XCTAssertTrue(TransferTaskFilter.received.matches(received))
        XCTAssertTrue(TransferTaskFilter.received.matches(cancelled))
        XCTAssertEqual(TransferTaskFilter.allCases.map(\.title), ["全部", "接收", "发送"])
        XCTAssertTrue(TransferByteCount.string(from: 0).hasPrefix("0"))
        XCTAssertFalse(TransferByteCount.string(from: 0).localizedCaseInsensitiveContains("zero"))
    }
}
