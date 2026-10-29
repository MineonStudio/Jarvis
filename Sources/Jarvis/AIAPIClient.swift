import Foundation

struct AIAPIConfiguration: Equatable, Sendable {
    static let apiEndpointKey = "jarvis.ai.api.endpoint"
    static let apiModelKey = "jarvis.ai.api.model"
    static let apiNameKey = "jarvis.ai.api.name"
    static let apiProviderKey = "jarvis.ai.api.provider"
    static let endpointKey = "jarvis.ai.endpoint"
    static let modelKey = "jarvis.ai.model"
    static let providerEndpointKey = "jarvis.ai.provider.endpoint"
    static let paidEndpointKey = "jarvis.ai.paid-endpoint"
    static let paidModelKey = "jarvis.ai.paid-model"
    static let legacyEndpointKey = "jarvis.screenshot.translation.endpoint"
    static let legacyModelKey = "jarvis.screenshot.translation.model"
    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    private static let storedProviderKeys = [
        apiEndpointKey,
        apiModelKey,
        apiNameKey,
        apiProviderKey,
        endpointKey,
        modelKey,
        providerEndpointKey,
        paidEndpointKey,
        paidModelKey,
        legacyEndpointKey,
        legacyModelKey
    ]

    var endpoint: String
    var model: String
    var apiKey: String
    var providerID: String = AIAPIProvider.custom.rawValue

    init(
        endpoint: String,
        model: String,
        apiKey: String,
        providerID: String? = nil
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.providerID = providerID ?? AIAPIProvider.detect(endpoint: endpoint).rawValue
    }

    var provider: AIAPIProvider {
        AIAPIProvider(rawValue: providerID) ?? .custom
    }

    var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(
        defaults: UserDefaults = .standard,
        keyStore: AIAPIKeyStore = .shared
    ) -> Self {
        load(defaults: defaults, resolvedAPIKey: keyStore.readIfAvailable())
    }

    /// #24：loadProvider 只是 load 的别名（provider 本来就是 load 里 detect 出来的），
    /// 别名已删除，调用方直接用 load。
    static func load(
        defaults: UserDefaults = .standard,
        resolvedAPIKey: String?
    ) -> Self {
        let endpoint = nonEmpty(defaults.string(forKey: apiEndpointKey))
            ?? nonEmpty(defaults.string(forKey: providerEndpointKey))
            ?? nonEmpty(defaults.string(forKey: paidEndpointKey))
            ?? nonEmpty(defaults.string(forKey: endpointKey))
            ?? nonEmpty(defaults.string(forKey: legacyEndpointKey))
            ?? defaultEndpoint
        let model = nonEmpty(defaults.string(forKey: apiModelKey))
            ?? nonEmpty(defaults.string(forKey: paidModelKey))
            ?? nonEmpty(defaults.string(forKey: modelKey))
            ?? nonEmpty(defaults.string(forKey: legacyModelKey))
            ?? defaultModel
        let provider = defaults.string(forKey: apiProviderKey)
            .flatMap(AIAPIProvider.init(rawValue:))
            ?? AIAPIProvider.detect(endpoint: endpoint)
        return Self(
            endpoint: endpoint,
            model: model,
            apiKey: resolvedAPIKey ?? "",
            providerID: provider.rawValue
        )
    }

    static func migrateLegacyKeys(defaults: UserDefaults = .standard) {
        if defaults.string(forKey: apiEndpointKey) == nil,
           let endpoint = nonEmpty(
               defaults.string(forKey: providerEndpointKey)
                   ?? defaults.string(forKey: paidEndpointKey)
                   ?? defaults.string(forKey: endpointKey)
                   ?? defaults.string(forKey: legacyEndpointKey)
           )
        {
            defaults.set(endpoint, forKey: apiEndpointKey)
        }
        if defaults.string(forKey: apiModelKey) == nil,
           let model = nonEmpty(
               defaults.string(forKey: paidModelKey)
                   ?? defaults.string(forKey: modelKey)
                   ?? defaults.string(forKey: legacyModelKey)
           )
        {
            defaults.set(model, forKey: apiModelKey)
        }
        if defaults.string(forKey: apiProviderKey) == nil,
           let endpoint = nonEmpty(defaults.string(forKey: apiEndpointKey))
        {
            defaults.set(AIAPIProvider.detect(endpoint: endpoint).rawValue, forKey: apiProviderKey)
        }
    }

    static func hasStoredAPIEndpoint(defaults: UserDefaults = .standard) -> Bool {
        [apiEndpointKey, providerEndpointKey, paidEndpointKey, endpointKey, legacyEndpointKey]
            .contains { nonEmpty(defaults.string(forKey: $0)) != nil }
    }

    static func removeStoredConfiguration(defaults: UserDefaults = .standard) {
        for key in storedProviderKeys {
            defaults.removeObject(forKey: key)
        }
    }

    static func nonEmpty(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var openAIBaseURL: String {
        let trimmed = endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let stripped = if trimmed.lowercased().hasSuffix("/chat/completions") {
            String(trimmed.dropLast("/chat/completions".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            trimmed
        }
        guard let components = URLComponents(string: stripped) else {
            return stripped
        }
        let path = components.path
        if path.isEmpty || path == "/" {
            return stripped + provider.chatCompletionsPath.dropLast("/chat/completions".count)
        }
        return stripped
    }
}

/// Request behavior for one completion. Output limits are optional so task-specific
/// callers can cap compact decisions without changing general-purpose requests.
struct AICompletionOptions: Equatable, Sendable {
    enum ResponseFormat: Equatable, Sendable {
        case jsonObject
        case plainText
    }

    let task: String
    let temperature: Double
    let responseFormat: ResponseFormat
    let timeoutSeconds: TimeInterval
    let maxOutputTokens: Int?
    /// DeepSeek thinking is on by default and spends `max_tokens` before `content`.
    /// Compact decisions set this so the answer is written into `content`. Only the
    /// DeepSeek request body receives `thinking: disabled`; other providers ignore it.
    let suppressesReasoning: Bool

    init(
        task: String,
        temperature: Double = 0.7,
        responseFormat: ResponseFormat = .jsonObject,
        timeoutSeconds: TimeInterval = 90,
        maxOutputTokens: Int? = nil,
        suppressesReasoning: Bool = false
    ) {
        self.task = task
        self.temperature = temperature
        self.responseFormat = responseFormat
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputTokens = maxOutputTokens
        self.suppressesReasoning = suppressesReasoning
    }

    static let standardJSON = Self(task: "generic-structured-json")

    static let meetingSummary = Self(
        task: "meeting-summary",
        temperature: 0,
        responseFormat: .jsonObject
    )

    static let resumeStructured = Self(
        task: "resume-structured-json",
        temperature: 0.7,
        responseFormat: .jsonObject
    )

    /// A tile name or a 1-based action index. Thinking stays off so those few
    /// characters are the completion, not a chain of thought cut off at the cap.
    static let mahjongDecision = Self(
        task: "mahjong-decision",
        temperature: 0,
        responseFormat: .plainText,
        timeoutSeconds: 10,
        maxOutputTokens: 32,
        suppressesReasoning: true
    )
}

protocol AITextCompletionAPI: Sendable {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String

    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions
    ) async throws -> String

    /// Same request as `complete`, but hands back each piece as it arrives and returns the
    /// whole answer at the end. `onEvent` runs off the caller's actor and may be called
    /// concurrently with nothing else: the client serialises it.
    func stream(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions,
        policy: AIStreamingPolicy,
        onEvent: @escaping @Sendable (AIStreamEvent) -> Void
    ) async throws -> String
}

extension AITextCompletionAPI {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options _: AICompletionOptions
    ) async throws -> String {
        try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration
        )
    }

    /// Fallback for APIs that only implement `complete`: one event with the whole answer.
    /// Callers see the same result and the same progress-free behaviour they had before.
    func stream(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions,
        policy _: AIStreamingPolicy,
        onEvent: @escaping @Sendable (AIStreamEvent) -> Void
    ) async throws -> String {
        let content = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            options: options
        )
        onEvent(.content(content))
        return content
    }
}

protocol AIAPIConnectionTesting: Sendable {
    func testConnection(configuration: AIAPIConfiguration) async throws
}

enum AIAPIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidEndpoint
    case invalidTransportResponse
    case invalidCompletionEnvelope(String)
    case invalidModelsEnvelope(String)
    case invalidJSON(context: String, reason: String)
    case invalidSchema(context: String, reason: String)
    case emptyGeneratedContent(context: String)
    case duplicateGeneratedContent(context: String)
    case outputTruncated
    case streamStalled(seconds: TimeInterval, beforeFirstToken: Bool)
    case streamTimedOut(seconds: TimeInterval)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "请先在设置中配置 AI 服务"
        case .invalidEndpoint:
            "AI 服务地址无效"
        case .invalidTransportResponse:
            "AI 服务响应异常：未收到有效的 HTTP 响应"
        case let .invalidCompletionEnvelope(reason):
            "AI 服务响应格式错误：\(reason)"
        case let .invalidModelsEnvelope(reason):
            "模型列表响应格式错误：\(reason)"
        case let .invalidJSON(context, reason):
            "\(context)结果不是有效 JSON：\(reason)"
        case let .invalidSchema(context, reason):
            "\(context)字段结构不符合要求：\(reason)"
        case let .emptyGeneratedContent(context):
            "\(context)没有生成有效内容"
        case let .duplicateGeneratedContent(context):
            "\(context)没有生成新的内容，请稍后再试"
        case .outputTruncated:
            "AI 服务输出未完成：模型或服务端提前结束了响应，请检查模型上下文容量或服务商限制"
        case let .streamStalled(seconds, beforeFirstToken):
            beforeFirstToken
                ? "AI 服务 \(Int(seconds)) 秒没有开始返回内容，已放弃本次请求。"
                : "AI 服务返回中途卡住，\(Int(seconds)) 秒没有新内容，已放弃本次请求。"
        case let .streamTimedOut(seconds):
            "AI 服务超过 \(Int(seconds)) 秒仍未完成，已放弃本次请求。"
        case let .server(message):
            message
        }
    }

    /// True when the provider accepted the request and then went quiet. Callers treat that
    /// as a stalled service rather than a wrong answer, because asking again is worthwhile.
    var isStreamInterruption: Bool {
        switch self {
        case .streamStalled, .streamTimedOut: true
        default: false
        }
    }

    static func decodingError(_ error: Error, context: String) -> Self {
        guard let decodingError = error as? DecodingError else {
            return .invalidJSON(context: context, reason: error.localizedDescription)
        }

        switch decodingError {
        case let .dataCorrupted(decodingContext):
            return .invalidJSON(
                context: context,
                reason: "\(codingPathDescription(decodingContext.codingPath))：\(decodingContext.debugDescription)"
            )
        case let .keyNotFound(key, decodingContext):
            return .invalidSchema(
                context: context,
                reason: "缺少字段 \(codingPathDescription(decodingContext.codingPath, appending: key))"
            )
        case let .typeMismatch(type, decodingContext):
            return .invalidSchema(
                context: context,
                reason: "字段 \(codingPathDescription(decodingContext.codingPath)) 应为 \(String(describing: type))"
            )
        case let .valueNotFound(type, decodingContext):
            return .invalidSchema(
                context: context,
                reason: "字段 \(codingPathDescription(decodingContext.codingPath)) 为空，期望 \(String(describing: type))"
            )
        @unknown default:
            return .invalidSchema(context: context, reason: "字段结构无法识别")
        }
    }

    private static func codingPathDescription(
        _ codingPath: [any CodingKey],
        appending key: (any CodingKey)? = nil
    ) -> String {
        let keys = codingPath.map(\.stringValue) + (key.map { [$0.stringValue] } ?? [])
        return keys.isEmpty ? "根对象" : keys.joined(separator: ".")
    }
}
