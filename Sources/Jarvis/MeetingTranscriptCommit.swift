import Foundation

/// Replace the transcript only with a complete, nonempty engine result. Preserve the
/// previous minutes as a version before a new transcript invalidates their references.
enum MeetingTranscriptCommit {
    static func applying(_ result: MeetingTranscriptionResult, to record: MeetingRecord) throws -> MeetingRecord {
        guard !result.segments.isEmpty else {
            throw MeetingEngineError.failed("未识别到有效语音，已有录音和文字记录已保留。")
        }
        var updated = record
        updated.speakers = result.speakers
        updated.transcript = result.segments
        updated.diarizationDegraded = result.diarizationDegraded
        updated.diarizationDegradeReason = result.diarizationDegradeReason
        updated.estimatedSpeakerCount = result.estimatedSpeakerCount
        updated.uncertainSegmentRatio = result.uncertainSegmentRatio
        updated.errorMessage = result.diarizationDegraded ? "说话人分离没有完成，逐字稿仍可生成纪要。" : nil
        if let previous = updated.summary {
            updated.minutesVersions.append(MeetingMinutesVersion(summary: previous))
            updated.summary = nil
        }
        updated.summaryCheckpoint = nil
        updated.status = .transcribed
        return updated
    }
}
