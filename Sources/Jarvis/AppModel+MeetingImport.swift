import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func importMeetingAudio() {
        guard !meetingImportInProgress else { return }
        guard meetingModelsReady else { showToast("请先下载 Paraformer-large 识别资源"); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "导入会议录音或录屏，文件将复制到 Jarvis 中处理。"
        panel.begin { [weak self] response in
            guard response == .OK, let source = panel.url, let self else { return }
            let id = UUID()
            let title = source.deletingPathExtension().lastPathComponent
            let output = self.meetingRepository.recordingURLs(for: id).mixed
            Task { @MainActor [weak self] in
                guard let self else { return }
                meetingImportInProgress = true
                defer { meetingImportInProgress = false }
                showToast("正在导入录音…")
                let access = source.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        source.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    try await MeetingAudioMixer.transcodeToM4A(inputURL: source, outputURL: output)
                    let duration = await MeetingAudioAssembler.playableDuration(at: output) ?? 0
                    let record = MeetingRecord(
                        id: id,
                        title: title,
                        createdAt: Date(),
                        duration: duration,
                        audioFileName: output.lastPathComponent,
                        status: .transcribing,
                        captureMode: .microphone,
                        titleIsUserEdited: false
                    )
                    try meetingRepository.save(record)
                    meetingRecords.insert(record, at: 0)
                    selectedMeetingID = id
                    retryMeetingProcessing(record)
                } catch {
                    try? FileManager.default.removeItem(at: output)
                    showToast("导入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func retranscribeMeeting(_ record: MeetingRecord) {
        guard meetingRecords.contains(where: { $0.id == record.id }), meetingActiveProcessingID == nil, !meetingFinalizingIDs.contains(record.id) else { return }
        ensureMeetingDetailLoaded(record.id)
        // Keep the previous transcript until a replacement has actually succeeded.
        enqueueMeetingProcessing(recordID: record.id, kind: .transcribeAndSummarize, preserveUserEdits: false)
    }

    func exportMeetingSRT(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }), !current.transcript.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(current.title).srt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try MeetingSubtitleExport.srt(current).write(to: url, atomically: true, encoding: .utf8)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch { self?.showToast(JarvisFeedbackCopy.exportFailed) }
        }
    }
}

enum MeetingSubtitleExport {
    static func srt(_ record: MeetingRecord) -> String {
        record.transcript.enumerated().map { index, segment in
            let name = record.speakers.first { $0.id == segment.speakerID }?.name ?? "未标注"
            return "\(index + 1)\n\(timestamp(segment.startTime)) --> \(timestamp(segment.endTime))\n\(name)：\(segment.text)\n"
        }.joined(separator: "\n")
    }

    private static func timestamp(_ time: Double) -> String {
        let ms = max(0, Int((time * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
