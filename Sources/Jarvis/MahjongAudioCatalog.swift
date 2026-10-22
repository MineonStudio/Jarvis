import Foundation

enum MahjongSoundEffect: String, CaseIterable {
    case tick, tileDraw, tileDiscard, deal, chi, pong, kong, win

    var resourceNames: [String] {
        switch self {
        case .tileDraw, .tileDiscard: (1 ... 3).map { "\(rawValue)-\($0)" }
        default: [rawValue]
        }
    }

    var minimumInterval: TimeInterval {
        switch self {
        case .tick, .win: 1
        case .deal: 0.5
        default: 0.2
        }
    }

    var priority: Int {
        switch self {
        case .tick: 0
        case .deal, .tileDraw: 1
        case .tileDiscard, .chi, .pong, .kong: 3
        case .win: 4
        }
    }

    var gain: Float {
        switch self {
        case .deal: 0.35
        case .tileDraw: 0.7
        case .tick: 0.5
        default: 1
        }
    }

    static func forVoice(_ key: String) -> Self? {
        if key.hasPrefix("tile-") {
            return .tileDiscard
        }
        switch key {
        case "action-chi": return .chi
        case "action-pong": return .pong
        case "action-kong", "action-exposed-kong", "action-added-kong", "action-concealed-kong": return .kong
        case "action-win", "action-self-draw", "action-draw": return .win
        default: return nil
        }
    }
}

/// One effect at a time; drop incidental sounds instead of replaying a backlog.
struct MahjongEffectGate {
    private var lastPlayed: [MahjongSoundEffect: TimeInterval] = [:]
    private var lastStarted: TimeInterval = -.infinity

    mutating func admit(_ effect: MahjongSoundEffect, at now: TimeInterval, active: MahjongSoundEffect?, voiceBusy: Bool) -> Bool {
        guard !(voiceBusy && effect.priority == 0),
              now - (lastPlayed[effect] ?? -.infinity) >= effect.minimumInterval else { return false }
        let interrupts = active.map { effect.priority > $0.priority } ?? false
        guard active == nil || interrupts, interrupts || now - lastStarted >= 0.12 else { return false }
        lastPlayed[effect] = now
        lastStarted = now
        return true
    }
}

struct MahjongVoiceRequest: Equatable {
    let key: String
    let gender: MahjongVoiceGender

    var priority: Int {
        switch key {
        case "action-win", "action-self-draw", "action-draw": 3
        case "action-chi", "action-pong", "action-kong", "action-exposed-kong", "action-added-kong", "action-concealed-kong": 2
        case "action-pass": 0
        default: 1
        }
    }

    /// Replace stale speech now, or drop this call; never schedule it for later.
    func canInterrupt(_ current: Self?) -> Bool {
        current.map { priority >= $0.priority } ?? true
    }
}
