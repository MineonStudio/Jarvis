import AVFoundation
import Foundation
@testable import Jarvis
import XCTest

final class MeetingEngineTests: XCTestCase {
    func testEngineTranscriptKeepsGlobalSpeakerIDsAndMillisecondTimes() throws {
        let json = #"{"duration_ms":12000,"sentences":[{"speaker":3,"start_ms":1250,"end_ms":2500,"text":"先确认范围。"},{"speaker":7,"start_ms":3000,"end_ms":4200,"text":"我来处理。"},{"speaker":3,"start_ms":5000,"end_ms":6200,"text":"周五交付。"}]}"#
        let transcript = try JSONDecoder().decode(MeetingEngineTranscript.self, from: Data(json.utf8))
        let result = transcript.result()
        XCTAssertEqual(result.speakers.map(\.name), ["说话人 1", "说话人 2"])
        XCTAssertEqual(result.segments[0].speakerID, result.segments[2].speakerID)
        XCTAssertNotEqual(result.segments[0].speakerID, result.segments[1].speakerID)
        XCTAssertEqual(result.segments[0].startTime, 1.25)
        XCTAssertEqual(result.segments[0].endTime, 2.5)
        XCTAssertFalse(result.diarizationDegraded)
    }

    func testGrowingWAVCanBeReadBeforeWriterClosesAndAfterSecondAppend() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-growing-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MeetingWAVWriter(url: url)
        try writer.append(Data(repeating: 0, count: 32000))
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 16000)
        try writer.append(Data(repeating: 0, count: 16000))
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 24000)
        XCTAssertEqual(try AVAudioFile(forReading: url).processingFormat.sampleRate, 16000)
    }

    func testEngineTransportReadsReadyThenFinishResult() async throws {
        let job = MeetingEngineJob(executable: URL(fileURLWithPath: "/bin/sh"))
        job.finish()
        let result = try await job.run(["-c", "printf '%s\\n' '{\"type\":\"ready\"}'; read command; printf '%s\\n' '{\"type\":\"result\",\"transcript\":{\"duration_ms\":0,\"sentences\":[]}}'"])
        XCTAssertEqual(result.type, "result")
        XCTAssertEqual(result.transcript?.sentences.count, 0)
    }

    func testEngineTransportRejectsFailedJobEvenAfterReady() async throws {
        let job = MeetingEngineJob(executable: URL(fileURLWithPath: "/bin/sh"))
        do {
            _ = try await job.run(["-c", "printf '%s\\n' '{\"type\":\"ready\"}' '{\"type\":\"error\",\"message\":\"模型不完整\"}'; exit 1"])
            XCTFail("An early ready event cannot hide a later worker failure")
        } catch { XCTAssertEqual(error.localizedDescription, "模型不完整") }
    }

    func testCancellingEngineTerminatesChild() async throws {
        let job = MeetingEngineJob(executable: URL(fileURLWithPath: "/bin/sleep"))
        let task = Task { try await job.run(["10"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testReplacementArchivesMinutesAndRejectsEmptyTranscription() throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "old", text: "原始逐字稿")
        let oldSummary = MeetingSummary(overview: "旧纪要", actionItems: [])
        let record = MeetingRecord(title: "保留数据", audioFileName: "meeting-test.m4a", transcript: [segment], summary: oldSummary)
        let empty = MeetingTranscriptionResult(speakers: [], segments: [])
        XCTAssertThrowsError(try MeetingTranscriptCommit.applying(empty, to: record))
        XCTAssertEqual(record.transcript, [segment])
        XCTAssertEqual(record.summary, oldSummary)

        let replacement = MeetingTranscriptSegment(startTime: 0, endTime: 2, speakerID: "new", text: "重新识别的内容")
        let committed = try MeetingTranscriptCommit.applying(MeetingTranscriptionResult(speakers: [], segments: [replacement]), to: record)
        XCTAssertEqual(committed.transcript, [replacement])
        XCTAssertNil(committed.summary)
        XCTAssertEqual(committed.minutesVersions.map(\.summary), [oldSummary])
    }

    func testSubtitleExportPreservesHourAndMillisecondBoundaries() {
        let record = MeetingRecord(title: "字幕", audioFileName: "meeting-test.m4a", speakers: [MeetingSpeaker(id: "1", name: "小王", colorIndex: 0)], transcript: [MeetingTranscriptSegment(startTime: 3600.125, endTime: 3601.875, speakerID: "1", text: "确认上线。")])
        let srt = MeetingSubtitleExport.srt(record)
        XCTAssertTrue(srt.contains("01:00:00,125 --> 01:00:01,875"))
        XCTAssertTrue(srt.contains("小王：确认上线。"))
    }
}
