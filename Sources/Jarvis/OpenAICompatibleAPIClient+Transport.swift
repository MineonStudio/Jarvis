import Foundation

extension OpenAICompatibleAPIClient {
    /// Fails the whole request when the stream goes quiet, so a silent provider cannot
    /// hold the app for as long as it likes.
    static func watchStream(
        sink: AIStreamSink,
        policy: AIStreamingPolicy,
        startedAt: TimeInterval
    ) async throws {
        while true {
            try await Task.sleep(for: .seconds(1))
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            if elapsed > policy.totalTimeout {
                throw AIAPIError.streamTimedOut(seconds: elapsed)
            }
            let silence = await sink.secondsSinceActivity
            let produced = await sink.hasProducedEvent
            let allowance = produced ? policy.idleTimeout : policy.firstDeltaTimeout
            // The duplicate may still save the request; only give up once both are spent.
            if silence > allowance, !policy.hedgingEnabled || elapsed > policy.hedgeDelay {
                throw AIAPIError.streamStalled(seconds: silence, beforeFirstToken: !produced)
            }
        }
    }

    /// Everything one attempt needs, so the attempt itself only takes its identity and
    /// the shared sink.
    struct StreamAttemptRequest: Sendable {
        var endpoint: URL
        var systemPrompt: String
        var userPrompt: String
        var configuration: AIAPIConfiguration
        var options: AICompletionOptions
        var policy: AIStreamingPolicy
    }

    func runStreamAttempt(
        _ attempt: StreamAttemptRequest,
        attemptID: Int,
        sink: AIStreamSink,
        history: AIStreamingLatencyHistory
    ) async throws -> String {
        var body = Self.completionBody(
            systemPrompt: attempt.systemPrompt,
            userPrompt: attempt.userPrompt,
            configuration: attempt.configuration,
            options: attempt.options
        )
        body["stream"] = true

        var request = URLRequest(url: attempt.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = attempt.policy.firstDeltaTimeout + attempt.policy.idleTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        Self.applyAuthentication(to: &request, configuration: attempt.configuration)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let attemptStartedAt = ProcessInfo.processInfo.systemUptime
        let (bytes, response) = try await Self.streamingSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAPIError.invalidTransportResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let data = try await Self.collectBody(bytes)
            throw AIAPIError.server(
                Self.serverMessage(from: data) ?? "AI 服务请求失败（\(httpResponse.statusCode)）"
            )
        }

        var state = StreamReadState()
        // Nested so both the streaming and the buffered path share one place that
        // accumulates content and hands events to the sink, in order.
        func handle(line: String) async throws {
            let events = state.decoder.feed(line: line)
            guard !events.isEmpty else { return }
            if !state.sawFirstToken {
                state.sawFirstToken = true
                history.record(
                    firstTokenSeconds: ProcessInfo.processInfo.systemUptime - attemptStartedAt,
                    configuration: attempt.configuration
                )
            }
            for event in events {
                if case let .content(text) = event {
                    state.content += text
                }
            }
            guard await sink.accept(attempt: attemptID, events: events) else {
                throw CancellationError()
            }
        }

        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/event-stream") {
            for try await line in bytes.lines {
                try await handle(line: line)
            }
        } else {
            // Either an ordinary completion envelope, or a stream from a server that did
            // not label it. Read the body once and tell the two apart.
            let data = try await Self.collectBody(bytes)
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("data:") {
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    try await handle(line: String(line))
                }
            } else {
                let content = try Self.chatCompletionContent(from: data)
                history.record(
                    firstTokenSeconds: ProcessInfo.processInfo.systemUptime - attemptStartedAt,
                    configuration: attempt.configuration
                )
                guard await sink.accept(attempt: attemptID, events: [.content(content)]) else {
                    throw CancellationError()
                }
                return content
            }
        }

        guard state.decoder.sawAnyEvent || state.decoder.sawCompletion else {
            throw AIAPIError.outputTruncated
        }
        guard !state.content.isEmpty else {
            throw AIAPIError.emptyGeneratedContent(context: attempt.options.task)
        }
        return state.content
    }

    struct StreamReadState {
        var decoder = SSEChatCompletionDecoder()
        var content = ""
        var sawFirstToken = false
    }

    static func collectBody(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    static let streamingSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }()
}
