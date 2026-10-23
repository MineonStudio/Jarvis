import Foundation

extension OpenAICompatibleAPIClient {
    /// What a provider says about its models. The context window is optional on the wire:
    /// providers that report it let the app size its requests correctly instead of guessing.
    struct ModelCatalogue: Sendable {
        var identifiers: [String]
        var contextWindows: [String: Int]

        init(identifiers: [String], contextWindows: [String: Int] = [:]) {
            self.identifiers = identifiers
            self.contextWindows = contextWindows
        }
    }

    func fetchModels(configuration: AIAPIConfiguration) async throws -> [String] {
        try await fetchModelCatalogue(configuration: configuration).identifiers
    }

    func fetchModelCatalogue(configuration: AIAPIConfiguration) async throws -> ModelCatalogue {
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedModelsURL(
            from: configuration.endpoint,
            provider: configuration.provider
        ) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.applyAuthentication(to: &request, configuration: configuration)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAPIError.invalidTransportResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = Self.serverMessage(from: data)
                ?? "获取模型列表失败（\(httpResponse.statusCode)）"
            throw AIAPIError.server(message)
        }

        return try ModelCatalogue(
            identifiers: Self.modelIdentifiers(from: data),
            contextWindows: Self.modelContextWindows(from: data)
        )
    }

    /// `context_window` is not part of the OpenAI schema; it is read when a provider offers it.
    static func modelContextWindows(from data: Data) -> [String: Int] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["data"] as? [[String: Any]]
        else { return [:] }
        var windows: [String: Int] = [:]
        for value in values {
            guard let identifier = value["id"] as? String, !identifier.isEmpty else { continue }
            if let window = value["context_window"] as? Int, window > 0 {
                windows[identifier] = window
            } else if let window = value["context_length"] as? Int, window > 0 {
                windows[identifier] = window
            }
        }
        return windows
    }

    static func applyAuthentication(
        to request: inout URLRequest,
        configuration: AIAPIConfiguration
    ) {
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    static func normalizedEndpointURL(
        from rawValue: String,
        provider: AIAPIProvider? = nil
    ) -> URL? {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              scheme == "https" || (scheme == "http" && isLoopbackHost(host))
        else {
            return nil
        }
        let resolvedProvider = provider ?? AIAPIProvider.detect(endpoint: trimmed)
        let path = components.path
        if path.hasSuffix("/chat/completions") {
            return components.url
        }
        if path.isEmpty || path == "/" {
            components.path = resolvedProvider.chatCompletionsPath
        } else {
            components.path = path.hasSuffix("/")
                ? path + "chat/completions"
                : path + "/chat/completions"
        }
        return components.url
    }

    /// Plain http is allowed only for a model running on this Mac (Ollama, LM Studio and
    /// friends listen there). A key sent to a public host stays https-only.
    static func isLoopbackHost(_ host: String) -> Bool {
        let name = host.lowercased()
        return name == "localhost" || name == "::1" || name == "[::1]" || name.hasPrefix("127.")
    }

    static func normalizedModelsURL(
        from rawValue: String,
        provider: AIAPIProvider? = nil
    ) -> URL? {
        let resolvedProvider = provider ?? AIAPIProvider.detect(endpoint: rawValue)
        let baseURL = AIAPIConfiguration(
            endpoint: rawValue,
            model: "model",
            apiKey: "",
            providerID: resolvedProvider.rawValue
        ).openAIBaseURL
        guard var components = URLComponents(string: baseURL),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "/models" : "/\(path)/models"
        return components.url
    }

    static func modelIdentifiers(from data: Data) throws -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["data"] as? [[String: Any]]
        else {
            throw AIAPIError.invalidModelsEnvelope("缺少 data 数组")
        }

        let identifiers: [String] = values.compactMap { value -> String? in
            guard let identifier = value["id"] as? String else { return nil }
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let uniqueIdentifiers = Array(Set(identifiers)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        guard !uniqueIdentifiers.isEmpty else {
            throw AIAPIError.invalidModelsEnvelope("data 数组中没有有效模型")
        }
        return uniqueIdentifiers
    }

    static func chatCompletionContent(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("响应正文不是 JSON 对象")
        }
        guard let choices = root["choices"] as? [[String: Any]], !choices.isEmpty else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 choices 数组或 choices 为空")
        }
        guard let message = choices[0]["message"] as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message")
        }
        if let finishReason = choices[0]["finish_reason"] as? String,
           finishReason == "length"
        {
            throw AIAPIError.outputTruncated
        }
        if let content = message["content"] as? String {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 为空")
            }
            return content
        }
        if let contentParts = message["content"] as? [[String: Any]] {
            let content = contentParts.compactMap { $0["text"] as? String }.joined()
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 文本片段为空")
            }
            return content
        }
        throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message.content，或 content 类型不受支持")
    }

    static func completionResponseMetrics(from data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var metrics: [String: String] = [:]
        if let choices = root["choices"] as? [[String: Any]],
           let choice = choices.first,
           let finishReason = choice["finish_reason"] as? String
        {
            metrics["finishReason"] = finishReason
        }
        if let usage = root["usage"] as? [String: Any] {
            if let promptTokens = usage["prompt_tokens"] {
                metrics["promptTokens"] = String(describing: promptTokens)
            }
            if let completionTokens = usage["completion_tokens"] {
                metrics["completionTokens"] = String(describing: completionTokens)
            }
            if let totalTokens = usage["total_tokens"] {
                metrics["totalTokens"] = String(describing: totalTokens)
            }
        }
        return metrics
    }

    static func validateConnectionEnvelope(from data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("响应正文不是 JSON 对象")
        }
        guard let choices = root["choices"] as? [[String: Any]], !choices.isEmpty else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 choices 数组或 choices 为空")
        }
        guard let message = choices[0]["message"] as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message")
        }
        if let content = message["content"] as? String {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 为空")
            }
            return
        }
        if let contentParts = message["content"] as? [[String: Any]] {
            let content = contentParts.compactMap { $0["text"] as? String }.joined()
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 文本片段为空")
            }
            return
        }
        throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message.content，或 content 类型不受支持")
    }

    static func jsonData(fromModelContent content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil
        {
            return data
        }
        let unfenced = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = unfenced.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
            return nil
        }
        return data
    }

    static func serverMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }
}
