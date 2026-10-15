import Foundation

/// How the transcript goes into the prompt, and how the model's references come back.
///
/// Segment ids are shortened to `S1`, `S2`… and timestamps are left out of the transcript
/// entirely: the model only has to point at a segment, and the app reads the times, the
/// speaker and the quoted words out of that segment locally. On a two-hour meeting this
/// removes tens of thousands of characters from every request — including every retry.
enum MeetingTranscriptFormat {
    static func shortID(forSegmentAt index: Int) -> String {
        "S\(index + 1)"
    }

    static func line(_ segment: MeetingTranscriptSegment, speaker: String, shortID: String) -> String {
        "[\(shortID)] \(speaker)：\(segment.text)"
    }

    static func render(
        segments: [MeetingTranscriptSegment],
        speakerNames: [String: String],
        shortIDs: [UUID: String]
    ) -> String {
        segments.map { segment in
            line(
                segment,
                speaker: speakerNames[segment.speakerID] ?? segment.speakerID,
                shortID: shortIDs[segment.id] ?? "S?"
            )
        }.joined(separator: "\n")
    }

    /// Rough token count. CJK is about one token per character, everything else about a
    /// quarter as much. Only used to decide whether a request fits, never to bill anything.
    static func estimateTokens(_ text: String) -> Int {
        var cjkCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            if isCJK(scalar) {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }
        return cjkCount + Int(ceil(Double(otherCount) / 4))
    }

    static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return (0x3400 ... 0x4DBF).contains(value)
            || (0x4E00 ... 0x9FFF).contains(value)
            || (0xF900 ... 0xFAFF).contains(value)
    }

    /// Splits rendered transcript lines into windows that fit a token budget.
    ///
    /// A normal meeting fits in one window and nothing is split at all. When it does not,
    /// lines are halved until each piece fits, and a single line too long to fit on its own
    /// is cut by text. Splitting is a fallback for small-context models, not the default path.
    static func windows(forLines lines: [String], budget: Int) -> [TranscriptWindow] {
        guard !lines.isEmpty else { return [] }
        guard lines.count > 1 else {
            return splitText(lines[0], budget: budget)
        }
        let whole = TranscriptWindow(text: lines.joined(separator: "\n"))
        guard whole.estimatedTokens > budget else { return [whole] }
        let middle = lines.count / 2
        return windows(forLines: Array(lines[..<middle]), budget: budget)
            + windows(forLines: Array(lines[middle...]), budget: budget)
    }

    /// Cuts one window in half, by lines when there are several and by text when there is not.
    static func split(_ window: TranscriptWindow) -> [TranscriptWindow] {
        let lines = window.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.count > 1 else {
            return splitText(window.text, budget: max(1, window.estimatedTokens / 2))
        }
        let middle = lines.count / 2
        return [
            TranscriptWindow(text: lines[..<middle].joined(separator: "\n")),
            TranscriptWindow(text: lines[middle...].joined(separator: "\n"))
        ]
    }

    private static func splitText(_ text: String, budget: Int) -> [TranscriptWindow] {
        guard estimateTokens(text) > budget, text.count > 1 else {
            return [TranscriptWindow(text: text)]
        }
        let characters = Array(text)
        let middle = characters.count / 2
        return splitText(String(characters[..<middle]), budget: budget)
            + splitText(String(characters[middle...]), budget: budget)
    }
}

struct TranscriptWindow: Sendable, Equatable {
    var text: String
    var estimatedTokens: Int

    init(text: String) {
        self.text = text
        estimatedTokens = MeetingTranscriptFormat.estimateTokens(text)
    }
}

/// Short id ↔ segment, so a point can be validated the moment it arrives and a model that
/// answers with a raw UUID (an older prompt, a resumed run) still resolves.
struct TranscriptIndex: Sendable {
    private var byShortID: [String: MeetingTranscriptSegment]
    private var byUUID: [String: MeetingTranscriptSegment]
    let shortIDs: [UUID: String]

    init(transcript: [MeetingTranscriptSegment]) {
        var byShortID: [String: MeetingTranscriptSegment] = [:]
        var byUUID: [String: MeetingTranscriptSegment] = [:]
        var shortIDs: [UUID: String] = [:]
        for (index, segment) in transcript.enumerated() {
            let shortID = MeetingTranscriptFormat.shortID(forSegmentAt: index)
            byShortID[shortID] = segment
            byShortID[shortID.lowercased()] = segment
            byUUID[segment.id.uuidString] = segment
            shortIDs[segment.id] = shortID
        }
        self.byShortID = byShortID
        self.byUUID = byUUID
        self.shortIDs = shortIDs
    }

    func segment(for rawID: String) -> MeetingTranscriptSegment? {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return byShortID[trimmed] ?? byShortID[trimmed.lowercased()] ?? byUUID[trimmed.uppercased()]
    }

    func shortID(for segment: MeetingTranscriptSegment) -> String? {
        shortIDs[segment.id]
    }
}
