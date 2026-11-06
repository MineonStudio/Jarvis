import Foundation

/// Festival dates are calendar rules. They never imply approved days off or makeup work.
enum ChinaFestivalRules {
    static func festival(for date: Date, calendar displayCalendar: Calendar) -> ChinaHolidayDay? {
        let parts = displayCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let solar: [Int: String] = [
            101: "元旦", 308: "妇女节", 501: "劳动节", 504: "青年节",
            601: "儿童节", 701: "建党节", 801: "建军节", 1001: "国庆节"
        ]
        var names = solar[month * 100 + day].map { [$0] } ?? []
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        // Convert civil date components at noon, so display timezone/DST cannot shift a festival.
        guard let civilDate = gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = gregorian.timeZone
        let chinese = lunar.dateComponents([.month, .day, .isLeapMonth], from: civilDate)
        if chinese.isLeapMonth != true, let lunarMonth = chinese.month, let lunarDay = chinese.day {
            let festivals: [Int: String] = [
                101: "春节", 102: "正月初二", 103: "正月初三", 115: "元宵节",
                505: "端午节", 707: "七夕节", 815: "中秋节", 909: "重阳节"
            ]
            if let name = festivals[lunarMonth * 100 + lunarDay] {
                names.append(name)
            }
        }
        if let tomorrow = gregorian.date(byAdding: .day, value: 1, to: civilDate) {
            let next = lunar.dateComponents([.month, .day, .isLeapMonth], from: tomorrow)
            if next.month == 1, next.day == 1, next.isLeapMonth != true {
                names.append("除夕")
            }
        }
        if month == 4, day == qingmingDay(in: year) {
            names.append("清明")
        }
        return names.isEmpty ? nil : ChinaHolidayDay(name: names.joined(separator: "·"), kind: .festival)
    }

    /// Qingming is a solar term (apparent solar longitude 15°), not a fixed Gregorian day.
    /// Meeus solar-position equations, also used by NOAA's solar calculator.
    /// Subscription dates take precedence over this astronomical fallback.
    static func qingmingDay(in year: Int) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        guard let estimate = calendar.date(from: DateComponents(year: year, month: 4, day: 4, hour: 12)) else { return nil }
        var julianDay = estimate.timeIntervalSince1970 / 86400 + 2_440_587.5
        func sine(_ degrees: Double) -> Double {
            sin(degrees * .pi / 180)
        }
        for _ in 0 ..< 8 {
            let t = (julianDay - 2_451_545) / 36525
            let meanLongitude = 280.46646 + t * (36000.76983 + t * 0.0003032)
            let anomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
            let center = sine(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
                + sine(2 * anomaly) * (0.019993 - 0.000101 * t) + sine(3 * anomaly) * 0.000289
            let apparent = meanLongitude + center - 0.00569 - 0.00478 * sine(125.04 - 1934.136 * t)
            var difference = (apparent - 15).truncatingRemainder(dividingBy: 360)
            if difference > 180 {
                difference -= 360
            }
            if difference < -180 {
                difference += 360
            }
            julianDay -= difference / 0.98564736
        }
        let crossing = Date(timeIntervalSince1970: (julianDay - 2_440_587.5) * 86400)
        return calendar.component(.day, from: crossing)
    }
}

extension ChinaHolidayCalendar {
    static func entry(for date: Date, calendar: Calendar, subscribedDays: [String: ChinaHolidayDay]) -> ChinaHolidayDay? {
        subscribedDays[key(for: date, calendar: calendar)] ?? ChinaFestivalRules.festival(for: date, calendar: calendar)
    }
}
