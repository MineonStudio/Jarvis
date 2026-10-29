import Foundation

struct OpenAICompatibleAPIClient: AITextCompletionAPI, AIAPIConnectionTesting, Sendable {
    func testConnection(configuration: AIAPIConfiguration) async throws {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedEndpointURL(
            from: configuration.endpoint,
            provider: configuration.provider
        ) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.provider == .openRouter ? 60 : 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAuthentication(to: &request, configuration: configuration)
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "user", "content": "Reply with OK."]
            ]
        ]
        if configuration.provider == .openRouter {
            // The catalogue includes models without JSON mode or temperature support.
            // A small explicit budget also avoids reserving an entire context window
            // against the user's OpenRouter credit balance just for a connection test.
            body["max_tokens"] = 1024
        } else {
            body["temperature"] = 0
            body["response_format"] = ["type": "json_object"]
            body["messages"] = [["role": "user", "content": "Reply with JSON: {\"ok\":true}"]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAPIError.invalidTransportResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = Self.serverMessage(from: data)
                ?? "AI 服务请求失败（\(httpResponse.statusCode)）"
            throw AIAPIError.server("HTTP \(httpResponse.statusCode)：\(message)")
        }

        // OpenRouter can return an error envelope after the HTTP headers were sent.
        if let message = Self.serverMessage(from: data) {
            throw AIAPIError.server(message)
        }
        try Self.validateConnectionEnvelope(from: data)
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            options: .standardJSON
        )
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions
    ) async throws -> String {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedEndpointURL(
            from: configuration.endpoint,
            provider: configuration.provider
        ) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = max(1, options.timeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAuthentication(to: &request, configuration: configuration)
        let requestBody = try JSONSerialization.data(
            withJSONObject: Self.completionBody(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                configuration: configuration,
                options: options
            )
        )
        request.httpBody = requestBody

        let requestID = JarvisLog.operationID()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let requestFields = [
            "task": options.task,
            "provider": configuration.provider.rawValue,
            "model": configuration.model,
            "requestBytes": String(requestBody.count),
            "timeoutSeconds": String(Int(request.timeoutInterval))
        ]
        JarvisLog.notice(
            category: .network,
            event: "ai.completion.request",
            operationID: requestID,
            result: "started",
            fields: requestFields
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAPIError.invalidTransportResponse
            }

            let succeeded = (200 ..< 300).contains(httpResponse.statusCode)
            JarvisLog.info(
                category: .network,
                event: "ai.completion.response",
                operationID: requestID,
                durationMilliseconds: elapsedMilliseconds,
                result: succeeded ? "success" : "failure",
                fields: [
                    "task": options.task,
                    "provider": configuration.provider.rawValue,
                    "model": configuration.model,
                    "httpStatus": String(httpResponse.statusCode),
                    "responseBytes": String(data.count)
                ].merging(Self.completionResponseMetrics(from: data), uniquingKeysWith: { _, new in new })
            )
            guard succeeded else {
                let message = Self.serverMessage(from: data)
                    ?? "AI 服务请求失败（\(httpResponse.statusCode)）"
                throw AIAPIError.server(message)
            }

            let content = try Self.chatCompletionContent(from: data)
            JarvisLog.notice(
                category: .network,
                event: "ai.completion.complete",
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
                event: "ai.completion.failed",
                operationID: requestID,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000,
                fields: requestFields.merging([
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ], uniquingKeysWith: { _, new in new })
            )
            throw error
        }
    }

    static func completionBody(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "temperature": options.temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        if options.responseFormat == .jsonObject {
            body["response_format"] = ["type": "json_object"]
        }
        if let maxOutputTokens = options.maxOutputTokens {
            body["max_tokens"] = maxOutputTokens
        }
        if options.suppressesReasoning, configuration.provider == .deepSeek {
            body["thinking"] = ["type": "disabled"]
        }
        return body
    }
}
