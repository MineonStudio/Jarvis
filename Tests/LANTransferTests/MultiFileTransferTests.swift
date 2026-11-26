import Foundation
@testable import LANTransfer
import XCTest

final class MultiFileTransferTests: XCTestCase {
    func testDownloadKeepsAUsableFileName() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        try Data("hi".utf8).write(to: harness.shared.appendingPathComponent("notes.txt"))
        try Data("hi".utf8).write(to: harness.shared.appendingPathComponent("说明.txt"))
        let notes = try XCTUnwrap(offer(harness.server, name: "notes.txt", batch: UUID(), index: 1, count: 1))
        let saved = try request("api/file?id=\(notes.uuidString)&t=1a2b", base: harness.base, cookie: harness.cookie)
        let savedDisposition = try XCTUnwrap(saved.0.value(forHTTPHeaderField: "Content-Disposition"))
        XCTAssertTrue(savedDisposition.contains("filename=\"notes.txt\""))
        XCTAssertFalse(savedDisposition.contains("filename=\"download\""))

        let named = try XCTUnwrap(offer(harness.server, name: "说明.txt", batch: UUID(), index: 1, count: 1))
        let unicode = try request("api/file?id=\(named.uuidString)&t=1a2b", base: harness.base, cookie: harness.cookie)
        let unicodeDisposition = try XCTUnwrap(unicode.0.value(forHTTPHeaderField: "Content-Disposition"))
        XCTAssertTrue(unicodeDisposition.contains("filename=\"file.txt\""))
        XCTAssertTrue(unicodeDisposition.contains("filename*=UTF-8''"))
        XCTAssertFalse(unicodeDisposition.contains("filename=\"download\""))
    }

    func testOutboundQueueOffersNamesInSelectionOrder() {
        var queue = OutboundFileQueue(deviceIP: "10.0.0.8", names: ["a.txt", "b.txt"])
        let first = queue.takeNext()
        let second = queue.takeNext()
        XCTAssertEqual(first?.name, "a.txt")
        XCTAssertEqual(first?.index, 1)
        XCTAssertEqual(second?.name, "b.txt")
        XCTAssertEqual(second?.index, 2)
        XCTAssertEqual(queue.total, 2)
        XCTAssertEqual(queue.fileNames, ["a.txt", "b.txt"])
        XCTAssertNil(queue.takeNext())
        XCTAssertEqual(TransferBatchLimit.maximumCount, 50)
    }

    func testIncomingBatchPromptDescribesTheWholeTransfer() {
        var task = Transfer(id: UUID(), name: "photo.jpg", direction: .upload, total: 12, batchID: UUID(), batchIndex: 1, batchCount: 3)
        task.status = .pending
        XCTAssertEqual(task.batchPosition, "1/3")
        XCTAssertEqual(task.incomingPromptTitle, "接收 3 个文件")
        XCTAssertEqual(task.incomingPromptConfirm, "全部接收")
        XCTAssertTrue(task.incomingPromptMessage.contains("1/3 · photo.jpg"))
        task.batchFileNames = ["photo.jpg", "notes.txt", "clip.mp4"]
        XCTAssertTrue(task.incomingPromptMessage.contains("photo.jpg、notes.txt、clip.mp4"))
        XCTAssertTrue(task.incomingPromptMessage.contains("确认后会按顺序接收。"))
        var single = Transfer(id: UUID(), name: "note.txt", direction: .upload, total: 4)
        single.status = .pending
        XCTAssertNil(single.batchPosition)
        XCTAssertEqual(single.incomingPromptTitle, "接收文件")
        XCTAssertEqual(single.incomingPromptConfirm, "下载")
    }

    func testWebPageCanSelectAndReceiveMultipleFiles() {
        XCTAssertTrue(WebPage.html.contains("<input id=\"picker\" type=\"file\" multiple>"))
        XCTAssertTrue(WebPage.html.contains("选择文件，可多选"))
        XCTAssertTrue(WebPage.html.contains("acceptedDownloadBatch"))
        XCTAssertTrue(WebPage.html.contains("全部接收"))
        XCTAssertTrue(WebPage.html.contains("id=\"receivedFiles\""))
        XCTAssertTrue(WebPage.html.contains("getRandomValues"))
        XCTAssertTrue(WebPage.html.contains("function openStoredFile"))
        XCTAssertTrue(WebPage.html.contains("link.download"))
        XCTAssertTrue(WebPage.html.contains("id=\"openDownload\""))
        XCTAssertTrue(WebPage.html.contains("打开"))
        XCTAssertTrue(WebPage.html.contains("预览"))
        XCTAssertTrue(WebPage.html.contains("mountImagePreview"))
        XCTAssertTrue(WebPage.html.contains("window.open"))
        XCTAssertTrue(WebPage.html.contains("bytes=0-4095"))
        XCTAssertTrue(WebPage.html.contains("function pullDownload"))
        XCTAssertTrue(WebPage.html.contains("browserStarted"))
        XCTAssertTrue(WebPage.html.contains("userGesture"))
        XCTAssertTrue(WebPage.html.contains("type==='application/json'"))
        XCTAssertFalse(WebPage.html.contains("randomUUID"))
    }

    func testDownloadBatchPublishesPositionAndKeepsOneActiveFile() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        try Data("one".utf8).write(to: harness.shared.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: harness.shared.appendingPathComponent("two.txt"))
        let batch = UUID()
        let first = try XCTUnwrap(offer(harness.server, name: "one.txt", batch: batch, index: 1, count: 2))
        XCTAssertNil(offer(harness.server, name: "two.txt", batch: batch, index: 2, count: 2))

        let offered = try request("api/offer", base: harness.base, cookie: harness.cookie)
        let details = try XCTUnwrap(JSONSerialization.jsonObject(with: offered.1) as? [String: Any])
        XCTAssertEqual(details["batchID"] as? String, batch.uuidString)
        XCTAssertEqual(details["batchIndex"] as? Int, 1)
        XCTAssertEqual(details["batchCount"] as? Int, 2)
        XCTAssertEqual(try request("api/file?id=\(first.uuidString)&t=1a2b", base: harness.base, cookie: harness.cookie).0.statusCode, 200)
        XCTAssertEqual(try status(first, in: harness)["status"] as? String, TransferStatus.completed.rawValue)

        let second = try XCTUnwrap(offer(harness.server, name: "two.txt", batch: batch, index: 2, count: 2))
        let next = try request("api/offer", base: harness.base, cookie: harness.cookie)
        let nextDetails = try XCTUnwrap(JSONSerialization.jsonObject(with: next.1) as? [String: Any])
        XCTAssertEqual(nextDetails["name"] as? String, "two.txt")
        XCTAssertEqual(nextDetails["batchIndex"] as? Int, 2)
        XCTAssertEqual(try request("api/file?id=\(second.uuidString)&t=1a2b", base: harness.base, cookie: harness.cookie).0.statusCode, 200)
    }

    func testAcceptedUploadBatchReceivesTheNextFileWithoutAnotherPrompt() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        let batch = UUID()
        let first = try offerUpload(.init(name: "a.txt", batch: batch, index: 1, count: 2), in: harness)
        XCTAssertEqual(try status(first, in: harness)["status"] as? String, TransferStatus.pending.rawValue)
        let blocked = try request(uploadPath(name: "b.txt", batch: batch, index: 2, count: 2), base: harness.base, method: "POST", cookie: harness.cookie)
        XCTAssertEqual(blocked.0.statusCode, 409)

        accept(first, on: harness.server)
        XCTAssertEqual(try request("api/upload?name=a.txt&id=\(first.uuidString)", base: harness.base, method: "PUT", body: Data("a".utf8), cookie: harness.cookie).0.statusCode, 201)
        let second = try offerUpload(.init(name: "b.txt", batch: batch, index: 2, count: 2), in: harness)
        XCTAssertEqual(try status(second, in: harness)["status"] as? String, TransferStatus.accepted.rawValue)
        XCTAssertEqual(try request("api/upload?name=b.txt&id=\(second.uuidString)", base: harness.base, method: "PUT", body: Data("b".utf8), cookie: harness.cookie).0.statusCode, 201)
        XCTAssertEqual(try Data(contentsOf: harness.received.appendingPathComponent("a.txt")), Data("a".utf8))
        XCTAssertEqual(try Data(contentsOf: harness.received.appendingPathComponent("b.txt")), Data("b".utf8))
    }

    func testUploadBatchRejectsGapsOverLimitAndCancelledContinuation() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        let batch = UUID()
        XCTAssertEqual(try request(uploadPath(name: "late.txt", batch: batch, index: 2, count: 2), base: harness.base, method: "POST", cookie: harness.cookie).0.statusCode, 409)
        XCTAssertEqual(try request(uploadPath(name: "too-many.txt", batch: UUID(), index: 1, count: 51), base: harness.base, method: "POST", cookie: harness.cookie).0.statusCode, 400)

        let first = try offerUpload(.init(name: "a.txt", batch: batch, index: 1, count: 3), in: harness)
        accept(first, on: harness.server)
        XCTAssertEqual(try request("api/upload?name=a.txt&id=\(first.uuidString)", base: harness.base, method: "PUT", body: Data("a".utf8), cookie: harness.cookie).0.statusCode, 201)
        let skipped = try request(uploadPath(name: "c.txt", batch: batch, index: 3, count: 3), base: harness.base, method: "POST", cookie: harness.cookie)
        XCTAssertEqual(skipped.0.statusCode, 409)
        XCTAssertEqual(String(data: skipped.1, encoding: .utf8), "多文件任务不连续")
        let second = try offerUpload(.init(name: "b.txt", batch: batch, index: 2, count: 3), in: harness)
        XCTAssertEqual(try status(second, in: harness)["status"] as? String, TransferStatus.accepted.rawValue)
        XCTAssertEqual(try request("api/cancel?id=\(second.uuidString)", base: harness.base, method: "POST", cookie: harness.cookie).0.statusCode, 200)
        XCTAssertEqual(try request(uploadPath(name: "c.txt", batch: batch, index: 3, count: 3), base: harness.base, method: "POST", cookie: harness.cookie).0.statusCode, 409)
    }

    func testUploadOfferStoresBatchFileNames() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        let batch = UUID()
        let names = ["photo.jpg", "notes.txt"]
        let json = try String(data: JSONSerialization.data(withJSONObject: names), encoding: .utf8)
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "name", value: "photo.jpg"),
            URLQueryItem(name: "size", value: "1"),
            URLQueryItem(name: "batch", value: batch.uuidString),
            URLQueryItem(name: "index", value: "1"),
            URLQueryItem(name: "count", value: "2"),
            URLQueryItem(name: "names", value: json)
        ]
        let path = try "api/offer-upload?\(XCTUnwrap(components.percentEncodedQuery))"
        var stored: [String]?
        harness.server.onTransfer = { transfer in
            if stored == nil {
                stored = transfer.batchFileNames
            }
        }
        defer { harness.server.onTransfer = nil }
        let response = try request(path, base: harness.base, method: "POST", cookie: harness.cookie)
        XCTAssertEqual(response.0.statusCode, 201, String(data: response.1, encoding: .utf8) ?? "")
        XCTAssertEqual(stored, names)
    }

    func testDownloadOfferPublishesKnownBatchNames() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        try Data("a".utf8).write(to: harness.shared.appendingPathComponent("one.txt"))
        try Data("b".utf8).write(to: harness.shared.appendingPathComponent("two.txt"))
        let batch = UUID()
        let names = ["one.txt", "two.txt"]
        let done = expectation(description: "named download offer")
        var result = DownloadOfferResult.unavailable
        Task {
            result = await harness.server.prepareDownloadOffer(
                name: "one.txt",
                to: "127.0.0.1",
                batch: DownloadBatch(id: batch, index: 1, count: 2),
                names: names
            )
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        guard case .started = result else {
            XCTFail("expected the named download to start")
            return
        }
        let offered = try request("api/offer", base: harness.base, cookie: harness.cookie)
        let details = try XCTUnwrap(JSONSerialization.jsonObject(with: offered.1) as? [String: Any])
        XCTAssertEqual(details["names"] as? [String], names)
    }

    func testPrepareDownloadOfferDistinguishesBusyFromMissing() throws {
        let harness = try makeHarness()
        defer { harness.server.stop(); try? FileManager.default.removeItem(at: harness.root) }
        XCTAssertEqual(prepare(harness.server, name: "missing.txt"), .unavailable)
        try Data("one".utf8).write(to: harness.shared.appendingPathComponent("one.txt"))
        _ = try offerUpload(.init(name: "a.txt", batch: UUID(), index: 1, count: 2), in: harness)
        XCTAssertEqual(prepare(harness.server, name: "one.txt"), .busy)
    }

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
        let server = HTTPServer(ip: "127.0.0.1", token: "1a2b", sharedDirectory: shared, receivedDirectory: received, maxBytes: 5 * 1024 * 1024)
        let ready = expectation(description: "listener ready")
        var port: UInt16 = 0
        server.onReady = { value in port = value; ready.fulfill() }
        server.onFailure = { message in XCTFail(message); ready.fulfill() }
        server.start()
        wait(for: [ready], timeout: 5)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/"))
        let entry = try request("?t=1a2b", base: base)
        let cookie = try XCTUnwrap(entry.0.value(forHTTPHeaderField: "Set-Cookie")?.components(separatedBy: ";").first)
        return Harness(server: server, root: root, shared: shared, received: received, base: base, cookie: cookie)
    }

    private func request(
        _ path: String, base: URL, method: String = "GET", body: Data? = nil, cookie: String? = nil
    ) throws -> (HTTPURLResponse, Data) {
        var input = try URLRequest(url: XCTUnwrap(URL(string: path, relativeTo: base)?.absoluteURL))
        input.httpMethod = method
        input.httpBody = body
        if let cookie {
            input.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        let done = expectation(description: "\(method) \(path)")
        var output: (HTTPURLResponse, Data)?
        var requestError: Error?
        session.dataTask(with: input) { data, response, error in
            requestError = error
            if let response = response as? HTTPURLResponse {
                output = (response, data ?? Data())
            }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        session.invalidateAndCancel()
        if let requestError {
            throw requestError
        }
        return try XCTUnwrap(output)
    }

    private func prepare(_ server: HTTPServer, name: String) -> DownloadOfferResult {
        let done = expectation(description: "prepare \(name)")
        var result = DownloadOfferResult.unavailable
        Task {
            result = await server.prepareDownloadOffer(name: name, to: "127.0.0.1", batch: nil)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func offer(_ server: HTTPServer, name: String, batch: UUID, index: Int, count: Int) -> UUID? {
        let done = expectation(description: "batch offer \(name)")
        var result: UUID?
        Task {
            result = await server.offerDownload(
                name: name,
                to: "127.0.0.1",
                batch: DownloadBatch(id: batch, index: index, count: count)
            )
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func uploadPath(name: String, batch: UUID, index: Int, count: Int) -> String {
        "api/offer-upload?name=\(name)&size=1&batch=\(batch.uuidString)&index=\(index)&count=\(count)"
    }

    private struct BatchUpload {
        var name: String
        var size: Int = 1
        var batch: UUID
        var index: Int
        var count: Int
    }

    private func offerUpload(_ upload: BatchUpload, in harness: Harness) throws -> UUID {
        let path = "api/offer-upload?name=\(upload.name)&size=\(upload.size)&batch=\(upload.batch.uuidString)&index=\(upload.index)&count=\(upload.count)"
        let response = try request(path, base: harness.base, method: "POST", cookie: harness.cookie)
        XCTAssertEqual(response.0.statusCode, 201, String(data: response.1, encoding: .utf8) ?? "")
        let details = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: String])
        return try XCTUnwrap(UUID(uuidString: XCTUnwrap(details["id"])))
    }

    private func accept(_ id: UUID, on server: HTTPServer) {
        let accepted = expectation(description: "accepted")
        server.onTransfer = { transfer in
            if transfer.id == id, transfer.status == .accepted {
                accepted.fulfill()
            }
        }
        server.acceptUpload(id)
        wait(for: [accepted], timeout: 5)
    }

    private func status(_ id: UUID, in harness: Harness) throws -> [String: Any] {
        let response = try request("api/transfer?id=\(id.uuidString)", base: harness.base, cookie: harness.cookie)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
    }
}
