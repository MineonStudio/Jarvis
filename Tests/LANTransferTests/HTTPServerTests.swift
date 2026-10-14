import Foundation
@testable import LANTransfer
import XCTest

final class HTTPServerTests: XCTestCase {
    func testUploadDownloadRangeAndAuthentication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("shared")
        let received = root.appendingPathComponent("received")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = HTTPServer(ip: "127.0.0.1", token: "test-secret", sharedDirectory: shared, receivedDirectory: received, maxBytes: 5 * 1024 * 1024)
        let ready = expectation(description: "listener ready")
        var port: UInt16 = 0
        server.onReady = { value in port = value; ready.fulfill() }
        server.onFailure = { message in XCTFail(message); ready.fulfill() }
        server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)"))
        let session = URLSession(configuration: .default)
        func request(_ path: String, method: String = "GET", body: Data? = nil, cookie: String? = nil, range: String? = nil) throws -> (HTTPURLResponse, Data) {
            var req = try URLRequest(url: XCTUnwrap(URL(string: path, relativeTo: base)?.absoluteURL))
            req.httpMethod = method; req.httpBody = body
            if let cookie {
                req.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            if let range {
                req.setValue(range, forHTTPHeaderField: "Range")
            }
            let done = expectation(description: path)
            var output: (HTTPURLResponse, Data)?
            var requestError: Error?
            session.dataTask(with: req) { data, response, error in
                requestError = error
                if let response = response as? HTTPURLResponse {
                    output = (response, data ?? Data())
                }
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 5)
            if let requestError {
                throw requestError
            }
            return try XCTUnwrap(output)
        }
        XCTAssertEqual(try request("api/files").0.statusCode, 401)
        let entry = try request("?t=test-secret")
        XCTAssertEqual(entry.0.statusCode, 200)
        let cookie = try XCTUnwrap(entry.0.value(forHTTPHeaderField: "Set-Cookie")?.components(separatedBy: ";").first)
        let data = Data("hello-world".utf8)
        XCTAssertEqual(try request("api/upload?name=test.txt", method: "PUT", body: data, cookie: cookie).0.statusCode, 201)
        XCTAssertEqual(try request("api/upload?name=test.txt", method: "PUT", body: data, cookie: cookie).0.statusCode, 201)
        XCTAssertTrue(FileManager.default.fileExists(atPath: received.appendingPathComponent("test(1).txt").path))
        try data.write(to: shared.appendingPathComponent("test.txt"))
        let files = try request("api/files", cookie: cookie)
        XCTAssertTrue(try XCTUnwrap(String(data: files.1, encoding: .utf8)?.contains("test.txt")))
        let nativeDownloadID = UUID()
        let nativeDownload = try request(
            "api/file?name=test.txt&t=test-secret&id=\(nativeDownloadID.uuidString)"
        )
        XCTAssertEqual(nativeDownload.0.statusCode, 200)
        XCTAssertEqual(nativeDownload.1, data)
        XCTAssertEqual(
            try request("api/file?name=test.txt&t=test-secret", method: "HEAD").0.statusCode,
            200
        )
        let statusResponse = try request("api/transfer?id=\(nativeDownloadID.uuidString)", cookie: cookie)
        let status = try XCTUnwrap(JSONSerialization.jsonObject(with: statusResponse.1) as? [String: Any])
        XCTAssertEqual(status["status"] as? String, TransferStatus.completed.rawValue)
        let part = try request("api/file?name=test.txt", cookie: cookie, range: "bytes=6-10")
        XCTAssertEqual(part.0.statusCode, 206)
        XCTAssertEqual(String(data: part.1, encoding: .utf8), "world")
        XCTAssertEqual(try request("api/file?name=test.txt", cookie: cookie, range: "bytes=100-").0.statusCode, 416)
        XCTAssertEqual(try request("api/upload?name=too-big", method: "PUT", body: Data(repeating: 1, count: 5 * 1024 * 1024 + 1), cookie: cookie).0.statusCode, 413)
        let large = Data(repeating: 0x5A, count: 4 * 1024 * 1024)
        XCTAssertEqual(try request("api/upload?name=large.bin", method: "PUT", body: large, cookie: cookie).0.statusCode, 201)
        XCTAssertEqual(try Data(contentsOf: received.appendingPathComponent("large.bin")), large)
        XCTAssertEqual(try request("api/file?name=..%2Fsecret", cookie: cookie).0.statusCode, 400)
        for index in 0 ..< 12 {
            let url = shared.appendingPathComponent("recent-\(index).txt")
            try data.write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(TimeInterval(index + 1))],
                ofItemAtPath: url.path
            )
        }
        let recentResponse = try request("api/files", cookie: cookie)
        let recentFiles = try XCTUnwrap(JSONSerialization.jsonObject(with: recentResponse.1) as? [[String: Any]])
        XCTAssertEqual(recentFiles.count, 10)
        XCTAssertEqual(recentFiles.first?["name"] as? String, "recent-11.txt")
        XCTAssertEqual(recentFiles.last?["name"] as? String, "recent-2.txt")
    }

    func testDownloadCanBeCancelledFromPairedDevice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("shared")
        let received = root.appendingPathComponent("received")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let largeFile = shared.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: largeFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: largeFile)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()

        let server = HTTPServer(
            ip: "127.0.0.1", token: "test-secret",
            sharedDirectory: shared, receivedDirectory: received, maxBytes: 5 * 1024 * 1024
        )
        let ready = expectation(description: "listener ready")
        var port: UInt16 = 0
        server.onReady = { value in port = value; ready.fulfill() }
        server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)"))
        let session = URLSession(configuration: .default)

        let paired = expectation(description: "paired")
        var cookie = ""
        try session.dataTask(with: XCTUnwrap(URL(string: "/?t=test-secret", relativeTo: base))) { _, response, _ in
            cookie = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Set-Cookie")?
                .components(separatedBy: ";").first ?? ""
            paired.fulfill()
        }.resume()
        wait(for: [paired], timeout: 5)
        XCTAssertFalse(cookie.isEmpty)

        let id = UUID()
        let started = expectation(description: "download started")
        server.onTransfer = { transfer in
            if transfer.id == id, transfer.status == .active, transfer.done == 0 {
                started.fulfill()
            }
        }
        let download = try session.downloadTask(
            with: XCTUnwrap(URL(string: "/api/file?name=large.bin&t=test-secret&id=\(id.uuidString)", relativeTo: base))
        )
        download.resume()
        defer { download.cancel() }
        wait(for: [started], timeout: 5)

        var cancelRequest = try URLRequest(url: XCTUnwrap(URL(string: "/api/cancel?id=\(id.uuidString)", relativeTo: base)))
        cancelRequest.httpMethod = "POST"
        cancelRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        let cancelled = expectation(description: "cancel response")
        var cancelStatus: Int?
        session.dataTask(with: cancelRequest) { _, response, _ in
            cancelStatus = (response as? HTTPURLResponse)?.statusCode
            cancelled.fulfill()
        }.resume()
        wait(for: [cancelled], timeout: 5)
        XCTAssertEqual(cancelStatus, 200)
        var statusRequest = try URLRequest(url: XCTUnwrap(URL(string: "/api/transfer?id=\(id.uuidString)", relativeTo: base)))
        statusRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        let statusRead = expectation(description: "cancelled status")
        var transferStatus: String?
        session.dataTask(with: statusRequest) { data, _, _ in
            if let data,
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                transferStatus = value["status"] as? String
            }
            statusRead.fulfill()
        }.resume()
        wait(for: [statusRead], timeout: 5)
        XCTAssertEqual(transferStatus, TransferStatus.cancelled.rawValue)
    }

    func testLANAddressCanBind() {
        guard let ip = NetworkAddress.localIPv4() else { return }
        let root = FileManager.default.temporaryDirectory
        let server = HTTPServer(ip: ip, token: "test", sharedDirectory: root, receivedDirectory: root, maxBytes: 1024)
        let ready = expectation(description: "LAN listener ready")
        server.onReady = { _ in ready.fulfill() }
        server.onFailure = { message in XCTFail(message); ready.fulfill() }
        server.start()
        wait(for: [ready], timeout: 5)
        server.stop()
    }
}
