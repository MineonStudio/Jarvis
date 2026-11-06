import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func copyMeetingMinutes(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }) else { return }
        guard current.summary != nil else {
            showToast(JarvisFeedbackCopy.nothingToCopy)
            return
        }
        do {
            let copied = try MeetingMinutesClipboard.write(current, to: .general)
            showToast(copied ? JarvisFeedbackCopy.copied : "复制失败，请重试")
        } catch {
            showToast("复制失败，请重试")
        }
    }

    func exportMeetingPlainTranscript(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }),
              !current.transcript.isEmpty
        else {
            showToast(JarvisFeedbackCopy.nothingToExport)
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(current.title)-逐字稿.txt"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try current.plainTranscriptDocument().write(to: url, atomically: true, encoding: .utf8)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch {
                self?.showToast(JarvisFeedbackCopy.exportFailed)
            }
        }
    }

    func exportMeetingPDF(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }),
              current.summary != nil || !current.transcript.isEmpty
        else {
            showToast(JarvisFeedbackCopy.nothingToExport)
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(current.title).pdf"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try MeetingExport.pdfData(for: current).write(to: url)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch {
                self?.showToast(JarvisFeedbackCopy.exportFailed)
            }
        }
    }

    func exportMeetingMarkdown(_ record: MeetingRecord, includeTranscript: Bool = false) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }) else { return }
        guard current.summary != nil || (includeTranscript && !current.transcript.isEmpty) else {
            showToast(JarvisFeedbackCopy.nothingToExport)
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = includeTranscript
            ? "\(current.title)-完整记录.md"
            : "\(current.title).md"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try current.markdownDocument(includeTranscript: includeTranscript)
                    .write(to: url, atomically: true, encoding: .utf8)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch {
                self?.showToast(JarvisFeedbackCopy.exportFailed)
            }
        }
    }

    func deleteMeeting(_ record: MeetingRecord) {
        guard meetingCurrentRecordingID != record.id, !meetingFinalizingIDs.contains(record.id) else {
            showToast(JarvisFeedbackCopy.finishRecordingFirst)
            return
        }
        meetingProcessingQueue.removeAll { $0.recordID == record.id }
        let wasActive = meetingActiveProcessingID == record.id
        if wasActive {
            // #14：先取消任务，再同步清掉 active 标记。被取消任务的 defer
            // （completeActiveMeetingProcessing）稍后才跑，会因 guard 直接 no-op，
            // 不会把我们下面推进的状态覆盖掉。
            meetingProcessingTask?.cancel()
            meetingProcessingTask = nil
            meetingActiveProcessingID = nil
        }
        // #14：删的是正在处理的会议时，队列里有排队就起下一个，空了就回 .idle——
        // 以前这里只在 !wasActive 时回 idle，删正在处理的会议会让状态永远卡在 .processing。
        defer {
            if wasActive {
                startNextMeetingProcessingIfNeeded()
            }
            if meetingActiveProcessingID == nil {
                meetingProcessingState = .idle
            }
        }
        do {
            try meetingRepository.delete(record)
            cancelMeetingTitleGeneration(record.id)
            meetingRecords.removeAll { $0.id == record.id }
            // Per-meeting state that lives outside the records goes with it.
            meetingLiveSummaries[record.id] = nil
            meetingAudioRevisions[record.id] = nil
            if selectedMeetingID == record.id {
                selectedMeetingID = meetingRecords.first?.id
            }
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "meeting.delete.failed",
                error: error,
                fields: ["meetingID": record.id.uuidString]
            )
            showToast(JarvisFeedbackCopy.deleteFailed)
        }
    }

    func meetingAudioURL(for record: MeetingRecord) -> URL? {
        try? meetingRepository.audioURL(for: record)
    }

    func updateMeetingTitle(recordID: UUID, title: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        guard meetingRecords[index].setUserTitle(title) else { return }
        cancelMeetingTitleGeneration(recordID)
        persistMeeting(meetingRecords[index])
    }

    func setMeetingActionItemCompleted(
        recordID: UUID,
        actionItemID: UUID,
        isCompleted: Bool
    ) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary,
              let itemIndex = summary.actionItems.firstIndex(where: { $0.id == actionItemID })
        else { return }
        summary.actionItems[itemIndex].isCompleted = isCompleted
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func updateMeetingOverview(recordID: UUID, overview: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary
        else { return }
        summary.overview = overview
        summary.overviewIsUserEdited = true
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func updateMeetingPoint(recordID: UUID, pointID: String, title: String, detail: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary,
              let pointIndex = summary.points.firstIndex(where: { $0.id == pointID })
        else { return }
        summary.points[pointIndex].title = title
        summary.points[pointIndex].detail = detail
        summary.points[pointIndex].isUserEdited = true
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func updateMeetingActionItemText(recordID: UUID, actionItemID: UUID, task: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary,
              let itemIndex = summary.actionItems.firstIndex(where: { $0.id == actionItemID })
        else { return }
        summary.actionItems[itemIndex].task = task
        summary.actionItems[itemIndex].isUserEdited = true
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func renameMeetingSpeaker(recordID: UUID, speakerID: String, name: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let speakerIndex = meetingRecords[index].speakers.firstIndex(where: { $0.id == speakerID })
        else { return }
        let oldName = meetingRecords[index].speakers[speakerIndex].name
        guard oldName != trimmed else { return }
        let shouldRelabelOwner = MeetingSpeakerRenaming.isUnambiguous(
            oldName,
            among: meetingRecords[index].speakers
        )
        meetingRecords[index].speakers[speakerIndex].name = trimmed
        if shouldRelabelOwner, let summary = meetingRecords[index].summary {
            meetingRecords[index].summary = MeetingSpeakerRenaming.relabeling(
                summary,
                from: oldName,
                to: trimmed
            )
        }
        if shouldRelabelOwner, let liveSummary = meetingLiveSummaries[recordID] {
            meetingLiveSummaries[recordID] = MeetingSpeakerRenaming.relabeling(
                liveSummary,
                from: oldName,
                to: trimmed
            )
        }
        if persistMeeting(meetingRecords[index]) {
            showToast("说话人名称已保存")
        }
    }

    func mergeMeetingSpeakers(recordID: UUID, sourceSpeakerID: String, into targetSpeakerID: String) {
        guard sourceSpeakerID != targetSpeakerID,
              let recordIndex = meetingRecords.firstIndex(where: { $0.id == recordID }),
              let sourceIndex = meetingRecords[recordIndex].speakers.firstIndex(where: { $0.id == sourceSpeakerID }),
              let target = meetingRecords[recordIndex].speakers.first(where: { $0.id == targetSpeakerID })
        else { return }

        let source = meetingRecords[recordIndex].speakers[sourceIndex]
        let shouldRelabelSummary = MeetingSpeakerRenaming.isUnambiguous(
            source.name,
            among: meetingRecords[recordIndex].speakers
        )
        var movedSegmentCount = 0
        for segmentIndex in meetingRecords[recordIndex].transcript.indices
            where meetingRecords[recordIndex].transcript[segmentIndex].speakerID == sourceSpeakerID
        {
            meetingRecords[recordIndex].transcript[segmentIndex].speakerID = targetSpeakerID
            movedSegmentCount += 1
        }
        meetingRecords[recordIndex].speakers.remove(at: sourceIndex)
        meetingRecords[recordIndex].estimatedSpeakerCount = meetingRecords[recordIndex].speakers.count

        if shouldRelabelSummary, let summary = meetingRecords[recordIndex].summary {
            meetingRecords[recordIndex].summary = MeetingSpeakerRenaming.relabeling(
                summary,
                from: source.name,
                to: target.name
            )
        }
        if shouldRelabelSummary, let liveSummary = meetingLiveSummaries[recordID] {
            meetingLiveSummaries[recordID] = MeetingSpeakerRenaming.relabeling(
                liveSummary,
                from: source.name,
                to: target.name
            )
        }

        if persistMeeting(meetingRecords[recordIndex]) {
            showToast("已合并说话人，(movedSegmentCount) 段转写归入「\(target.name)」")
        }
    }

    func restoreMeetingMinutesVersion(recordID: UUID, versionID: UUID) {
        ensureMeetingDetailLoaded(recordID)
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              let versionIndex = meetingRecords[index].minutesVersions.firstIndex(where: { $0.id == versionID })
        else { return }
        let version = meetingRecords[index].minutesVersions[versionIndex]
        if let current = meetingRecords[index].summary {
            meetingRecords[index].minutesVersions.append(MeetingMinutesVersion(summary: current))
        }
        meetingRecords[index].minutesVersions.removeAll { $0.id == versionID }
        meetingRecords[index].summary = version.summary
        meetingRecords[index].status = .ready
        meetingRecords[index].summaryCheckpoint = nil
        meetingRecords[index].errorMessage = nil
        persistMeeting(meetingRecords[index])
    }

    func createMeetingPlaceholder() {
        let id = UUID()
        let urls = meetingRepository.recordingURLs(for: id)
        let record = MeetingRecord(
            id: id,
            title: MeetingRecord.defaultTitle,
            audioFileName: urls.mixed.lastPathComponent,
            status: .failed,
            errorMessage: "识别资源还没准备好，这条会议先占着。资源下载完成后可以开始录音。",
            awaitingAssets: true
        )
        do {
            try meetingRepository.save(record)
            meetingRecords.insert(record, at: 0)
            selectedMeetingID = id
        } catch {
            showToast(JarvisFeedbackCopy.saveFailed)
        }
    }

    func postponeMeetingAssetDownload() {
        cancelMeetingModelPreparation()
        if !meetingRecords.contains(where: { $0.awaitingAssets == true }) {
            createMeetingPlaceholder()
        }
        showToast("资源稍后再准备。占位会议还不能录音。")
    }
}
