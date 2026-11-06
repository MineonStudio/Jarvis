import Foundation

enum MeetingTitlePolicy {
    static func isManuallyNamed(_ title: String, createdAt: Date) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value != MeetingRecord.defaultTitle
            && !MeetingRecord.isLegacyGeneratedTitle(value, createdAt: createdAt)
    }

    static func canApply(to record: MeetingRecord, originalTitle: String, summary: MeetingSummary) -> Bool {
        !record.titleIsUserEdited && record.title == originalTitle && record.status == .ready && record.summary == summary
    }
}

extension MeetingRecord {
    @discardableResult
    mutating func setUserTitle(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.isEmpty ? Self.defaultTitle : value
        guard title != normalized else { return false }
        title = normalized
        titleIsUserEdited = normalized != Self.defaultTitle
        return true
    }
}
