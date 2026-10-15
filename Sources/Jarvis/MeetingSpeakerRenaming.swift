import Foundation

/// Keeping the minutes in step with a speaker's name.
///
/// The minutes name their owner rather than pointing at a speaker, so renaming one has to
/// follow through to the action items. That is only safe while the old name meant exactly
/// one person: with two speakers sharing a name, an item under that name may belong to
/// either of them, and moving it would be a guess.
enum MeetingSpeakerRenaming {
    static func isUnambiguous(_ name: String, among speakers: [MeetingSpeaker]) -> Bool {
        speakers.count { $0.name == name } == 1
    }

    static func isTaken(_ name: String, by otherThan: MeetingSpeaker, among speakers: [MeetingSpeaker]) -> Bool {
        speakers.contains { $0.id != otherThan.id && $0.name == name }
    }

    static func relabeling(_ summary: MeetingSummary, from oldName: String, to newName: String) -> MeetingSummary {
        var renamed = summary
        guard !oldName.isEmpty, oldName != newName else { return renamed }

        renamed.overview = replacingSpeakerName(in: renamed.overview, from: oldName, to: newName)
        for index in renamed.points.indices {
            renamed.points[index].title = replacingSpeakerName(
                in: renamed.points[index].title,
                from: oldName,
                to: newName
            )
            renamed.points[index].detail = replacingSpeakerName(
                in: renamed.points[index].detail,
                from: oldName,
                to: newName
            )
        }
        for index in renamed.actionItems.indices {
            renamed.actionItems[index].task = replacingSpeakerName(
                in: renamed.actionItems[index].task,
                from: oldName,
                to: newName
            )
            if renamed.actionItems[index].owner == oldName {
                renamed.actionItems[index].owner = newName
            }
        }
        return renamed
    }

    private static func replacingSpeakerName(in text: String, from oldName: String, to newName: String) -> String {
        text.replacingOccurrences(of: oldName, with: newName)
    }
}
