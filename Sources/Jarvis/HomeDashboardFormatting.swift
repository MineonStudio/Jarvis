import Foundation

/// Pure formatting and date calculations shared by the dashboard and its tests.
enum HomeDashboardFormatting {
    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    static func bytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
        if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let hours = max(0, Int(seconds / 3600))
        return hours >= 24 ? "\(hours / 24) 天 \(hours % 24) 小时" : "\(hours) 小时 \(max(0, Int(seconds / 60)) % 60) 分钟"
    }

    static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5 ..< 12: "上午好"
        case 12 ..< 18: "下午好"
        case 18 ..< 24: "晚上好"
        default: "夜深了"
        }
    }

    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date)
        else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return [Date?](repeating: nil, count: leading)
            + days.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: interval.start)
            }.map(Optional.some)
    }

    static func shiftedMonth(from date: Date, by offset: Int, calendar: Calendar = .current) -> Date? {
        guard let firstDay = calendar.dateInterval(of: .month, for: date)?.start,
              let shifted = calendar.date(byAdding: .month, value: offset, to: firstDay) else { return nil }
        return shifted
    }
}
