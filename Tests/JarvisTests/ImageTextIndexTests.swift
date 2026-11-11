import Foundation
@testable import Jarvis
import XCTest

@MainActor
final class ImageTextIndexTests: XCTestCase {
    func testSHA256MatchesTheKnownVector() {
        XCTAssertEqual(
            ImageContentHash.sha256(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testJoinedTextKeepsCJKTogetherAndSpacesASCII() {
        XCTAssertEqual(ImageTextRecognition.joined(["大", "模型"]), "大模型")
        XCTAssertEqual(ImageTextRecognition.joined(["Hello", "World"]), "Hello World")
        XCTAssertEqual(ImageTextRecognition.joined(["大模型", "API"]), "大模型 API")
        XCTAssertEqual(ImageTextRecognition.joined(["  ", "模型"]), "模型")
    }

    func testUndecodableImageIsEmptySoItIsNotRetried() async {
        let text = await ImageTextRecognition.recognize(Data([0x00, 0x01, 0x02, 0x03]))
        XCTAssertEqual(text, "")
    }

    func testSamePixelsAreRecognizedOnceWhileTheFirstJobIsRunning() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hold = RecognitionHold()
        let index = ImageTextIndex(directoryURL: directory) { _ in
            await hold.enter()
            return "大模型"
        }
        let data = Data("大模型".utf8)
        let hash = ImageContentHash.sha256(data)
        let first = try write(data, named: "a.bin", in: directory)
        let second = try write(data, named: "b.bin", in: directory)

        index.enqueue(hash: nil, fileURL: first, priority: true)
        await hold.waitUntilEntered()
        index.enqueue(hash: hash, fileURL: second, priority: true)
        await hold.release()
        await index.waitUntilIdle()

        let calls = await hold.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(index.recognizedText[hash], "大模型")
    }

    func testNewImagesRunAheadOfBackfill() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hold = RecognitionHold()
        let order = TextOrder()
        let index = ImageTextIndex(directoryURL: directory) { data in
            let name = String(bytes: data, encoding: .utf8) ?? ""
            await order.append(name)
            if name == "one" {
                await hold.enter()
            }
            return name
        }
        let one = try write(Data("one".utf8), named: "one.bin", in: directory)
        let two = try write(Data("two".utf8), named: "two.bin", in: directory)
        let now = try write(Data("now".utf8), named: "now.bin", in: directory)

        index.enqueue(hash: nil, fileURL: one, priority: false)
        await hold.waitUntilEntered()
        index.enqueue(hash: nil, fileURL: two, priority: false)
        index.enqueue(hash: nil, fileURL: now, priority: true)
        await hold.release()
        await index.waitUntilIdle()

        let values = await order.snapshot()
        XCTAssertEqual(values, ["one", "now", "two"])
    }

    func testFailureIsNotStoredAndTheNextEnqueueRetries() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempts = AttemptCounter()
        let index = ImageTextIndex(directoryURL: directory) { _ in
            let attempt = await attempts.next()
            return attempt == 1 ? nil : "ok"
        }
        let data = Data("ok".utf8)
        let hash = ImageContentHash.sha256(data)
        let file = try write(data, named: "ok.bin", in: directory)

        index.enqueue(hash: hash, fileURL: file, priority: true)
        await index.waitUntilIdle()
        XCTAssertNil(index.recognizedText[hash])

        index.enqueue(hash: hash, fileURL: file, priority: true)
        await index.waitUntilIdle()
        XCTAssertEqual(index.recognizedText[hash], "ok")
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 2)
    }

    func testEmptyRecognitionIsStoredAndNotRetried() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempts = AttemptCounter()
        let index = ImageTextIndex(directoryURL: directory) { _ in
            _ = await attempts.next()
            return ""
        }
        let data = Data("blank".utf8)
        let hash = ImageContentHash.sha256(data)
        let file = try write(data, named: "blank.bin", in: directory)

        index.enqueue(hash: hash, fileURL: file, priority: true)
        await index.waitUntilIdle()
        XCTAssertEqual(index.recognizedText[hash], "")
        let attemptCount = await attempts.current()
        XCTAssertEqual(attemptCount, 1)

        let reloadedAttempts = AttemptCounter()
        let reloaded = ImageTextIndex(directoryURL: directory) { _ in
            _ = await reloadedAttempts.next()
            return "should-not-run"
        }
        reloaded.enqueue(hash: hash, fileURL: file, priority: true)
        await reloaded.waitUntilIdle()
        XCTAssertEqual(reloaded.recognizedText[hash], "")
        let reloadedCount = await reloadedAttempts.current()
        XCTAssertEqual(reloadedCount, 0)
    }

    func testPruneDropsUnreferencedTextAndQueuedWork() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hold = RecognitionHold()
        let order = TextOrder()
        let index = ImageTextIndex(directoryURL: directory) { data in
            let name = String(bytes: data, encoding: .utf8) ?? ""
            await order.append(name)
            if name == "keep" {
                await hold.enter()
            }
            return name
        }
        let keepData = Data("keep".utf8)
        let dropData = Data("drop".utf8)
        let keepHash = ImageContentHash.sha256(keepData)
        let dropHash = ImageContentHash.sha256(dropData)
        let keepFile = try write(keepData, named: "keep.bin", in: directory)
        let dropFile = try write(dropData, named: "drop.bin", in: directory)

        index.enqueue(hash: keepHash, fileURL: keepFile, priority: false)
        await hold.waitUntilEntered()
        index.enqueue(hash: dropHash, fileURL: dropFile, priority: false)
        index.prune(keeping: [keepHash], filePaths: [keepFile.path])
        await hold.release()
        await index.waitUntilIdle()

        let values = await order.snapshot()
        XCTAssertEqual(values, ["keep"])
        XCTAssertEqual(index.recognizedText[keepHash], "keep")
        XCTAssertNil(index.recognizedText[dropHash])

        let reloaded = ImageTextIndex(directoryURL: directory) { _ in "nope" }
        XCTAssertEqual(reloaded.recognizedText, [keepHash: "keep"])
    }

    func testScreenshotContentHashRoundTripsWithoutRewritingTheImage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-content-hash-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScreenshotHistoryStore(directoryURL: directory)
        let original = Data([9, 8, 7])
        let added = try XCTUnwrap(store.add(data: original, contentHash: "aaa"))

        XCTAssertEqual(store.load().first?.contentHash, "aaa")
        XCTAssertTrue(store.setContentHash(id: added.id, hash: "aaa"))
        XCTAssertEqual(store.data(for: added), original)
        XCTAssertTrue(store.setContentHash(id: added.id, hash: "bbb"))
        XCTAssertEqual(store.load().first?.contentHash, "bbb")
        XCTAssertEqual(store.data(for: added), original)

        let edited = try XCTUnwrap(store.update(added, data: Data([1]), contentHash: "ccc"))
        XCTAssertEqual(edited.contentHash, "ccc")
        XCTAssertEqual(store.data(for: added), Data([1]))

        struct LegacyItem: Codable {
            let id: UUID
            let createdAt: Date
            let updatedAt: Date
            let fileName: String
        }
        let current = try XCTUnwrap(store.load().first)
        let legacy = LegacyItem(
            id: current.id,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            fileName: current.fileName
        )
        let metadata = try JSONEncoder().encode([legacy])
        try metadata.write(to: directory.appendingPathComponent("metadata.json"))
        XCTAssertNil(ScreenshotHistoryStore(directoryURL: directory).load().first?.contentHash)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-image-text-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

private actor RecognitionHold {
    private var started = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0

    func callCount() -> Int {
        calls
    }

    func enter() async {
        calls += 1
        started = true
        let waitingToStart = startWaiters
        startWaiters.removeAll()
        for waiter in waitingToStart {
            waiter.resume()
        }
        if isReleased {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor TextOrder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private actor AttemptCounter {
    private(set) var count = 0

    func next() -> Int {
        count += 1
        return count
    }

    func current() -> Int {
        count
    }
}
