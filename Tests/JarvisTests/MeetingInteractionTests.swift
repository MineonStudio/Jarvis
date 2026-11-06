import AppKit
import AVFoundation
@testable import Jarvis
import XCTest

@MainActor
final class MeetingInteractionTests: XCTestCase {
    func testSpeakerPreviewPausesAtEndAndSwitchingCancelsPreviousStop() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speaker-preview-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000))
        buffer.frameLength = 32000
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0 ..< 32000 {
            channel[index] = 0
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let playback = MeetingPlayback()
        defer { playback.stop() }
        playback.load(url)
        XCTAssertTrue(playback.available)
        let first = MeetingTranscriptSegment(startTime: 0.05, endTime: 0.15, speakerID: "S1", text: "第一位")
        let second = MeetingTranscriptSegment(startTime: 0.3, endTime: 0.8, speakerID: "S2", text: "第二位")
        playback.toggleSpeakerPreview("S1", first)
        guard playback.isPlaying else { throw XCTSkip("当前测试环境没有可用音频输出") }
        XCTAssertTrue(playback.isPreviewingSpeaker("S1"))
        playback.toggleSpeakerPreview("S2", second)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(playback.isPreviewingSpeaker("S2"), "The first speaker's stop must not pause the second preview")
        XCTAssertFalse(playback.isPlayingSource(at: second.startTime))
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertNil(playback.previewSpeakerID)
        XCTAssertEqual(playback.position, 0.8, accuracy: 0.03)
    }

    func testCopyMinutesProvidesRichTextAndPlainFallbackWithoutMarkdownSyntax() throws {
        let record = MeetingRecord(
            title: "研发 & 评审", audioFileName: "sample.m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "小王", colorIndex: 0)],
            transcript: [MeetingTranscriptSegment(startTime: 0, endTime: 2, speakerID: "S1", text: "逐字稿不应被复制")],
            summary: MeetingSummary(
                overview: "确认了交付范围。",
                actionItems: [MeetingActionItem(task: "发送方案", owner: "小王")],
                points: [MeetingDiscussionPoint(id: "P1", title: "发布决议", detail: "先完成评审。", evidence: [])]
            )
        )
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(try MeetingMinutesClipboard.write(record, to: pasteboard))
        let rtf = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let html = try XCTUnwrap(pasteboard.data(forType: .html))
        XCTAssertFalse(html.isEmpty)
        let rich = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        let plain = try XCTUnwrap(pasteboard.string(forType: .string))
        for value in [record.title, "会议纪要", "确认了交付范围。", "发布决议", "先完成评审。", "发送方案", "负责人：小王"] {
            XCTAssertTrue(rich.string.contains(value))
            XCTAssertTrue(plain.contains(value))
        }
        XCTAssertFalse(plain.contains("# "))
        XCTAssertFalse(plain.contains("**"))
        XCTAssertFalse(plain.contains("- [ ]"))
        XCTAssertFalse(plain.contains("逐字稿不应被复制"))
        let titleFont = try XCTUnwrap(rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let bodyLocation = (rich.string as NSString).range(of: "确认了交付范围。").location
        let bodyFont = try XCTUnwrap(rich.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
    }

    func testSpeakerPreviewUsesEarliestValidUtteranceRegardlessOfTranscriptOrder() {
        let early = MeetingTranscriptSegment(startTime: 4, endTime: 7, speakerID: "S1", text: "首次发言")
        let segments = [
            MeetingTranscriptSegment(startTime: 20, endTime: 30, speakerID: "S1", text: "后面的发言"),
            MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "  "),
            MeetingTranscriptSegment(startTime: 1, endTime: 1, speakerID: "S1", text: "无时长"),
            MeetingTranscriptSegment(startTime: .nan, endTime: 3, speakerID: "S1", text: "无效时间"),
            MeetingTranscriptSegment(startTime: 2, endTime: 3, speakerID: "S2", text: "另一位"),
            early
        ]
        let first = MeetingSpeakerPreview.firstUtterances(in: segments)
        XCTAssertEqual(first["S1"]?.id, early.id)
        XCTAssertEqual(first["S2"]?.startTime, 2)
        XCTAssertNil(first["unknown"])
    }

    func testSpeakerPreviewStopsAtUtteranceEndAndClampsToAvailableAudio() {
        let segment = MeetingTranscriptSegment(startTime: 4, endTime: 9, speakerID: "S1", text: "首次发言")
        XCTAssertEqual(MeetingSpeakerPreview.range(for: segment, duration: 30), 4 ..< 9)
        XCTAssertEqual(MeetingSpeakerPreview.range(for: segment, duration: 7), 4 ..< 7)
        XCTAssertNil(MeetingSpeakerPreview.range(for: segment, duration: 3))
        XCTAssertNil(MeetingSpeakerPreview.range(for: segment, duration: .nan))
    }
}
