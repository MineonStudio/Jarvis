import Foundation

/// Shared five-step scale for dashboard accents. The RGB value is independent
/// of a metric's units; callers normalize measurements to a 0...1 fraction.
enum HomeMetricLevel: UInt32, CaseIterable, Sendable {
    case green = 0x34C759
    case yellowGreen = 0xA3CF4A
    case yellow = 0xF2C94C
    case orange = 0xF2994A
    case red = 0xEB5757

    init?(fraction: Double?) {
        guard let fraction, fraction.isFinite else { return nil }
        switch min(1, max(0, fraction)) {
        case ..<0.2: self = .green
        case ..<0.4: self = .yellowGreen
        case ..<0.6: self = .yellow
        case ..<0.8: self = .orange
        default: self = .red
        }
    }
}
