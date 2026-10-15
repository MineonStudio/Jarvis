import Foundation
@testable import Jarvis
import XCTest

final class MeetingMinutesStreamDecoderTests: XCTestCase {
    private let sample = """
    {"summary":"会上确认了三件事。","points":[{"id":"P1","title":"登录改版","detail":"已提测","evidence":[{"segment_id":"S1","keyword":"提测"}]}],"todos":[{"id":"T1","task":"补证书链","owner":null,"due":null,"evidence":[{"segment_id":"S2","keyword":"证书链"}]}]}
    """

    func testReadsOverviewPointsAndTodosFromOneChunk() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(sample)

        XCTAssertEqual(overview(of: events), ["会上确认了三件事。"])
        XCTAssertEqual(points(of: events).count, 1)
        XCTAssertEqual(todos(of: events).count, 1)
        XCTAssertTrue(points(of: events)[0].contains("\"title\":\"登录改版\""))
    }

    func testStreamsTheSameEventsWhenFedCharacterByCharacter() {
        var decoder = MeetingMinutesStreamDecoder()
        var events: [MeetingMinutesStreamDecoder.Event] = []
        for character in sample {
            events += decoder.feed(String(character))
        }

        let whole = eventsFromOneChunk(sample)
        XCTAssertEqual(overview(of: events).joined(), "会上确认了三件事。")
        XCTAssertEqual(points(of: events), points(of: whole))
        XCTAssertEqual(todos(of: events), todos(of: whole))
        XCTAssertEqual(points(of: events).count, 1)
        XCTAssertEqual(todos(of: events).count, 1)
    }

    func testOverviewArrivesBeforeTheRestOfTheDocumentFinishes() {
        var decoder = MeetingMinutesStreamDecoder()
        let head = #"{"summary":"先出来的概要""#
        let events = decoder.feed(head)

        XCTAssertEqual(overview(of: events).joined(), "先出来的概要")
        XCTAssertTrue(points(of: events).isEmpty)
    }

    func testDecodesEscapesAndUnicodeInTheOverview() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(#"{"summary":"第一行\n第二行 \"引用\" 中文"}"#)

        XCTAssertEqual(overview(of: events).joined(), "第一行\n第二行 \"引用\" 中文")
    }

    func testKeepsEscapesSplitAcrossChunks() {
        var decoder = MeetingMinutesStreamDecoder()
        var text = ""
        for character in #"{"summary":"a中b\nc"}"# {
            text += overview(of: decoder.feed(String(character))).joined()
        }
        XCTAssertEqual(text, "a中b\nc")
    }

    func testSkipsProseAndCodeFencesBeforeTheObject() {
        var decoder = MeetingMinutesStreamDecoder()
        let raw = """
        好的，这是纪要：
        ```json
        {"summary":"围栏里的概要","points":[],"todos":[]}
        ```
        """
        let events = raw.map { decoder.feed(String($0)) }.flatMap(\.self)

        XCTAssertEqual(overview(of: events).joined(), "围栏里的概要")
    }

    func testCapturedPointSliceDecodesWithJSONDecoder() throws {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(sample)
        let slice = try XCTUnwrap(points(of: events).first)

        let draft = try JSONDecoder().decode(
            MeetingMinutesAlgorithm.DraftPoint.self,
            from: Data(slice.utf8)
        )
        XCTAssertEqual(draft.id, "P1")
        XCTAssertEqual(draft.evidence?.first?.segmentID, "S1")
    }

    func testNestedEvidenceArraysKeepTheSliceBalanced() throws {
        var decoder = MeetingMinutesStreamDecoder()
        let raw = #"{"points":[{"id":"P1","evidence":[{"segment_id":"S1","keyword":"a"},{"segment_id":"S2","keyword":"b"}],"detail":"d"}],"summary":"x"}"#
        let events = decoder.feed(raw)
        let slice = try XCTUnwrap(points(of: events).first)

        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(slice.utf8)))
        XCTAssertEqual(slice.filter { $0 == "{" }.count, slice.filter { $0 == "}" }.count)
    }

    func testHandlesPointsComingBeforeTheOverview() {
        var decoder = MeetingMinutesStreamDecoder()
        var events: [MeetingMinutesStreamDecoder.Event] = []
        for character in #"{"points":[{"id":"P1"}],"summary":"后到的概要"}"# {
            events += decoder.feed(String(character))
        }

        XCTAssertEqual(points(of: events).count, 1)
        XCTAssertEqual(overview(of: events).joined(), "后到的概要")
    }

    func testReadsActionItemsAsTodos() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(#"{"summary":"s","actionItems":[{"id":"T1","task":"发文档"}]}"#)

        XCTAssertEqual(todos(of: events).count, 1)
        XCTAssertTrue(todos(of: events)[0].contains("发文档"))
    }

    func testIgnoresTrailingTextAfterTheRootObject() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(#"{"summary":"完成"}{"summary":"这是第二个对象，不该被读进来"}"#)

        XCTAssertEqual(overview(of: events).joined(), "完成")
    }

    func testSurrogatesDoNotRunAcrossTwoStrings() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(#"{"note":"\uD83C","summary":"\uDE00 tail"}"#)

        XCTAssertEqual(
            overview(of: events).joined(),
            " tail",
            "半个代理对只属于它自己那个字符串，不该和后面的拼成一个字"
        )
    }

    func testBracesInProseDoNotEndTheRun() {
        var decoder = MeetingMinutesStreamDecoder()
        var events: [MeetingMinutesStreamDecoder.Event] = []
        for character in #"使用 {} 表示对象，正文如下：{"summary":"真实的概要"}"# {
            events += decoder.feed(String(character))
        }

        XCTAssertEqual(overview(of: events).joined(), "真实的概要")
    }

    func testARepeatedOverviewKeyRestartsThePreview() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(#"{"summary":"先写的","summary":"后写的"}"#)

        XCTAssertEqual(overview(of: events).joined(), "先写的后写的")
        XCTAssertEqual(events.filter { $0 == .overviewRestarted }.count, 1, "第二次写概要时预览要重来")
    }

    func testIgnoresEmptyArrays() {
        var decoder = MeetingMinutesStreamDecoder()
        let events = decoder.feed(#"{"summary":"空","points":[],"todos":[]}"#)

        XCTAssertEqual(overview(of: events).joined(), "空")
        XCTAssertTrue(points(of: events).isEmpty)
        XCTAssertTrue(todos(of: events).isEmpty)
    }

    // MARK: - Helpers

    private func eventsFromOneChunk(_ text: String) -> [MeetingMinutesStreamDecoder.Event] {
        var decoder = MeetingMinutesStreamDecoder()
        return decoder.feed(text)
    }

    private func overview(of events: [MeetingMinutesStreamDecoder.Event]) -> [String] {
        events.compactMap { event in
            if case let .overviewDelta(text) = event {
                return text
            }
            return nil
        }
    }

    private func points(of events: [MeetingMinutesStreamDecoder.Event]) -> [String] {
        events.compactMap { event in
            if case let .pointCompleted(json) = event {
                return json
            }
            return nil
        }
    }

    private func todos(of events: [MeetingMinutesStreamDecoder.Event]) -> [String] {
        events.compactMap { event in
            if case let .todoCompleted(json) = event {
                return json
            }
            return nil
        }
    }
}
