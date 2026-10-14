import Foundation
@testable import LANTransfer
import XCTest

final class HTTPServerTests: XCTestCase {
    private struct Harness {
        let server: HTTPServer
        let root: URL
        let shared: URL
        let received: URL
        let base: URL
        let cookie: String
    }

    private func makeHarness() throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("shared")
        let received = root.appendingPathComponent("received")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        let server = HTTPServer(ip: "127.0.0.1", token: "test-secret", sharedDirectory: shared, receivedDirectory: received, maxBytes: 5 * 1024 * 1024)
        let ready = expectation(description: "listener ready")
        var port: UInt16 = 0
        server.onReady = { value in port = value; ready.fulfill() }
        server.onFailure = { message in XCTFail(message); ready.fulfill() }
        server.start()
        wait(for: [ready], timeout: 5)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/"))
        let entry = try request("?t=test-secret", base: base)
        let cookie = try XCTUnwrap(entry.0.value(forHTTPHeaderField: "Set-Cookie")?.components(separatedBy: ";").first)
        return Harness(server: server, root: root, shared: shared, received: received, base: base, cookie: cookie)
    }

    private func request(
        _ path: String, base: URL, method: String = "GET", body: Data? = nil,
        cookie: String? = nil, range: String? = nil
    ) throws -> (HTTPURLResponse, Data) {
        var input = try URLRequest(url: XCTUnwrap(URL(string: path, relativeTo: base)?.absoluteURL))
        input.httpMethod = method
        input.httpBody = body
        if let cookie { input.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let range { input.setValue(range, forHTTPHeaderField: "Range") }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        let done = expectation(description: "\(method) \(path)")
        var output: (HTTPURLResponse, Data)?
        var requestError: Error?
        session.dataTask(with: input) { data, response, error in
            requestError = error
            if let response = response as? HTTPURLResponse { output = (response, data ?? Data()) }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        session.invalidateAndCancel()
        if let requestError { throw requestError }
        return try XCTUnwrap(output)
    }

    private func offer(_ server: HTTPServer, name: String) -> Bool {
        let done = expectation(description: "Mac offer")
        var result = false
        Task { result = await server.offerDownload(name: name); done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    private func status(_ id: UUID, in harness: Harness) throws -> [String: Any] {
        let response = try request("api/transfer?id=\(id.uuidString)", base: harness.base, cookie: harness.cookie)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
    }

    func testMacOfferRequiresTaskAndCompletesAfterRanges() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        let data = Data("hello-world".utf8)
        try data.write(to: harness.shared.appendingPathComponent("small.txt"))

        XCTAssertEqual(try request("api/offer", base: harness.base, cookie: harness.cookie).0.statusCode, 204)
        XCTAssertEqual(try request("api/files", base: harness.base, cookie: harness.cookie).0.statusCode, 404)
        XCTAssertEqual(try request("api/file?name=small.txt", base: harness.base, cookie: harness.cookie).0.statusCode, 400)
        XCTAssertTrue(offer(harness.server, name: "small.txt"))
        XCTAssertFalse(offer(harness.server, name: "small.txt"))

        let offered = try request("api/offer", base: harness.base, cookie: harness.cookie)
        let details = try XCTUnwrap(JSONSerialization.jsonObject(with: offered.1) as? [String: Any])
        let id = try XCTUnwrap(UUID(uuidString: XCTUnwrap(details["id"] as? String)))
        XCTAssertEqual(details["name"] as? String, "small.txt")
        XCTAssertEqual(details["size"] as? Int, data.count)
        XCTAssertEqual(details["displaySize"] as? String, ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
        XCTAssertEqual(try request("api/offer-upload?name=other.txt&size=1", base: harness.base, method: "POST", cookie: harness.cookie).0.statusCode, 409)

        let first = try request("api/file?id=\(id.uuidString)&t=test-secret", base: harness.base, range: "bytes=0-5")
        XCTAssertEqual(first.0.statusCode, 206)
        XCTAssertEqual(first.1, Data("hello-".utf8))
        XCTAssertEqual(try status(id, in: harness)["status"] as? String, TransferStatus.pending.rawValue)
        let second = try request("api/file?id=\(id.uuidString)&t=test-secret", base: harness.base, range: "bytes=6-10")
        XCTAssertEqual(second.0.statusCode, 206)
        XCTAssertEqual(second.1, Data("world".utf8))
        XCTAssertEqual(try status(id, in: harness)["status"] as? String, TransferStatus.completed.rawValue)
        XCTAssertEqual(try request("api/offer", base: harness.base, cookie: harness.cookie).0.statusCode, 204)
    }

    func testPhoneUploadWaitsForMacAcceptanceAndSavesReceivedFile() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        let data = Data("hello-world".utf8)
        let offered = try request("api/offer-upload?name=photo.txt&size=11", base: harness.base, method: "POST", cookie: harness.cookie)
        XCTAssertEqual(offered.0.statusCode, 201)
        let details = try XCTUnwrap(JSONSerialization.jsonObject(with: offered.1) as? [String: String])
        let id = try XCTUnwrap(UUID(uuidString: XCTUnwrap(details["id"])))
        XCTAssertEqual(try status(id, in: harness)["status"] as? String, TransferStatus.pending.rawValue)
        XCTAssertEqual(try request("api/upload?name=photo.txt&id=\(id.uuidString)", base: harness.base, method: "PUT", body: data, cookie: harness.cookie).0.statusCode, 409)

        let accepted = expectation(description: "Mac accepted")
        harness.server.onTransfer = { transfer in
            if transfer.id == id, transfer.status == .accepted { accepted.fulfill() }
        }
        harness.server.acceptUpload(id)
        wait(for: [accepted], timeout: 5)
        let uploaded = try request("api/upload?name=photo.txt&id=\(id.uuidString)", base: harness.base, method: "PUT", body: data, cookie: harness.cookie)
        XCTAssertEqual(uploaded.0.statusCode, 201)
        XCTAssertEqual(try Data(contentsOf: harness.received.appendingPathComponent("photo.txt")), data)
        XCTAssertEqual(try status(id, in: harness)["status"] as? String, TransferStatus.completed.rawValue)
        XCTAssertEqual(try request("api/files", base: harness.base, cookie: harness.cookie).0.statusCode, 404)
    }

    func testMissingResourceFailsOfferAndCancellationFreesSingleTaskSlot() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.shared.appendingPathComponent("gone.bin")
        try Data("file".utf8).write(to: url)
        XCTAssertTrue(offer(harness.server, name: "gone.bin"))
        let offered = try request("api/offer", base: harness.base, cookie: harness.cookie)
        let details = try XCTUnwrap(JSONSerialization.jsonObject(with: offered.1) as? [String: Any])
        let id = try XCTUnwrap(UUID(uuidString: XCTUnwrap(details["id"] as? String)))
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try request("api/file?id=\(id.uuidString)", base: harness.base, cookie: harness.cookie).0.statusCode, 410)
        XCTAssertEqual(try status(id, in: harness)["status"] as? String, TransferStatus.failed.rawValue)
        XCTAssertTrue(offer(harness.server, name: "gone.bin") == false)

        let upload = try request("api/offer-upload?name=next.txt&size=4", base: harness.base, method: "POST", cookie: harness.cookie)
        XCTAssertEqual(upload.0.statusCode, 201)
        let uploadDetails = try XCTUnwrap(JSONSerialization.jsonObject(with: upload.1) as? [String: String])
        let uploadID = try XCTUnwrap(UUID(uuidString: XCTUnwrap(uploadDetails["id"])))
        XCTAssertEqual(try request("api/cancel?id=\(uploadID.uuidString)", base: harness.base, method: "POST", cookie: harness.cookie).0.statusCode, 200)
        XCTAssertEqual(try status(uploadID, in: harness)["status"] as? String, TransferStatus.cancelled.rawValue)
        XCTAssertEqual(try request("api/upload?name=next.txt&id=\(uploadID.uuidString)", base: harness.base, method: "PUT", body: Data("test".utf8), cookie: harness.cookie).0.statusCode, 409)
    }

    func testInterruptedPrefixIsRetainedWhenDownloadResumes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("file.bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        let total: Int64 = 75_420_323
        let prefix: Int64 = 4 * 1024 * 1024
        try file.truncate(atOffset: UInt64(total))
        try file.close()
        let server = HTTPServer(ip: "127.0.0.1", token: "test", sharedDirectory: root, receivedDirectory: root, maxBytes: total)
        XCTAssertTrue(offer(server, name: "file.bin"))
        let task = try XCTUnwrap(server.currentDownloadOffer())
        let first = UUID(), second = UUID()
        XCTAssertTrue(server.beginDownload(id: task.id, connectionID: first, name: task.name, total: total, start: 0))
        server.updateDownload(id: task.id, connectionID: first, start: 0, sent: prefix, bytesPerSecond: 1)
        server.abandonDownload(id: task.id, connectionID: first, start: 0, sent: prefix)
        XCTAssertEqual(server.transferRecord(task.id)?.status, .pending)
        XCTAssertTrue(server.beginDownload(id: task.id, connectionID: second, name: task.name, total: total, start: prefix))
        server.updateDownload(id: task.id, connectionID: second, start: prefix, sent: total - prefix, bytesPerSecond: 1)
        server.finishDownload(id: task.id, connectionID: second, start: prefix, length: total - prefix)
        XCTAssertEqual(server.transferRecord(task.id)?.status, .completed)
        XCTAssertEqual(server.transferRecord(task.id)?.done, total)
    }
}
