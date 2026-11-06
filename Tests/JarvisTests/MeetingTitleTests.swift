@testable import Jarvis
import XCTest

final class MeetingTitleTests: XCTestCase {
    private let summary = MeetingSummary(
        overview: "确认支付模块修复计划与上线时间。", actionItems: [],
        points: [MeetingDiscussionPoint(id: "P1", title: "上线安排", detail: "先修复问题再测试。", evidence: [])]
    )

    func testGeneratesTitleFromFinishedMinutesUsingExistingAIConfiguration() async throws {
        let api = TitleTestAPI()
        let configuration = AIAPIConfiguration(endpoint: "https://example.com/v1/chat/completions", model: "existing-model", apiKey: "test-key")
        let title = try await MeetingTitleService(api: api).generate(from: summary, configuration: configuration)
        XCTAssertEqual(title, "支付模块修复与上线安排")
        let received = await api.received
        XCTAssertEqual(received?.configuration.model, configuration.model)
        XCTAssertEqual(received?.configuration.endpoint, configuration.endpoint)
        XCTAssertEqual(received?.configuration.apiKey, configuration.apiKey)
        XCTAssertTrue(received?.prompt.contains(summary.overview) == true)
        XCTAssertTrue(received?.prompt.contains("上线安排") == true)
        XCTAssertEqual(received?.task, "meeting-title")
    }

    func testInvalidOrExplanatoryNamesAreRejected() throws {
        XCTAssertEqual(try MeetingTitleService.parse("```json\n{\"title\":\"  交付方案评审  \"}\n```"), "交付方案评审")
        for raw in ["不是 JSON", "{}", "{\"title\":\"\"}", "{\"title\":\"未命名会议\"}", "{\"title\":\"# 标题\"}", "{\"title\":\"第一行\\n第二行\"}"] {
            XCTAssertThrowsError(try MeetingTitleService.parse(raw))
        }
        let tooLong = try JSONSerialization.data(withJSONObject: ["title": String(repeating: "长", count: 41)])
        XCTAssertThrowsError(try MeetingTitleService.parse(XCTUnwrap(String(data: tooLong, encoding: .utf8))))
    }

    func testManualRenameAndNewSummaryRejectStaleAIResults() {
        var record = MeetingRecord(title: "imported-file", audioFileName: "sample.m4a", status: .ready, summary: summary, titleIsUserEdited: false)
        XCTAssertTrue(MeetingTitlePolicy.canApply(to: record, originalTitle: record.title, summary: summary))
        let original = record.title
        XCTAssertTrue(record.setUserTitle("手动会议名称"))
        XCTAssertTrue(record.titleIsUserEdited)
        XCTAssertFalse(MeetingTitlePolicy.canApply(to: record, originalTitle: original, summary: summary))
        record.setUserTitle("")
        XCTAssertEqual(record.title, MeetingRecord.defaultTitle)
        XCTAssertFalse(record.titleIsUserEdited)
        XCTAssertFalse(MeetingTitlePolicy.canApply(to: record, originalTitle: original, summary: summary))
        let currentTitle = record.title
        record.summary?.overview = "新的纪要"
        XCTAssertFalse(MeetingTitlePolicy.canApply(to: record, originalTitle: currentTitle, summary: summary))
    }

    func testTitleOwnershipSurvivesRepositoryAndLegacyRecordsKeepCustomNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("title-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MeetingRepository(directoryURL: directory)
        var record = MeetingRecord(title: "AI 生成的会议名称", audioFileName: "sample.m4a", status: .ready, titleIsUserEdited: false)
        try repository.save(record)
        XCTAssertEqual(repository.load().records.first?.titleIsUserEdited, false)
        XCTAssertFalse(record.setUserTitle(record.title), "Leaving an unchanged title field must not claim it as a manual name")
        XCTAssertFalse(record.titleIsUserEdited)
        record.setUserTitle("用户自定义")
        try repository.save(record)
        XCTAssertEqual(repository.load().records.first?.titleIsUserEdited, true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "titleIsUserEdited")
        let oldRecord = try JSONDecoder().decode(MeetingRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(oldRecord.titleIsUserEdited)
        object["title"] = MeetingRecord.defaultTitle
        let oldUntitled = try JSONDecoder().decode(MeetingRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(oldUntitled.titleIsUserEdited)
    }
}

private actor TitleTestAPI: AITextCompletionAPI {
    struct Received: Sendable { let configuration: AIAPIConfiguration; let prompt: String; let task: String }
    private(set) var received: Received?
    func complete(systemPrompt: String, userPrompt: String, configuration: AIAPIConfiguration) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration, options: .standardJSON)
    }

    func complete(systemPrompt _: String, userPrompt: String, configuration: AIAPIConfiguration, options: AICompletionOptions) async throws -> String {
        received = Received(configuration: configuration, prompt: userPrompt, task: options.task)
        return "{\"title\":\"支付模块修复与上线安排\"}"
    }
}
