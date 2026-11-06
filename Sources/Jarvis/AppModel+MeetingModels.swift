import Foundation

extension AppModel {
    var meetingModelsReady: Bool {
        meetingModelState.isReady
    }

    func refreshMeetingModelState() {
        guard meetingModelPreparationTask == nil,
              meetingModelAvailabilityTask == nil
        else { return }
        meetingModelAvailabilityTask = Task { @MainActor [weak self] in
            let stored = await Task.detached(priority: .utility) {
                MeetingModelStorage.availability()
            }.value
            let availability = stored
            guard let self,
                  !Task.isCancelled,
                  meetingModelPreparationTask == nil
            else { return }
            meetingModelAvailabilityTask = nil
            meetingModelAvailability = availability
            meetingModelState = availability.isReady ? .ready : .notReady(availability)
            updateMeetingMenuBarState()
        }
    }

    func prepareMeetingModels() {
        startMeetingModelPreparation(for: MeetingModelPreparationStage.allCases)
    }

    func prepareMeetingModel(_ stage: MeetingModelPreparationStage) {
        startMeetingModelPreparation(for: [stage])
    }

    private func startMeetingModelPreparation(for stages: [MeetingModelPreparationStage]) {
        guard canManageMeetingModels else { return }

        meetingModelAvailabilityTask?.cancel()
        meetingModelAvailabilityTask = nil
        meetingModelPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for stage in stages {
                guard !Task.isCancelled else { break }
                meetingModelState = .downloading(stage: stage, progress: 0.01)
                do {
                    try await meetingTranscriptionService.prepareModel(stage) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  case let .downloading(activeStage, _) = meetingModelState,
                                  activeStage == stage
                            else {
                                return
                            }
                            meetingModelState = .downloading(stage: stage, progress: progress)
                            let bytes = MeetingModelDownloadMeter.snapshot()
                            meetingModelDownloadCompletedBytes = bytes.completed
                            meetingModelDownloadTotalBytes = bytes.total
                        }
                    }
                    guard !Task.isCancelled else { break }
                } catch is CancellationError {
                    break
                } catch {
                    meetingModelPreparationTask = nil
                    meetingModelState = .failed(
                        stage: stage,
                        operation: .download,
                        message: error.localizedDescription
                    )
                    return
                }
            }

            meetingModelPreparationTask = nil
            meetingModelState = .checking
            refreshMeetingModelState()
        }
    }

    func removeMeetingModel(_ stage: MeetingModelPreparationStage) {
        guard canManageMeetingModels else { return }

        meetingModelState = .removing(stage)
        meetingModelPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await meetingTranscriptionService.removeModel(stage)
                meetingModelPreparationTask = nil
                meetingModelState = .checking
                refreshMeetingModelState()
            } catch {
                meetingModelPreparationTask = nil
                meetingModelState = .failed(
                    stage: stage,
                    operation: .remove,
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancelMeetingModelPreparation() {
        guard case .downloading = meetingModelState else { return }
        meetingModelPreparationTask?.cancel()
        meetingModelState = .checking
        refreshMeetingModelState()
    }
}
