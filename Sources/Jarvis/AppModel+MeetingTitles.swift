import Foundation

extension AppModel {
    func cancelMeetingTitleGeneration(_ recordID: UUID) {
        meetingTitleTasks.removeValue(forKey: recordID)?.cancel()
        meetingTitleGenerationIDs[recordID] = nil
    }

    func generateMeetingTitle(recordID: UUID, summary: MeetingSummary, configuration: AIAPIConfiguration) {
        cancelMeetingTitleGeneration(recordID)
        guard let record = meetingRecords.first(where: { $0.id == recordID }), !record.titleIsUserEdited else { return }
        let originalTitle = record.title
        let generationID = UUID()
        let api = aiTextCompletionAPI
        meetingTitleGenerationIDs[recordID] = generationID
        meetingTitleTasks[recordID] = Task { @MainActor [weak self] in
            defer {
                if let self, self.meetingTitleGenerationIDs[recordID] == generationID {
                    self.meetingTitleTasks[recordID] = nil
                    self.meetingTitleGenerationIDs[recordID] = nil
                }
            }
            do {
                let title = try await MeetingTitleService(api: api).generate(from: summary, configuration: configuration)
                try Task.checkCancellation()
                guard let self, self.meetingTitleGenerationIDs[recordID] == generationID,
                      let index = self.meetingRecords.firstIndex(where: { $0.id == recordID }),
                      MeetingTitlePolicy.canApply(to: self.meetingRecords[index], originalTitle: originalTitle, summary: summary)
                else { return }
                self.meetingRecords[index].title = title
                self.persistMeeting(self.meetingRecords[index])
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Minutes have already succeeded; a failed title never invalidates them.
                JarvisLog.error(
                    category: .meeting,
                    event: "meeting.title.failed",
                    error: error,
                    fields: ["meetingID": recordID.uuidString]
                )
            }
        }
    }
}
