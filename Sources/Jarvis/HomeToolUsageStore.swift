import Foundation
import Observation

/// Local entry activations, independent of page transitions or retained content.
@MainActor
@Observable
final class HomeToolUsageStore {
    struct Entry: Codable, Equatable {
        var count: Int
        var lastOpened: Date
    }

    private(set) var entries: [String: Entry]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "home.tool-usage.v1"
    static let tools: [SkillID] = [
        .screenshot, .clipboard, .meetingNotes, .screenRecording,
        .lanTransfer, .resume, .wallpaper, .windowLayout
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.key).flatMap {
            try? JSONDecoder().decode([String: Entry].self, from: $0)
        } ?? [:]
        entries = decoded.filter { SkillID(rawValue: $0.key) != nil && $0.value.count > 0 }
    }

    func recordOpen(_ tool: SkillID, at date: Date = .now) {
        let previous = count(for: tool)
        entries[tool.rawValue] = Entry(count: previous < Int.max ? previous + 1 : previous, lastOpened: date)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func count(for tool: SkillID) -> Int {
        entries[tool.rawValue]?.count ?? 0
    }

    func lastOpened(_ tool: SkillID) -> Date? {
        entries[tool.rawValue]?.lastOpened
    }

    var rankedTools: [SkillID] {
        Self.tools.enumerated().sorted { lhs, rhs in
            let left = count(for: lhs.element), right = count(for: rhs.element)
            if left != right {
                return left > right
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    var recentTools: [SkillID] {
        Self.tools.filter { lastOpened($0) != nil }.sorted {
            let left = lastOpened($0) ?? .distantPast, right = lastOpened($1) ?? .distantPast
            return left == right ? $0.rawValue < $1.rawValue : left > right
        }
    }
}
