import Foundation

enum MeetingSpeakerPreview {
    static func firstUtterances(in segments: [MeetingTranscriptSegment]) -> [String: MeetingTranscriptSegment] {
        var result: [String: MeetingTranscriptSegment] = [:]
        for segment in segments {
            guard !segment.speakerID.isEmpty, !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  segment.startTime.isFinite, segment.endTime.isFinite,
                  segment.startTime >= 0, segment.endTime > segment.startTime else { continue }
            if let earlier = result[segment.speakerID], earlier.startTime <= segment.startTime {
                continue
            }
            result[segment.speakerID] = segment
        }
        return result
    }

    static func range(for segment: MeetingTranscriptSegment, duration: Double) -> Range<Double>? {
        guard duration.isFinite, duration > 0, segment.startTime.isFinite, segment.endTime.isFinite else { return nil }
        let start = max(0, segment.startTime)
        let end = min(duration, segment.endTime)
        return end > start ? start ..< end : nil
    }
}
