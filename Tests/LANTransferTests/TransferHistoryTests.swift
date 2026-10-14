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
}
