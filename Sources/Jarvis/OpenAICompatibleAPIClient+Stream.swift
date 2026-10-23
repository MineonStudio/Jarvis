import Foundation

extension OpenAICompatibleAPIClient {
    /// Streams one request. Never trusts the provider to match the documented shape:
    /// a server that ignores `stream` is read as a plain completion instead, and a stalled
    /// connection is abandoned on the policy's deadlines instead of waiting forever.
    func stream(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions,
        policy: AIStreamingPolicy,
        onEvent: @escaping @Sendable (AIStreamEvent) -> Void
    ) async throws -> String {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedEndpointURL(
            from: configuration.endpoint,
            provider: configuration.provider
        ) else {
            throw AIAPIError.invalidEndpoint
        }

        let sink = AIStreamSink(onEvent: onEvent)
        let startedAt = ProcessInfo.processInfo.systemUptime
        let requestID = JarvisLog.operationID()
        let resumption = AIStreamingLatencyHistory.shared
        JarvisLog.notice(
            category: .network,
            event: "ai.stream.request",
            operationID: requestID,
            result: "started",
            fields: [
                "task": options.task,
                "provider": configuration.provider.rawValue,
                "model": configuration.model,
                "hedgeSeconds": String(format: "%.1f", policy.hedgeDelay),
                "hedging": policy.hedgingEnabled ? "true" : "false"
            ]
        )

        do {
            let content = try await withThrowingTaskGroup(of: StreamAttemptOutcome.self) { group in
                let attemptCount = policy.hedgingEnabled ? 2 : 1
                for id in 0 ..< attemptCount {
                    group.addTask { [self] in
                        if id > 0 {
                            // A duplicate request only makes sense while the first one is silent.
                            try await Task.sleep(for: .seconds(policy.hedgeDelay))
                            if await sink.hasProducedEvent {
                                return .skipped
                            }
                        }
                        do {
                            let text = try await runStreamAttempt(
                                StreamAttemptRequest(
                                    endpoint: endpoint,
                                    systemPrompt: systemPrompt,
                                    userPrompt: userPrompt,
                                    configuration: configuration,
                                    options: options,
                                    policy: policy
                                ),
                                attemptID: id,
                                sink: sink,
                                history: resumption
                            )
                            return .finished(text)
                        } catch is CancellationError {
                            return .skipped
                        } catch {
                            return .failed(error)
                        }
                    }
                }
                group.addTask {
                    try await Self.watchStream(sink: sink, policy: policy, startedAt: startedAt)
                    return .watchdog
                }

                var remainingAttempts = attemptCount
                var failures: [Error] = []
                for try await outcome in group {
                    switch outcome {
                    case let .finished(text):
                        group.cancelAll()
                        return text
                    case .watchdog:
                        continue
                    case .skipped:
                        remainingAttempts -= 1
                    case let .failed(error):
                        failures.append(error)
                        remainingAttempts -= 1
                        // A provider that refused will refuse the duplicate too.
                        if case AIAPIError.server = error {
                            remainingAttempts = 0
                        }
                    }
                    // Report what actually went wrong as soon as nothing is left running.
                    // Waiting on the watchdog instead would relabel a refusal, a bad key or
                    // a truncated answer as a stall a minute later.
                    guard remainingAttempts > 0 else {
                        group.cancelAll()
                        throw failures.first ?? AIAPIError.invalidTransportResponse
                    }
                }
                throw failures.first ?? AIAPIError.invalidTransportResponse
            }
            JarvisLog.notice(
                category: .network,
                event: "ai.stream.complete",
                operationID: requestID,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000,
                result: "success",
                fields: [
                    "task": options.task,
                    "provider": configuration.provider.rawValue,
                    "model": configuration.model,
                    "contentCharacters": String(content.count)
                ]
            )
            return content
        } catch {
            let nsError = error as NSError
            JarvisLog.error(
                category: .network,
                event: "ai.stream.failed",
                operationID: requestID,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000,
                fields: [
                    "task": options.task,
                    "provider": configuration.provider.rawValue,
                    "model": configuration.model,
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
            throw error
        }
    }

    enum StreamAttemptOutcome: Sendable {
        case finished(String)
        case failed(Error)
        /// The duplicate never had to run, or lost the race and stopped.
        case skipped
        /// The watchdog itself. It never returns while a request is alive, but it must not
        /// be counted as an attempt that settled.
        case watchdog
    }
}
