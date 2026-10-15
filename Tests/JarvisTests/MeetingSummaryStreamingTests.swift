import Foundation
@testable import Jarvis
import XCTest

final class MeetingSummaryStreamingTests: XCTestCase {
    @MainActor
    func testOverviewShowsUpWhileTheAnswerIsStillBeingWritten() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "先做首版。")
        let api = StreamingMeetingAPI(
            plan: [
                .deltas([
                    #"{"summary":"会上先确认了首版的范围"#,
                    #"，并约定这周内提测。","points":[{"id":"P1","title":"首版范围","detail":"先做首版。","evidence":[{"segment_id":"S1","keyword":"首版"}]}],"todos":[]}"#
                ])
            ]
        )
        let collector = LiveUpdateCollector()
        let summary = try await MeetingSummaryService(api: api).summarize(
            record: meetingRecordForStreaming(title: "流式", segments: [segment]),
            configuration: streamTestConfiguration,
            onLiveUpdate: { collector.record($0) }
        )
        try await settleLiveUpdates()

        let drafts = collector.drafts
        XCTAssertFalse(drafts.isEmpty, "生成过程中应该已经能显示内容")
        XCTAssertTrue(
            drafts.contains { $0.overview.contains("先确认了首版的范围") && !$0.overview.contains("提测") },
            "概要应该边生成边出现，而不是等整段写完"
        )
        XCTAssertTrue(drafts.contains { $0.points.count == 1 })
        XCTAssertEqual(summary.points.map(\.title), ["首版范围"])
    }

    @MainActor
    func testThinkingIsReportedBeforeAnyMinutesArrive() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "先做首版。")
        let api = StreamingMeetingAPI(
            plan: [
                .deltas([
                    "\n\n",
                    #"{"summary":"概要内容","points":[],"todos":[]}"#
                ], reasoning: ["先想想", "再想想"])
            ]
        )
        let collector = LiveUpdateCollector()
        _ = try await MeetingSummaryService(api: api).summarize(
            record: meetingRecordForStreaming(title: "思考", segments: [segment]),
            configuration: streamTestConfiguration,
            onLiveUpdate: { collector.record($0) }
        )
        try await settleLiveUpdates()

        XCTAssertTrue(collector.sawThinking, "推理模型先吐思考时应该让用户看到进展")
    }

    func testStalledRequestIsAskedAgainInsteadOfFailing() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "先做首版。")
        let response = minutesStreamJSON(summary: paddedSummary("首版范围已确认。"))
        let api = StreamingMeetingAPI(
            plan: [
                .failure(.streamStalled(seconds: 25, beforeFirstToken: true)),
                .deltas([response])
            ]
        )
        let summary = try await MeetingSummaryService(api: api).summarize(
            record: meetingRecordForStreaming(title: "卡住", segments: [segment]),
            configuration: streamTestConfiguration
        )

        XCTAssertEqual(summary.overview, paddedSummary("首版范围已确认。"))
        let count = await api.callCount
        XCTAssertEqual(count, 2, "上游挂住一次以后应该再试一次，而不是直接失败")
    }

    func testAWindowThatDoesNotFitIsSplitAndMergedBack() async throws {
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 1,
            speakerID: "S1",
            text: String(repeating: "会议内容", count: 2400)
        )
        let windowJSON = minutesStreamJSON(summary: paddedSummary("这一半的结论。"))
        let mergedJSON = minutesStreamJSON(summary: paddedSummary("合并后的结论。"))
        let api = StreamingMeetingAPI(
            failFirstCall: .server("This model's maximum context length is 8192 tokens"),
            responsesByPromptFragment: ["请合并成一份": mergedJSON],
            defaultResponse: windowJSON
        )
        // A scratch store: what one run learns about a model must not leak into another.
        var service = MeetingSummaryService(api: api)
        service.budgets = AIContextBudgetStore(defaults: scratchDefaults())
        let summary = try await service.summarize(
            record: meetingRecordForStreaming(title: "超长", segments: [segment]),
            configuration: streamTestConfiguration
        )

        let prompts = await api.userPrompts
        let shapes = prompts.map { prompt -> String in
            if prompt.contains("请合并成一份") {
                return "merge"
            }
            if let label = prompt.range(of: "这是会议的第 ") {
                return String(prompt[label.lowerBound...].prefix(12))
            }
            return "whole"
        }
        XCTAssertEqual(summary.overview, paddedSummary("合并后的结论。"), shapes.joined(separator: " | "))
        XCTAssertLessThanOrEqual(prompts.count, 6, "切分以后应该只有每一段的请求加一次合并：\(shapes)")
        XCTAssertTrue(shapes.first == "whole")
        XCTAssertTrue(shapes.contains { $0.hasPrefix("这是会议的第 1/") })
        XCTAssertEqual(shapes.last, "merge")
    }

    func testContextBudgetFallsAfterARejectionAndFollowsTheProvider() {
        let defaults = scratchDefaults()
        let store = AIContextBudgetStore(defaults: defaults)
        let configuration = streamTestConfiguration

        XCTAssertEqual(store.budget(for: configuration), AIContextBudgetStore.defaultBudget)

        store.recordContextWindow(100_000, for: configuration)
        XCTAssertEqual(store.budget(for: configuration), 40000, "服务商报了窗口就按窗口的一部分来")

        store.recordTooLong(estimatedTokens: 8000, for: configuration)
        XCTAssertEqual(store.budget(for: configuration), 4000, "被拒绝过一次就记住更小的安全值")

        store.recordContextWindows(["big-model": 1_000_000], providerID: "custom")
        XCTAssertEqual(
            AIContextBudgetStore(defaults: defaults).budget(
                for: AIAPIConfiguration(
                    endpoint: "https://example.com/v1/chat/completions",
                    model: "big-model",
                    apiKey: "k",
                    providerID: "custom"
                )
            ),
            AIContextBudgetStore.maximumBudget,
            "取模型列表时记下的窗口要能跨启动保留"
        )
    }
}

/// Live updates are delivered through the main actor; give them a turn to land.
@MainActor
private func settleLiveUpdates() async throws {
    try await Task.sleep(for: .milliseconds(60))
}

private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "jarvis.tests.\(UUID().uuidString)") ?? .standard
}

@MainActor
private final class LiveUpdateCollector {
    private(set) var updates: [MeetingSummaryLiveUpdate] = []

    var drafts: [MeetingSummary] {
        updates.compactMap { update in
            if case let .draft(summary) = update {
                return summary
            }
            return nil
        }
    }

    var sawThinking: Bool {
        updates.contains { $0 == .thinking }
    }

    func record(_ update: MeetingSummaryLiveUpdate) {
        updates.append(update)
    }
}

private actor StreamingMeetingAPI: AITextCompletionAPI {
    enum Step: Sendable {
        case deltas([String], reasoning: [String] = [])
        case failure(AIAPIError)
    }

    private var plan: [Step]
    private var failFirstCall: AIAPIError?
    private var responsesByPromptFragment: [String: String]
    private var defaultResponse: String
    private(set) var userPrompts: [String] = []

    var callCount: Int {
        userPrompts.count
    }

    init(plan: [Step]) {
        self.plan = plan
        failFirstCall = nil
        responsesByPromptFragment = [:]
        defaultResponse = ""
    }

    init(
        failFirstCall: AIAPIError? = nil,
        responsesByPromptFragment: [String: String] = [:],
        defaultResponse: String
    ) {
        plan = []
        self.failFirstCall = failFirstCall
        self.responsesByPromptFragment = responsesByPromptFragment
        self.defaultResponse = defaultResponse
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            options: .meetingSummary
        )
    }

    func complete(
        systemPrompt _: String,
        userPrompt _: String,
        configuration _: AIAPIConfiguration,
        options _: AICompletionOptions
    ) async throws -> String {
        throw AIAPIError.missingConfiguration
    }

    func stream(
        systemPrompt _: String,
        userPrompt: String,
        configuration _: AIAPIConfiguration,
        options _: AICompletionOptions,
        policy _: AIStreamingPolicy,
        onEvent: @escaping @Sendable (AIStreamEvent) -> Void
    ) async throws -> String {
        userPrompts.append(userPrompt)
        if let failure = failFirstCall {
            failFirstCall = nil
            throw failure
        }
        for (fragment, response) in responsesByPromptFragment where userPrompt.contains(fragment) {
            onEvent(.content(response))
            return response
        }
        // Running past the plan is a failure of the test's expectations, not of the service;
        // keep answering so the assertions can describe what actually happened.
        guard !plan.isEmpty else {
            let fallback = minutesStreamJSON(summary: paddedSummary("计划外的调用"))
            onEvent(.content(fallback))
            return fallback
        }
        switch plan.removeFirst() {
        case let .failure(error):
            throw error
        case let .deltas(pieces, reasoning):
            for text in reasoning {
                onEvent(.reasoning(text))
            }
            var content = ""
            for piece in pieces {
                onEvent(.content(piece))
                content += piece
            }
            return content
        }
    }
}

private let streamTestConfiguration = AIAPIConfiguration(
    endpoint: "https://example.com/v1/chat/completions",
    model: "stream-test",
    apiKey: "test-key"
)

private func meetingRecordForStreaming(
    title: String,
    segments: [MeetingTranscriptSegment]
) -> MeetingRecord {
    MeetingRecord(
        title: title,
        audioFileName: "meeting-\(UUID().uuidString).m4a",
        speakers: [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)],
        transcript: segments
    )
}

private func minutesStreamJSON(summary: String) -> String {
    #"{"summary":"\#(summary)","points":[],"todos":[]}"#
}

private func paddedSummary(_ text: String) -> String {
    var value = text
    while value.count < 220 {
        value += "会上确认了这一安排。"
    }
    if value.count > 400 {
        value = String(value.prefix(400))
    }
    return value
}
