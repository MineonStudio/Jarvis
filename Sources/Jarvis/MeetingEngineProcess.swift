import Foundation

/// Private, local NDJSON transport. No network listener or AI credentials enter the engine.
final class MeetingEngineJob: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let executable: URL
    init(executable: URL = MeetingEnginePaths.executable) {
        self.executable = executable
    }

    private let input = Pipe()
    private var cancelled = false
    private var finished = false

    func finish(keepDuration: Double? = nil) {
        lock.withLock {
            guard !finished else { return }
            finished = true
            try? input.fileHandleForWriting.write(contentsOf: Data((keepDuration.map { "finish \($0)\n" } ?? "finish\n").utf8))
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning {
                process.terminate()
            }
        }
    }

    func run(
        _ arguments: [String],
        onEvent: @escaping @Sendable (MeetingEngineEvent) -> Void = { _ in }
    ) async throws -> MeetingEngineEvent {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                let output = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.standardError
                try lock.withLock {
                    if cancelled {
                        throw CancellationError()
                    }
                    try process.run()
                }
                var pending = Data()
                var result: MeetingEngineEvent?
                var failure: String?
                while true {
                    let data = output.fileHandleForReading.availableData
                    if data.isEmpty {
                        break
                    }
                    pending.append(data)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = pending.prefix(upTo: newline)
                        pending.removeSubrange(...newline)
                        guard let event = try? JSONDecoder().decode(MeetingEngineEvent.self, from: line) else { continue }
                        if event.type == "error" {
                            failure = event.message
                        }
                        if event.type == "result" || event.type == "ready" {
                            result = event
                        }
                        onEvent(event)
                    }
                }
                process.waitUntilExit()
                try input.fileHandleForWriting.close()
                try output.fileHandleForReading.close()
                if lock.withLock({ cancelled }) {
                    throw CancellationError()
                }
                guard process.terminationStatus == 0, let result else {
                    throw MeetingEngineError.failed(failure ?? "本地会议引擎意外退出，录音已保留，可重试处理。")
                }
                return result
            }.value
        } onCancel: { self.cancel() }
    }
}

struct MeetingEngineEvent: Decodable, Sendable {
    var type: String
    var progress: Double?
    var completed: Int64?
    var total: Int64?
    var message: String?
    var lines: [MeetingLiveLine]?
    var transcript: MeetingEngineTranscript?
}

struct MeetingLiveLine: Decodable, Identifiable, Sendable {
    var start_ms: UInt64
    var text: String
    var id: UInt64 {
        start_ms
    }
}

struct MeetingEngineTranscript: Decodable, Sendable {
    struct Sentence: Decodable, Sendable {
        var speaker: Int
        var start_ms: UInt64
        var end_ms: UInt64
        var text: String
    }

    var duration_ms: UInt64
    var sentences: [Sentence]

    func result() -> MeetingTranscriptionResult {
        var ids: [Int] = []
        for s in sentences where !ids.contains(s.speaker) {
            ids.append(s.speaker)
        }
        let speakers = ids.enumerated().map { index, id in
            MeetingSpeaker(id: "campplus:\(id)", name: "说话人 \(index + 1)", colorIndex: index)
        }
        let segments = sentences.compactMap { s -> MeetingTranscriptSegment? in
            guard s.end_ms >= s.start_ms, !s.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return MeetingTranscriptSegment(
                startTime: Double(s.start_ms) / 1000,
                endTime: Double(s.end_ms) / 1000,
                speakerID: "campplus:\(s.speaker)", text: s.text
            )
        }
        return MeetingTranscriptionResult(speakers: speakers, segments: segments, estimatedSpeakerCount: speakers.count, uncertainSegmentRatio: 0)
    }
}

enum MeetingEngineError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case let .failed(message) = self {
            message
        } else {
            nil
        }
    }
}

enum MeetingEnginePaths {
    static var executable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/jarvis-meeting-engine")
    }

    static var models: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(JarvisAppIdentity.dataDirectoryName)
            .appendingPathComponent("Meetings/Models/Paraformer-large", isDirectory: true)
    }
}

enum MeetingModelDownloadMeter {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var values: (Int64, Int64) = (0, 0)
    static func update(completed: Int64, total: Int64) {
        lock.withLock { values = (completed, total) }
    }

    static func snapshot() -> (completed: Int64, total: Int64) {
        lock.withLock { values }
    }
}
