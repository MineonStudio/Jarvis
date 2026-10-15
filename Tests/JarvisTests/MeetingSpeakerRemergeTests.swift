import Foundation
@testable import Jarvis
import XCTest

/// Re-running the speaker assignment must not cost the user anything: it is a repair for
/// transcripts made by an older rule, not a tidy-up of the list they have been editing.
final class MeetingSpeakerRemergeTests: XCTestCase {
    func testANameAndColourSurviveASpeakerWhoLostEverySegment() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 4, speakerID: "old", text: "先说范围"),
            MeetingTranscriptSegment(startTime: 5, endTime: 9, speakerID: "old", text: "再排期")
        ]
        let turns = [MeetingSpeakerTurnRecord(startTime: 0, endTime: 4.5, clusterID: "mic:0")]
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 3),
            MeetingSpeaker(id: "mic:7", name: "李娜", colorIndex: 1)
        ]

        let merged = MeetingSpeakerRemerge.apply(
            segments: segments,
            turns: turns,
            overrides: [],
            speakers: speakers
        )

        XCTAssertEqual(
            merged.speakers.first { $0.id == "mic:7" }?.name,
            "李娜",
            "没有任何一句归属的说话人，名字也不该被丢掉"
        )
        XCTAssertEqual(
            merged.speakers.first { $0.id == "mic:0" }?.colorIndex,
            3,
            "已有的颜色不该因为重跑而换个位置"
        )
    }

    func testANewSpeakerNeverTakesANameSomebodyElseHas() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 4, speakerID: "old", text: "开场")
        ]
        let turns = [
            MeetingSpeakerTurnRecord(startTime: 0, endTime: 4.5, clusterID: "mic:9")
        ]
        // 说话人 2 was renamed, so counting the names left would mint 说话人 2 again.
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0),
            MeetingSpeaker(id: "mic:5", name: "说话人 3", colorIndex: 1)
        ]

        let merged = MeetingSpeakerRemerge.apply(
            segments: segments,
            turns: turns,
            overrides: [],
            speakers: speakers
        )

        let names = merged.speakers.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "说话人名字不能重复：\(names)")
        XCTAssertTrue(names.contains("说话人 3"), "已有的名字要留着：\(names)")
        let minted = names.filter { $0.hasPrefix("说话人 ") && $0 != "说话人 3" }
        XCTAssertEqual(minted.count, 2, "新来的说话人也要有个编号：\(names)")
    }

    func testTheSameTranscriptComesBackUnchanged() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 4, speakerID: "old", text: "先说范围"),
            MeetingTranscriptSegment(startTime: 4.2, endTime: 8, speakerID: "old", text: "再排期")
        ]
        let turns = [
            MeetingSpeakerTurnRecord(startTime: 0, endTime: 4.5, clusterID: "mic:0"),
            MeetingSpeakerTurnRecord(startTime: 4.5, endTime: 8, clusterID: "mic:1")
        ]
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0),
            MeetingSpeaker(id: "mic:1", name: "说话人 2", colorIndex: 1)
        ]

        let first = MeetingSpeakerRemerge.apply(
            segments: segments,
            turns: turns,
            overrides: [],
            speakers: speakers
        )
        let second = MeetingSpeakerRemerge.apply(
            segments: first.segments,
            turns: turns,
            overrides: [],
            speakers: first.speakers
        )

        XCTAssertEqual(first.segments.map(\.speakerID), second.segments.map(\.speakerID))
        XCTAssertEqual(first.speakers, second.speakers)
    }
}
