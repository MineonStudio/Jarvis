import AppKit
import Observation

enum MahjongTableStyle: String, CaseIterable, Identifiable {
    case brocade, linen, walnut, leather

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .linen: "海盐亚麻"
        case .walnut: "胡桃木纹"
        case .leather: "酒红皮革"
        case .brocade: "墨夜织锦"
        }
    }

    var subtitle: String {
        switch self {
        case .linen: "雾蓝灰调 · 细密经纬"
        case .walnut: "温润棕木 · 自然纹理"
        case .leather: "复古酒红 · 细腻压纹"
        case .brocade: "深海藏蓝 · 暗金菱锦"
        }
    }

    var dye: (red: Double, green: Double, blue: Double) {
        switch self {
        case .linen: (0.19, 0.29, 0.34)
        case .walnut: (0.33, 0.205, 0.12)
        case .leather: (0.30, 0.09, 0.125)
        case .brocade: (0.085, 0.145, 0.23)
        }
    }

    var color: NSColor {
        NSColor(srgbRed: dye.red, green: dye.green, blue: dye.blue, alpha: 1)
    }

    /// Stable shader identifiers, independent of the settings display order.
    var textureID: Int {
        switch self {
        case .brocade: 4
        case .linen: 1
        case .walnut: 2
        case .leather: 3
        }
    }
}

@MainActor
@Observable
final class MahjongTableSettings {
    static let shared = MahjongTableSettings()
    @ObservationIgnored private let defaults: UserDefaults

    var style: MahjongTableStyle {
        didSet { defaults.set(style.rawValue, forKey: "mahjong.table.style") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedStyle = defaults.string(forKey: "mahjong.table.style")
        style = savedStyle.flatMap(MahjongTableStyle.init(rawValue:)) ?? .brocade
        if savedStyle == "jade" {
            defaults.set(style.rawValue, forKey: "mahjong.table.style")
        }
    }
}
