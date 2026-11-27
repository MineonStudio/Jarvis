import Foundation

/// Severity comes from macOS thermal pressure, independently of the hottest
/// sensor reading. A single Celsius threshold is not reliable across Macs.
enum HomeThermalStatus: Equatable, Sendable {
    case normal
    case warm
    case hot
    case critical
    case unknown

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .normal
        case .fair: self = .warm
        case .serious: self = .hot
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .normal: "正常"
        case .warm: "偏热"
        case .hot: "高温"
        case .critical: "需要降温"
        case .unknown: "未知"
        }
    }

    var guidance: String? {
        switch self {
        case .hot: "温度较高，建议减少高负载任务。"
        case .critical: "需要降温，请暂停高负载任务。"
        default: nil
        }
    }

    /// macOS reports thermal pressure for the system, not for individual
    /// sensors. Keep that judgment consistent on both processor cards.
    func temperatureReminder(for celsius: Double?) -> String {
        if self == .hot {
            return "温度较高"
        }
        if self == .critical {
            return "需要降温"
        }
        guard let celsius, celsius.isFinite, celsius > 0, celsius <= 150 else { return "温度不可用" }
        switch self {
        case .normal: return "温度正常"
        case .warm: return "温度偏高"
        default: return "状态未知"
        }
    }
}
