import Foundation

/// One incremental piece of an OpenAI-compatible chat completion stream.
/// `reasoning` is optional on the wire: providers that do not emit it simply never send one.
enum AIStreamEvent: Equatable, Sendable {
    case reasoning(String)
    case content(String)
}

/// How long a streaming request may stay silent before the client gives up.
///
/// The first token gets its own, larger allowance because a slow model may spend a long
/// time thinking before it emits anything; once tokens are flowing, a gap means the
/// connection is dead rather than slow.
struct AIStreamingPolicy: Equatable, Sendable {
    static let hedgeEnabledKey = "jarvis.ai.stream.hedge"
    static let defaultHedgeDelay: TimeInterval = 12
    static let minimumHedgeDelay: TimeInterval = 8
    static let maximumHedgeDelay: TimeInterval = 45

    /// Sends a duplicate request when the first one stays silent, and keeps whichever
    /// answers first. Only ever fires before any token arrives, so a working request is
    /// never duplicated.
    var hedgingEnabled: Bool
    var hedgeDelay: TimeInterval
    /// Silence allowed before the first token.
    var firstDeltaTimeout: TimeInterval
    /// Silence allowed between tokens.
    var idleTimeout: TimeInterval
    /// Hard ceiling for one request, however chatty it is. Generous on purpose: a long
    /// meeting on a slow model is not a fault, and a request that has gone quiet is already
    /// caught by the idle allowances above.
    var totalTimeout: TimeInterval

    static let `default` = Self(
        hedgingEnabled: true,
        hedgeDelay: defaultHedgeDelay,
        firstDeltaTimeout: 60,
        idleTimeout: 25,
        totalTimeout: 1800
    )

    static func load(
        defaults: UserDefaults = .standard,
        configuration: AIAPIConfiguration,
        history: AIStreamingLatencyHistory = .shared
    ) -> Self {
        var policy = Self.default
        if defaults.object(forKey: hedgeEnabledKey) != nil {
            policy.hedgingEnabled = defaults.bool(forKey: hedgeEnabledKey)
        }
        policy.hedgeDelay = history.suggestedHedgeDelay(for: configuration)
        return policy
    }
}

/// Remembers how long a provider took to produce its first token, so the hedge delay
/// follows whatever model the user picked instead of a number tuned for one of them.
final class AIStreamingLatencyHistory: @unchecked Sendable {
    static let shared = AIStreamingLatencyHistory()

    private static let key = "jarvis.ai.stream.first-token-samples"
    private static let sampleLimit = 8

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var samples: [String: [Double]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: [Double]]
        samples = stored ?? [:]
    }

    func record(firstTokenSeconds: TimeInterval, configuration: AIAPIConfiguration) {
        guard firstTokenSeconds.isFinite, firstTokenSeconds >= 0 else { return }
        let key = Self.identifier(for: configuration)
        lock.lock()
        defer { lock.unlock() }
        var values = samples[key] ?? []
        values.append(firstTokenSeconds)
        if values.count > Self.sampleLimit {
            values.removeFirst(values.count - Self.sampleLimit)
        }
        samples[key] = values
        defaults.set(samples, forKey: Self.key)
    }

    func suggestedHedgeDelay(for configuration: AIAPIConfiguration) -> TimeInterval {
        lock.lock()
        let values = samples[Self.identifier(for: configuration)] ?? []
        lock.unlock()
        // One sample is noise; wait for a few before letting it move the delay.
        guard values.count >= 3 else { return AIStreamingPolicy.defaultHedgeDelay }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count) * 0.75).rounded(.up)) - 1)
        let p75 = sorted[max(index, 0)]
        return min(
            max(p75 * 2, AIStreamingPolicy.minimumHedgeDelay),
            AIStreamingPolicy.maximumHedgeDelay
        )
    }

    /// Which model a sample belongs to. The same model behind two endpoints is two entries.
    private static func identifier(for configuration: AIAPIConfiguration) -> String {
        "\(configuration.provider.rawValue)|\(configuration.model.lowercased())"
    }
}

/// Turns one server-sent-events line of a chat completion into incremental events.
///
/// Pure and synchronous on purpose: the transport feeds it line by line and tests feed it
/// from fixtures, including lines split across chunk boundaries.
struct SSEChatCompletionDecoder {
    private(set) var sawCompletion = false
    private(set) var sawAnyEvent = false

    mutating func feed(line: String) -> [AIStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Comments and keep-alives carry no data.
        guard trimmed.hasPrefix("data:") else { return [] }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return [] }
        if payload == "[DONE]" {
            sawCompletion = true
            return []
        }
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
        sawAnyEvent = true
        if let finishReason = (root["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String,
           !finishReason.isEmpty
        {
            sawCompletion = true
        }
        return Self.events(fromChunk: root)
    }

    private static func events(fromChunk root: [String: Any]) -> [AIStreamEvent] {
        guard let choices = root["choices"] as? [[String: Any]], !choices.isEmpty else { return [] }
        var events: [AIStreamEvent] = []
        for choice in choices {
            let payload = (choice["delta"] as? [String: Any]) ?? (choice["message"] as? [String: Any])
            guard let payload else { continue }
            // Providers spell the thinking channel differently; accept the common spellings.
            for key in ["reasoning_content", "reasoning"] {
                if let text = payload[key] as? String, !text.isEmpty {
                    events.append(.reasoning(text))
                }
            }
            if let text = payload["content"] as? String, !text.isEmpty {
                events.append(.content(text))
            } else if let parts = payload["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty {
                    events.append(.content(text))
                }
            }
        }
        return events
    }
}

/// Arbitrates the optional duplicate request: whichever attempt produces a token first
/// owns the stream, and the other one stops reading.
actor AIStreamSink {
    private let onEvent: @Sendable (AIStreamEvent) -> Void
    private var winner: Int?
    private var lastActivity: TimeInterval
    private var hasEmitted = false

    init(onEvent: @escaping @Sendable (AIStreamEvent) -> Void) {
        self.onEvent = onEvent
        lastActivity = ProcessInfo.processInfo.systemUptime
    }

    /// Returns false when another attempt already owns the stream and this one should stop.
    func accept(attempt: Int, events: [AIStreamEvent]) -> Bool {
        guard !events.isEmpty else { return isOwner(attempt) }
        if winner == nil {
            winner = attempt
        }
        guard winner == attempt else { return false }
        hasEmitted = true
        lastActivity = ProcessInfo.processInfo.systemUptime
        for event in events {
            onEvent(event)
        }
        return true
    }

    var hasProducedEvent: Bool {
        hasEmitted
    }

    var secondsSinceActivity: TimeInterval {
        ProcessInfo.processInfo.systemUptime - lastActivity
    }

    private func isOwner(_ attempt: Int) -> Bool {
        winner == nil || winner == attempt
    }
}

enum AIAPIStreamError {
    static func stalled(seconds: TimeInterval, receivedAnything: Bool) -> AIAPIError {
        .streamStalled(seconds: seconds, beforeFirstToken: !receivedAnything)
    }
}
