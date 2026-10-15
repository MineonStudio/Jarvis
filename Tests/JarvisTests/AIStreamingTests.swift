import Foundation
@testable import Jarvis
import XCTest

final class AIStreamingTests: XCTestCase {
    func testReadsContentAndReasoningFromOneFrame() {
        var decoder = SSEChatCompletionDecoder()
        let line = #"data: {"choices":[{"index":0,"delta":{"reasoning_content":"想想","content":"答案"}}]}"#

        XCTAssertEqual(decoder.feed(line: line), [.reasoning("想想"), .content("答案")])
    }

    func testAlternateReasoningSpellingIsAccepted() {
        var decoder = SSEChatCompletionDecoder()
        let line = #"data: {"choices":[{"delta":{"reasoning":"先想一下"}}]}"#

        XCTAssertEqual(decoder.feed(line: line), [.reasoning("先想一下")])
    }

    func testCommentsAndEmptyDeltasProduceNothing() {
        var decoder = SSEChatCompletionDecoder()
        let line = #"data: {"choices":[{"delta":{"role":"assistant","content":null,"reasoning_content":""}}]}"#

        XCTAssertTrue(decoder.feed(line: ": keep-alive").isEmpty)
        XCTAssertTrue(decoder.feed(line: "").isEmpty)
        XCTAssertTrue(decoder.feed(line: line).isEmpty)
    }

    func testClosingFrameIsRemembered() {
        var decoder = SSEChatCompletionDecoder()

        XCTAssertTrue(decoder.feed(line: "data: [DONE]").isEmpty)
        XCTAssertTrue(decoder.sawCompletion)
    }

    func testFinishReasonCountsAsCompletion() {
        var decoder = SSEChatCompletionDecoder()
        _ = decoder.feed(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)

        XCTAssertTrue(decoder.sawCompletion)
    }

    func testMalformedFrameIsSkipped() {
        var decoder = SSEChatCompletionDecoder()

        XCTAssertTrue(decoder.feed(line: "data: {not json").isEmpty)
        XCTAssertFalse(decoder.sawAnyEvent)
    }

    func testMessageShapeIsAcceptedWhenAProviderDoesNotStream() {
        var decoder = SSEChatCompletionDecoder()
        let line = #"data: {"choices":[{"message":{"role":"assistant","content":"完整回答"}}]}"#

        XCTAssertEqual(decoder.feed(line: line), [.content("完整回答")])
    }

    func testTheFirstAttemptToAnswerOwnsTheStream() async {
        let log = LockedEventLog()
        let sink = AIStreamSink { log.append($0) }

        let primaryKeptIt = await sink.accept(attempt: 0, events: [.content("先到的")])
        let duplicateRejected = await sink.accept(attempt: 1, events: [.content("后到的")])

        XCTAssertTrue(primaryKeptIt)
        XCTAssertFalse(duplicateRejected, "补发的请求不该再往界面上写内容")
        XCTAssertEqual(log.events, [.content("先到的")])
        let produced = await sink.hasProducedEvent
        XCTAssertTrue(produced)
    }

    func testSilenceIsMeasuredFromTheLastEvent() async {
        let sink = AIStreamSink { _ in }
        _ = await sink.accept(attempt: 0, events: [.content("开始")])

        let silence = await sink.secondsSinceActivity
        XCTAssertGreaterThanOrEqual(silence, 0)
        XCTAssertLessThan(silence, 1)
    }

    func testHedgeDelayFollowsWhatTheProviderActuallyDoes() {
        let defaults = UserDefaults(suiteName: "jarvis.tests.hedge.\(UUID().uuidString)") ?? .standard
        let history = AIStreamingLatencyHistory(defaults: defaults)
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "slow-model",
            apiKey: "k",
            providerID: "custom"
        )

        XCTAssertEqual(
            history.suggestedHedgeDelay(for: configuration),
            AIStreamingPolicy.defaultHedgeDelay,
            "样本不足时不该乱动默认值"
        )
        for _ in 0 ..< 3 {
            history.record(firstTokenSeconds: 20, configuration: configuration)
        }
        XCTAssertEqual(history.suggestedHedgeDelay(for: configuration), 40)

        for _ in 0 ..< 3 {
            history.record(firstTokenSeconds: 60, configuration: configuration)
        }
        XCTAssertEqual(
            history.suggestedHedgeDelay(for: configuration),
            AIStreamingPolicy.maximumHedgeDelay,
            "很慢的模型不该被无限跟着放大"
        )
    }
}

private final class LockedEventLog: @unchecked Sendable {
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
