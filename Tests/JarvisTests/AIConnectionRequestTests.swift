@testable import Jarvis
import XCTest

final class AIConnectionRequestTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RecordingURLProtocol.capturedBody = nil
    }

    override func tearDown() {
        RecordingURLProtocol.capturedBody = nil
        super.tearDown()
    }

    func testConnectionTestRequestPromptMentionsJSONForJSONObjectMode() async throws {
        URLProtocol.registerClass(RecordingURLProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }

        let client = OpenAICompatibleAPIClient()
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key"
        )
        try await client.testConnection(configuration: configuration)

        let body = try XCTUnwrap(RecordingURLProtocol.capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let contents = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        XCTAssertTrue(
            contents.lowercased().contains("json"),
            "json_object 模式的 user prompt 必须包含 'json'，不能只依赖 response_format"
        )
        let responseFormat = try XCTUnwrap(object["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_object")
    }

    func testCompletionRequestDoesNotSetAnApplicationOutputBudget() async throws {
        URLProtocol.registerClass(RecordingURLProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }

        let client = OpenAICompatibleAPIClient()
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key"
        )
        _ = try await client.complete(
            systemPrompt: "Return JSON.",
            userPrompt: "Generate as much content as the task requires.",
            configuration: configuration,
            options: .meetingSummary
        )

        let body = try XCTUnwrap(RecordingURLProtocol.capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["max_tokens"])
        XCTAssertNil(object["max_completion_tokens"])
        XCTAssertNil(object["thinking"])
    }

    func testMahjongDecisionDisablesDeepSeekThinking() {
        let body = OpenAICompatibleAPIClient.completionBody(
            systemPrompt: "只输出牌名",
            userPrompt: "从合法牌里选一张",
            configuration: AIAPIConfiguration(
                endpoint: "https://api.deepseek.com/chat/completions",
                model: "deepseek-flash",
                apiKey: "test-key",
                providerID: AIAPIProvider.deepSeek.rawValue
            ),
            options: .mahjongDecision
        )

        let thinking = body["thinking"] as? [String: String]
        XCTAssertEqual(thinking?["type"], "disabled")
        XCTAssertEqual(body["max_tokens"] as? Int, 32)
        XCTAssertEqual(body["temperature"] as? Double, 0)
    }

    func testMahjongDecisionDoesNotSendThinkingToOtherProviders() {
        let body = OpenAICompatibleAPIClient.completionBody(
            systemPrompt: "只输出牌名",
            userPrompt: "从合法牌里选一张",
            configuration: AIAPIConfiguration(
                endpoint: "https://api.openai.com/v1/chat/completions",
                model: "gpt-4o-mini",
                apiKey: "test-key",
                providerID: AIAPIProvider.openAI.rawValue
            ),
            options: .mahjongDecision
        )

        XCTAssertNil(body["thinking"])
        XCTAssertEqual(body["max_tokens"] as? Int, 32)
    }

    func testOtherDeepSeekTasksLeaveThinkingAtTheProviderDefault() {
        let body = OpenAICompatibleAPIClient.completionBody(
            systemPrompt: "Return JSON.",
            userPrompt: "Summarize the meeting.",
            configuration: AIAPIConfiguration(
                endpoint: "https://api.deepseek.com/chat/completions",
                model: "deepseek-flash",
                apiKey: "test-key",
                providerID: AIAPIProvider.deepSeek.rawValue
            ),
            options: .meetingSummary
        )

        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["max_tokens"])
    }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capturedBody: Data?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let body = request.httpBody {
            Self.capturedBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: bufferSize)
                if count <= 0 {
                    break
                }
                data.append(buffer, count: count)
            }
            Self.capturedBody = data
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let envelope = #"{"choices":[{"message":{"role":"assistant","content":"{\"ok\":true}"}}]}"#
        client?.urlProtocol(self, didLoad: Data(envelope.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
