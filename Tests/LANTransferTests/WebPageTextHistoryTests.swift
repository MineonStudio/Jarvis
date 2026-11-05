import AppKit
@testable import LANTransfer
import WebKit
import XCTest

@MainActor
final class WebPageTextHistoryTests: XCTestCase {
    @MainActor
    private struct Harness {
        let server: HTTPServer
        let root: URL
        let entry: URL
        let browser: WKWebView

        func close() {
            browser.stopLoading()
            browser.loadHTMLString("", baseURL: nil)
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class Navigation: NSObject, WKNavigationDelegate {
        let ready: XCTestExpectation
        init(_ ready: XCTestExpectation) {
            self.ready = ready
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            ready.fulfill()
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            XCTFail("Page failed: \(error)"); ready.fulfill()
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            XCTFail("Page failed: \(error)"); ready.fulfill()
        }
    }

    private func load(_ entry: URL, in browser: WKWebView) async throws {
        let ready = expectation(description: "Web page loaded")
        let navigation = Navigation(ready)
        browser.navigationDelegate = navigation
        browser.load(URLRequest(url: entry))
        await fulfillment(of: [ready], timeout: 10)
        withExtendedLifetime(navigation) {}
        let title = try await browser.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(title, "文件传输")
        try await waitFor("typeof rememberTextTransfer === 'function'", in: browser)
    }

    private func makeHarness() async throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shared = root.appendingPathComponent("shared")
        let received = root.appendingPathComponent("received")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        let server = HTTPServer(
            ip: "127.0.0.1",
            token: "a1b2",
            sharedDirectory: shared,
            receivedDirectory: received,
            maxBytes: 1024 * 1024
        )
        let ready = expectation(description: "HTTP server ready")
        var port: UInt16 = 0
        server.onReady = { port = $0; ready.fulfill() }
        server.onFailure = { XCTFail($0); ready.fulfill() }
        server.start()
        await fulfillment(of: [ready], timeout: 10)
        let entry = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/?t=a1b2"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        try await load(entry, in: browser)
        return Harness(server: server, root: root, entry: entry, browser: browser)
    }

    private func waitFor(_ condition: String, in browser: WKWebView) async throws {
        for _ in 0 ..< 250 {
            if try await browser.evaluateJavaScript(condition) as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(condition)")
        throw NSError(domain: "WebPageTextHistoryTests", code: 1)
    }

    private func receive(_ text: String, count: Int, in harness: Harness) async throws {
        let offered = await harness.server.offerDownloadText(text, to: "127.0.0.1")
        XCTAssertTrue(offered)
        try await waitFor("currentOffer !== null && !offerModal.hidden", in: harness.browser)
        _ = try await harness.browser.evaluateJavaScript("document.getElementById('accept').click(); true")
        try await waitFor("textRecords.length === \(count) && !acceptingText", in: harness.browser)
    }

    func testReceivedTextsRemainSeparateCopyableAndSurviveRefresh() async throws {
        let harness = try await makeHarness()
        defer { harness.close() }
        _ = try await harness.browser.evaluateJavaScript("window.__copies=[]; copyText=async value=>{window.__copies.push(value)}; true")
        let first = "https://example.com/first"
        let second = "第二条文本 <img src=x onerror=alert(1)>"
        try await receive(first, count: 1, in: harness)
        try await receive(second, count: 2, in: harness)
        try await receive(first, count: 3, in: harness)
        let texts = try await harness.browser.evaluateJavaScript("Array.from(document.querySelectorAll('#textHistory pre'), node=>node.textContent)") as? [String]
        XCTAssertEqual(texts, [first, second, first])
        let linkCount = try await harness.browser.evaluateJavaScript("document.querySelectorAll('#textHistory a').length") as? Int
        XCTAssertEqual(linkCount, 2)
        let imageCount = try await harness.browser.evaluateJavaScript("document.querySelectorAll('#textHistory img').length") as? Int
        XCTAssertEqual(imageCount, 0)
        _ = try await harness.browser.evaluateJavaScript("document.querySelectorAll('#textHistory button')[1].click(); true")
        try await waitFor("window.__copies.length === 4", in: harness.browser)
        let copied = try await harness.browser.evaluateJavaScript("window.__copies[3]") as? String
        XCTAssertEqual(copied, second)

        try await load(harness.entry, in: harness.browser)
        let restored = try await harness.browser.evaluateJavaScript("Array.from(document.querySelectorAll('#textHistory pre'), node=>node.textContent)") as? [String]
        XCTAssertEqual(restored, [first, second, first])
    }

    func testClipboardFailureStillRetainsTextsAndAllowsTheNextTransfer() async throws {
        let harness = try await makeHarness()
        defer { harness.close() }
        _ = try await harness.browser.evaluateJavaScript("copyText=async()=>{throw Error('clipboard unavailable')}; true")
        try await receive("first", count: 1, in: harness)
        try await receive("second", count: 2, in: harness)
        let texts = try await harness.browser.evaluateJavaScript("Array.from(document.querySelectorAll('#textHistory pre'), node=>node.textContent)") as? [String]
        XCTAssertEqual(texts, ["second", "first"])
    }

    func testMultipleTextsSentFromBrowserKeepIndependentRecords() async throws {
        let harness = try await makeHarness()
        defer { harness.close() }
        harness.server.onTransfer = { [weak server = harness.server] transfer in
            if transfer.direction == .upload, transfer.status == .pending {
                server?.finishText(transfer.id, direction: .upload)
            }
        }
        for count in 1 ... 3 {
            _ = try await harness.browser.evaluateJavaScript("textInput.value='message-\(count)'; sendText(); true")
            try await waitFor("textRecords.length === \(count) && activeTextSend === null", in: harness.browser)
        }
        let texts = try await harness.browser.evaluateJavaScript("Array.from(document.querySelectorAll('#textHistory pre'), node=>node.textContent)") as? [String]
        XCTAssertEqual(texts, ["message-3", "message-2", "message-1"])
        let activeTaskHidden = try await harness.browser.evaluateJavaScript("!uploadTask.classList.contains('visible')") as? Bool
        XCTAssertEqual(activeTaskHidden, true)
    }
}
