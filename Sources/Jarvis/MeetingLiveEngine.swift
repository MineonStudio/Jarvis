import Foundation

@MainActor
final class MeetingLiveEngine {
    private let job = MeetingEngineJob()
    private var task: Task<MeetingEngineEvent, Error>?
    private var ready = false
    private var failure: String?
    var failureMessage: String? {
        failure
    }

    let directory: URL
    let mixedWAV: URL

    init(directory: URL) {
        self.directory = directory
        mixedWAV = directory.appendingPathComponent("mixed.wav")
    }

    func start(mode: MeetingCaptureMode, onLines: @escaping @MainActor @Sendable ([MeetingLiveLine]) -> Void) async throws {
        let sources = mode == .system ? ["system"] : mode == .microphone ? ["mic"] : ["system", "mic"]
        let arguments = ["live", MeetingEnginePaths.models.path, directory.path, mixedWAV.path] + sources
        task = Task { [job, weak self] in
            do { return try await job.run(arguments) { [weak self] event in
                Task { @MainActor [weak self] in
                    if event.type == "ready" {
                        self?.ready = true
                    }
                    if event.type == "error" {
                        self?.failure = event.message
                    }
                    if let lines = event.lines {
                        onLines(lines)
                    }
                }
            } } catch {
                self?.failure = error.localizedDescription
                throw error
            }
        }
        let deadline = Date().addingTimeInterval(30)
        while !ready {
            try Task.checkCancellation()
            if let failure {
                throw MeetingEngineError.failed(failure)
            }
            guard Date() < deadline else { cancel(); throw MeetingEngineError.failed("本地识别引擎启动超时，请重试。") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func finish(audioURL: URL, keepDuration: Double? = nil) async throws -> MeetingTranscriptionResult {
        guard let task else { throw MeetingEngineError.failed("识别任务尚未启动") }
        job.finish(keepDuration: keepDuration)
        let event = try await task.value
        guard let transcript = event.transcript else { throw MeetingEngineError.failed("未返回转写结果") }
        // Keep both source WAVs until the record and complete transcript are committed.
        try await MeetingAudioMixer.transcodeToM4A(inputURL: mixedWAV, outputURL: audioURL)
        return transcript.result()
    }

    func cancel() {
        job.cancel(); task?.cancel()
    }

    deinit { job.cancel() }

    static func recover(directory: URL, audioURL: URL) async throws -> MeetingTranscriptionResult {
        let mixed = directory.appendingPathComponent("mixed.wav")
        _ = try await MeetingEngineJob().run([
            "mix",
            directory.appendingPathComponent("system.wav").path,
            directory.appendingPathComponent("mic.wav").path,
            mixed.path
        ])
        let event = try await MeetingEngineJob().run(["transcribe", MeetingEnginePaths.models.path, mixed.path])
        guard let transcript = event.transcript else { throw MeetingEngineError.failed("录音恢复处理失败，原始文件已保留。") }
        try await MeetingAudioMixer.transcodeToM4A(inputURL: mixed, outputURL: audioURL)
        return transcript.result()
    }
}
