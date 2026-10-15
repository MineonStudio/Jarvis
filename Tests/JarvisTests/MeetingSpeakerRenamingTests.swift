import Foundation
@testable import Jarvis
import XCTest

final class MeetingSpeakerRenamingTests: XCTestCase {
    func testTheSameShortNameIsUsedByEveryMeeting() {
        // Speaker ids are per-recording cluster labels, not app-wide ones: the same two
        // strings appear in every meeting, which is why anything keyed by them has to be
        // keyed by the recording as well.
        let first = MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0)
        let second = MeetingSpeaker(id: "mic:0", name: "王强", colorIndex: 0)

        XCTAssertEqual(first.id, second.id)
        XCTAssertNotEqual(first.name, second.name)
    }

    func testARenameFollowsIntoTheMinutesWhileTheOldNameMeantOnePerson() {
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0),
            MeetingSpeaker(id: "mic:1", name: "说话人 2", colorIndex: 1)
        ]
        var summary = sampleSummary()
        summary.actionItems[0].owner = "说话人 1"
        summary.actionItems[1].owner = "说话人 2"

        XCTAssertTrue(MeetingSpeakerRenaming.isUnambiguous("说话人 1", among: speakers))
        let renamed = MeetingSpeakerRenaming.relabeling(summary, from: "说话人 1", to: "王强")

        XCTAssertEqual(renamed.actionItems.map(\.owner), ["王强", "说话人 2"])
    }

    func testASharedOldNameIsAmbiguousSoNothingIsMoved() {
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0),
            MeetingSpeaker(id: "mic:1", name: "说话人 1", colorIndex: 1)
        ]

        XCTAssertFalse(
            MeetingSpeakerRenaming.isUnambiguous("说话人 1", among: speakers),
            "两个说话人重名时，负责人可能属于任何一方，不能跟着改"
        )
    }

    func testANameAlreadyInUseIsRefused() {
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0),
            MeetingSpeaker(id: "mic:1", name: "说话人 2", colorIndex: 1)
        ]

        XCTAssertTrue(MeetingSpeakerRenaming.isTaken("说话人 1", by: speakers[1], among: speakers))
        XCTAssertFalse(
            MeetingSpeakerRenaming.isTaken("王强", by: speakers[1], among: speakers),
            "没被用过的名字可以改"
        )
        XCTAssertFalse(
            MeetingSpeakerRenaming.isTaken("说话人 2", by: speakers[1], among: speakers),
            "改回自己的名字不算被占用"
        )
    }

    private func sampleSummary() -> MeetingSummary {
        let evidence = MeetingEvidence(segmentID: UUID(), startMs: 0, endMs: 1000, quote: "原文")
        return MeetingSummary(
            overview: "概要",
            keyPoints: [],
            decisions: [],
            actionItems: [
                MeetingActionItem(task: "发文档", owner: "", evidence: [evidence]),
                MeetingActionItem(task: "排期", owner: "", evidence: [evidence])
            ],
            openQuestions: []
        )
    }
}
