import Foundation
import Observation

@MainActor
@Observable
final class MahjongAudioSettings {
    static let shared = MahjongAudioSettings()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    private var overall: Double
    private var music: Double
    private var effects: Double
    private var voice: Double

    var overallVolume: Double {
        get { overall }
        set {
            overall = Self.clamp(newValue)
            save(overall, "overall")
        }
    }

    var musicVolume: Double {
        get { music }
        set {
            music = Self.clamp(newValue)
            save(music, "music")
        }
    }

    var effectsVolume: Double {
        get { effects }
        set {
            effects = Self.clamp(newValue)
            save(effects, "effects")
        }
    }

    var voiceVolume: Double {
        get { voice }
        set {
            voice = Self.clamp(newValue)
            save(voice, "voice")
        }
    }

    var isMuted: Bool {
        didSet { save(isMuted, "muted") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overall = Self.readVolume("overall", fallback: 0.5, from: defaults)
        music = Self.readVolume("music", fallback: 0.5, from: defaults)
        effects = Self.readVolume("effects", fallback: 0.5, from: defaults)
        voice = Self.readVolume("voice", fallback: 0.5, from: defaults)
        isMuted = defaults.bool(forKey: Self.key("muted"))
        defaults.removeObject(forKey: Self.key("pausesInBackground"))
    }

    func restoreDefaults() {
        overallVolume = 0.5
        musicVolume = 0.5
        effectsVolume = 0.5
        voiceVolume = 0.5
        isMuted = false
    }

    private func save(_ value: Any, _ name: String) {
        defaults.set(value, forKey: Self.key(name))
        onChange?()
    }

    private static func key(_ name: String) -> String {
        "mahjong.audio.\(name)"
    }

    private static func readVolume(_ name: String, fallback: Double, from defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: key(name)) != nil else { return fallback }
        return clamp(defaults.double(forKey: key(name)))
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
