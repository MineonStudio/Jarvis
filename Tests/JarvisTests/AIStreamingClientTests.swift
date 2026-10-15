import Foundation
@testable import Jarvis
import XCTest

/// Exercises the real streaming client against a real socket. The stub types used elsewhere
/// skip the transport entirely, which is exactly where a silent provider, a refusal, or a
/// duplicate request has to be handled.
final class AIStreamingClientTests: XCTestCase {
    func testAProviderRefusalIsReportedInsteadOfWaitingForTheDeadline() async throws {
        let server = try StubHTTPServer(replies: [
            .init(
                status: 402,
                contentType: "application/json",
                chunks: [#"{"error":{"message":"Insufficient Balance (request_id: test)"}}"#]
            )
        ])
        let port = try server.start()
        defer { server.stop() }

        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await client().stream(
                systemPrompt: "s",
                userPrompt: "u",
                configuration: configuration(port: port),
                options: .meetingSummary,
                policy: slowPolicy(hedging: false),
                onEvent: { _ in }
            )
            XCTFail("额度不足应该直接抛错")
        } catch let error as AIAPIError {
            guard case let .server(message) = error else {
                return XCTFail("应该保留服务商的原文，实际是 \(error)")
            }
            XCTAssertTrue(message.contains("Insufficient Balance"), message)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertLessThan(elapsed, 5, "拒绝要立刻返回，而不是等看门狗把错误说成卡住")
        XCTAssertEqual(server.requestCount, 1)
    }

    func testTheDuplicateRequestWinsWhenTheFirstOneIsSlow() async throws {
        // The first request is slow to start; the duplicate, which only fires because the
        // first said nothing, answers first and is the one that counts.
        let server = try StubHTTPServer(replies: [
            .init(chunks: [sseFrame(content: "slow"), sseDone], initialDelay: 3),
            .init(chunks: [sseFrame(content: "fast"), sseDone], initialDelay: 0.05)
        ])
        let port = try server.start()
        defer { server.stop() }

        var policy = slowPolicy(hedging: true)
        policy.hedgeDelay = 0.2
        let started = ProcessInfo.processInfo.systemUptime
        let content = try await client().stream(
            systemPrompt: "s",
            userPrompt: "u",
            configuration: configuration(port: port),
            options: .meetingSummary,
            policy: policy,
            onEvent: { _ in }
        )

        XCTAssertEqual(content, "fast", "两份回答只该用先到的那份")
        XCTAssertEqual(server.requestCount, 2)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2, "不该等慢的那份")
    }

    func testAStreamThatGoesQuietFailsOnTheIdleAllowance() async throws {
        let server = try StubHTTPServer(replies: [
            .init(chunks: [sseFrame(content: "开头")], holdOpen: true)
        ])
        let port = try server.start()
        defer { server.stop() }

        var policy = slowPolicy(hedging: false)
        policy.idleTimeout = 0.5
        do {
            _ = try await client().stream(
                systemPrompt: "s",
                userPrompt: "u",
                configuration: configuration(port: port),
                options: .meetingSummary,
                policy: policy,
                onEvent: { _ in }
            )
            XCTFail("中途卡住应该失败")
        } catch let error as AIAPIError {
            guard case let .streamStalled(_, beforeFirstToken) = error else {
                return XCTFail("应该是卡住，实际是 \(error)")
            }
            XCTAssertFalse(beforeFirstToken, "已经有内容了，属于中途卡住")
        }
    }

    func testAServerThatIgnoresStreamIsReadAsOneAnswer() async throws {
        let envelope = #"{"choices":[{"message":{"role":"assistant","content":"完整回答"},"finish_reason":"stop"}]}"#
        let server = try StubHTTPServer(replies: [
            .init(contentType: "application/json", chunks: [envelope])
        ])
        let port = try server.start()
        defer { server.stop() }

        let content = try await client().stream(
            systemPrompt: "s",
            userPrompt: "u",
            configuration: configuration(port: port),
            options: .meetingSummary,
            policy: slowPolicy(hedging: false),
            onEvent: { _ in }
        )

        XCTAssertEqual(content, "完整回答")
    }

    func testReasoningAndContentBothReachTheCallerInOrder() async throws {
        let server = try StubHTTPServer(replies: [
            .init(chunks: [sseReasoningFrame("想一下"), sseFrame(content: "A"), sseFrame(content: "B"), sseDone])
        ])
        let port = try server.start()
        defer { server.stop() }

        let log = LockedStreamLog()
        let content = try await client().stream(
            systemPrompt: "s",
            userPrompt: "u",
            configuration: configuration(port: port),
            options: .meetingSummary,
            policy: slowPolicy(hedging: false),
            onEvent: { log.append($0) }
        )

        XCTAssertEqual(content, "AB")
        XCTAssertEqual(log.events, [.reasoning("想一下"), .content("A"), .content("B")])
    }

    func testTheRequestAsksForStreaming() async throws {
        let server = try StubHTTPServer(replies: [
            .init(chunks: [sseFrame(content: "ok"), sseDone])
        ])
        let port = try server.start()
        defer { server.stop() }

        _ = try await client().stream(
            systemPrompt: "系统",
            userPrompt: "用户",
            configuration: configuration(port: port),
            options: .meetingSummary,
            policy: slowPolicy(hedging: false),
            onEvent: { _ in }
        )

        let body = try XCTUnwrap(server.lastRequestBody)
        XCTAssertTrue(body.contains(#""stream":true"#), body)
        XCTAssertTrue(body.contains("系统"), "请求体里应该有系统提示词")
    }

    func testLoopbackMayUsePlainHTTPButPublicHostsMayNot() {
        XCTAssertNotNil(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "http://127.0.0.1:11434/v1")
        )
        XCTAssertNotNil(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "http://localhost:1234/v1")
        )
        XCTAssertNil(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "http://api.openai.com/v1"),
            "公网地址仍然只允许 https"
        )
    }

    // MARK: - Helpers

    private func client() -> OpenAICompatibleAPIClient {
        OpenAICompatibleAPIClient()
    }

    private func configuration(port: UInt16) -> AIAPIConfiguration {
        AIAPIConfiguration(
            endpoint: "http://127.0.0.1:\(port)/v1/chat/completions",
            model: "stub-model",
            apiKey: "stub-key",
            providerID: AIAPIProvider.custom.rawValue
        )
    }

    private func slowPolicy(hedging: Bool) -> AIStreamingPolicy {
        AIStreamingPolicy(
            hedgingEnabled: hedging,
            hedgeDelay: 5,
            firstDeltaTimeout: 30,
            idleTimeout: 30,
            totalTimeout: 60
        )
    }
}

private final class LockedStreamLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AIStreamEvent] = []

    var events: [AIStreamEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: AIStreamEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}
