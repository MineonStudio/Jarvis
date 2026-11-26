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
        let navigation: Navigation

        func close() {
            browser.stopLoading()
            browser.loadHTMLString("", baseURL: nil)
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class Navigation: NSObject, WKNavigationDelegate {
        var ready: XCTestExpectation?
        private(set) var downloadURLs: [URL] = []

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            ready?.fulfill()
            ready = nil
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            XCTFail("Page failed: \(error)"); ready?.fulfill(); ready = nil
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            XCTFail("Page failed: \(error)"); ready?.fulfill(); ready = nil
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url, url.path == "/api/file" else {
                decisionHandler(.allow)
                return
            }
            downloadURLs.append(url)
            decisionHandler(.cancel)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request).resume()
        }
    }

    private func load(_ entry: URL, in browser: WKWebView, navigation: Navigation) async throws {
        let ready = expectation(description: "Web page loaded")
        navigation.ready = ready
        browser.navigationDelegate = navigation
        browser.load(URLRequest(url: entry))
        await fulfillment(of: [ready], timeout: 10)
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
        let navigation = Navigation()
        try await load(entry, in: browser, navigation: navigation)
        return Harness(server: server, root: root, entry: entry, browser: browser, navigation: navigation)
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

        try await load(harness.entry, in: harness.browser, navigation: harness.navigation)
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

    func testOneAcceptKeepsEveryReceivedFileOpenable() async throws {
        let harness = try await makeHarness()
        defer { harness.close() }
        let shared = harness.root.appendingPathComponent("shared")
        try Data("hello".utf8).write(to: shared.appendingPathComponent("notes.txt"))
        try Data("bin".utf8).write(to: shared.appendingPathComponent("payload.bin"))
        let batch = UUID()
        let first = await harness.server.offerDownload(
            name: "notes.txt", to: "127.0.0.1", batch: DownloadBatch(id: batch, index: 1, count: 2)
        )
        XCTAssertNotNil(first)
        try await waitFor("currentOffer && document.getElementById('accept').textContent === '全部接收'", in: harness.browser)
        _ = try await harness.browser.evaluateJavaScript("window.__downloads=[]; window.__opens=[]; const nativeClick=HTMLAnchorElement.prototype.click; HTMLAnchorElement.prototype.click=function(){if(this.download){window.__downloads.push(String(this.href)); fetch(this.href,{cache:'no-store'}); return} return nativeClick.call(this)}; openStoredFile=record=>{window.__opens.push(record.name)}; document.getElementById('accept').click(); true")
        try await waitFor("receivedFiles.length === 1", in: harness.browser)
        let second = await harness.server.offerDownload(
            name: "payload.bin", to: "127.0.0.1", batch: DownloadBatch(id: batch, index: 2, count: 2)
        )
        XCTAssertNotNil(second)
        _ = try await harness.browser.evaluateJavaScript("checkOffer(); true")
        try await waitFor("receivedFiles.length === 2 && activeDownload === null", in: harness.browser)
        let names = try await harness.browser.evaluateJavaScript("Array.from(document.querySelectorAll('#receivedFiles strong'), node=>node.textContent)") as? [String]
        XCTAssertEqual(names, ["payload.bin", "notes.txt"])
        let downloads = try await harness.browser.evaluateJavaScript("window.__downloads.slice()") as? [String]
        XCTAssertEqual(downloads?.count, 2)
        XCTAssertEqual(downloads?.allSatisfy { !$0.contains("inline=1") }, true)
        try await waitFor("Array.from(document.querySelectorAll('#receivedFiles pre'), node=>node.textContent).includes('hello')", in: harness.browser)
        _ = try await harness.browser.evaluateJavaScript("document.querySelectorAll('#receivedFiles .text-actions button')[0].click(); true")
        try await waitFor("filePreview.hidden === false", in: harness.browser)
        let openedBefore = try await harness.browser.evaluateJavaScript("window.__opens.slice()") as? [String]
        XCTAssertEqual(openedBefore, [])
        let labels = try await harness.browser.evaluateJavaScript("Array.from(document.querySelectorAll('#receivedFiles .text-actions button'), node=>node.textContent)") as? [String]
        XCTAssertEqual(labels, ["预览", "打开", "预览", "打开"])
        _ = try await harness.browser.evaluateJavaScript("document.querySelectorAll('#receivedFiles .text-actions button')[1].click(); true")
        let opened = try await harness.browser.evaluateJavaScript("window.__opens.slice()") as? [String]
        XCTAssertEqual(opened, ["payload.bin"])
        let downloadsAfterOpen = try await harness.browser.evaluateJavaScript("window.__downloads.slice()") as? [String]
        XCTAssertEqual(downloadsAfterOpen?.count, 2)
        _ = try await harness.browser.evaluateJavaScript("document.querySelectorAll('#receivedFiles .text-actions button')[2].click(); true")
        try await waitFor("filePreview.hidden === false && previewFrame.hidden === false", in: harness.browser)
        let previewName = try await harness.browser.evaluateJavaScript("document.getElementById('previewName').textContent") as? String
        XCTAssertEqual(previewName, "notes.txt")
    }
}
