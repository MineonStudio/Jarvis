import Foundation
@testable import Jarvis
import XCTest

final class MeetingTranscriptPayloadTests: XCTestCase {
    func testPromptLinesCarryShortIDsAndDropTimestamps() {
        let segment = MeetingTranscriptSegment(startTime: 12.5, endTime: 14, speakerID: "S1", text: "先做首版。")
        let text = MeetingTranscriptFormat.render(
            segments: [segment],
            speakerNames: ["S1": "张伟"],
            shortIDs: [segment.id: "S1"]
        )

        XCTAssertEqual(text, "[S1] 张伟：先做首版。")
        XCTAssertFalse(text.contains(segment.id.uuidString))
        XCTAssertFalse(text.contains("12500"))
    }

    func testKeywordBecomesAnExactQuoteFromTheSegment() throws {
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 3,
            speakerID: "S1",
            text: "是证书链没带完整证书，我已经把中间证书补进去了。"
        )
        let draft = MeetingMinutesAlgorithm.DraftEvidence(
            segmentID: "S1",
            startMs: 0,
            endMs: 0,
            quote: "",
            keyword: "中间证书"
        )
        let quote = try XCTUnwrap(MeetingMinutesAlgorithm.evidenceQuote(draft, in: segment))

        XCTAssertTrue(segment.text.contains(quote))
        XCTAssertTrue(quote.contains("中间证书"))
    }

    func testRewrittenQuoteIsStillRejectedWithoutAKeyword() {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "埋点由客户端上报。")
        let draft = MeetingMinutesAlgorithm.DraftEvidence(
            segmentID: "S1",
            startMs: 0,
            endMs: 1000,
            quote: "这里不是原句"
        )

        XCTAssertNil(MeetingMinutesAlgorithm.evidenceQuote(draft, in: segment))
    }

    func testAnExactQuoteIsKeptExactlyAsWritten() throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "埋点由客户端上报。")
        let draft = MeetingMinutesAlgorithm.DraftEvidence(
            segmentID: "S1",
            startMs: 0,
            endMs: 1000,
            quote: "客户端上报"
        )

        XCTAssertEqual(try XCTUnwrap(MeetingMinutesAlgorithm.evidenceQuote(draft, in: segment)), "客户端上报")
    }

    func testALongSentenceIsTrimmedAroundTheKeyword() throws {
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 9,
            speakerID: "S1",
            text: String(repeating: "这一段在讲别的背景", count: 12) + "证书链要补齐" + String(repeating: "后面还有别的结论", count: 12)
        )
        let draft = MeetingMinutesAlgorithm.DraftEvidence(
            segmentID: "S1",
            startMs: 0,
            endMs: 0,
            quote: "",
            keyword: "证书链要补齐"
        )
        let quote = try XCTUnwrap(MeetingMinutesAlgorithm.evidenceQuote(draft, in: segment))

        XCTAssertTrue(segment.text.contains(quote))
        XCTAssertTrue(quote.contains("证书链要补齐"))
        XCTAssertLessThanOrEqual(quote.count, 60)
    }

    func testIndexResolvesShortIDsAndRawUUIDs() {
        let first = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "一")
        let second = MeetingTranscriptSegment(startTime: 1, endTime: 2, speakerID: "S1", text: "二")
        let index = TranscriptIndex(transcript: [first, second])

        XCTAssertEqual(index.segment(for: "S1")?.id, first.id)
        XCTAssertEqual(index.segment(for: "s2")?.id, second.id)
        XCTAssertEqual(index.segment(for: second.id.uuidString)?.id, second.id)
        XCTAssertNil(index.segment(for: "S9"))
        XCTAssertEqual(index.shortID(for: first), "S1")
    }

    func testAShortTranscriptStaysInOneWindow() {
        let lines = ["[S1] 张伟：先做首版。", "[S2] 李娜：下周三再看。"]

        let windows = MeetingTranscriptFormat.windows(forLines: lines, budget: 12000)

        XCTAssertEqual(windows.count, 1)
        XCTAssertTrue(windows[0].text.contains("先做首版。"))
    }

    func testALongTranscriptIsSplitIntoWindowsThatFit() {
        let lines = [
            "[S1] 张伟：" + String(repeating: "议", count: 9000),
            "[S2] 李娜：" + String(repeating: "题", count: 9000)
        ]

        let windows = MeetingTranscriptFormat.windows(forLines: lines, budget: 12000)

        XCTAssertEqual(windows.count, 2)
        XCTAssertTrue(windows.allSatisfy { $0.estimatedTokens <= 12000 })
    }

    func testASingleLineTooLongToFitIsCutInHalf() {
        let window = TranscriptWindow(text: String(repeating: "会议内容", count: 4000))
        let pieces = MeetingTranscriptFormat.split(window)

        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].text.count + pieces[1].text.count, window.text.count)
    }

    func testTokenEstimateCountsCJKPerCharacter() {
        XCTAssertEqual(MeetingTranscriptFormat.estimateTokens("会议内容"), 4)
        XCTAssertEqual(MeetingTranscriptFormat.estimateTokens("abcdefgh"), 2)
    }
}
