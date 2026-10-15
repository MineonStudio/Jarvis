import Foundation

/// How much transcript one request may carry.
///
/// The app cannot know a model's context window up front: some providers report one, most
/// do not, and the user is free to point Jarvis at any of them. So the budget starts
/// generous enough for a normal meeting, comes down when a provider says the request is too
/// long, and follows what the provider reports when it says anything at all.
final class AIContextBudgetStore: @unchecked Sendable {
    static let shared = AIContextBudgetStore()

    static let defaultBudget = 12000
    static let minimumBudget = 2000
    static let maximumBudget = 96000

    private static let key = "jarvis.ai.transcript.budget"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var budgets: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        budgets = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    func budget(for configuration: AIAPIConfiguration) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return budgets[Self.identifier(for: configuration)] ?? Self.defaultBudget
    }

    /// A provider that reports a context window gets to decide the budget. Only a fraction
    /// of it is used: the answer has to fit in the same window as the transcript.
    func recordContextWindow(_ contextWindow: Int, for configuration: AIAPIConfiguration) {
        guard contextWindow > 0 else { return }
        store(
            min(Self.maximumBudget, max(Self.minimumBudget, contextWindow * 2 / 5)),
            for: configuration
        )
    }

    /// Records every window a provider reported, so switching models does not have to
    /// rediscover them one request at a time.
    func recordContextWindows(_ windows: [String: Int], providerID: String) {
        guard !windows.isEmpty else { return }
        lock.lock()
        for (model, window) in windows where window > 0 {
            budgets["\(providerID)|\(model.lowercased())"] = min(
                Self.maximumBudget,
                max(Self.minimumBudget, window * 2 / 5)
            )
        }
        let snapshot = budgets
        lock.unlock()
        defaults.set(snapshot, forKey: Self.key)
    }

    /// The provider rejected a request for being too long. Whatever was sent was too much.
    func recordTooLong(estimatedTokens: Int, for configuration: AIAPIConfiguration) {
        let current = budget(for: configuration)
        let ceiling = estimatedTokens > 0 ? estimatedTokens / 2 : current / 2
        store(max(Self.minimumBudget, min(current, ceiling)), for: configuration)
    }

    private func store(_ budget: Int, for configuration: AIAPIConfiguration) {
        lock.lock()
        budgets[Self.identifier(for: configuration)] = budget
        let snapshot = budgets
        lock.unlock()
        defaults.set(snapshot, forKey: Self.key)
    }

    private static func identifier(for configuration: AIAPIConfiguration) -> String {
        "\(configuration.provider.rawValue)|\(configuration.model.lowercased())"
    }
}
