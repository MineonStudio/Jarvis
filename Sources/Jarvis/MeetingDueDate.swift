import Foundation

/// Resolve spoken deadlines against the meeting day, including records saved by
/// earlier versions. Unresolvable phrases stay as spoken rather than inventing a date.
enum MeetingDueDate {
    static func label(_ raw: String, meetingDate: Date, calendar: Calendar = .current) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Older records stored both the meeting day and the computed deadline.
        if let range = text.range(of: "换算为"),
           let date = explicitDate(
               in: String(text[range.upperBound...]), meetingDate: meetingDate, calendar: calendar
           )
        {
            return dayString(date, calendar: calendar)
        }
        if let date = explicitDate(in: text, meetingDate: meetingDate, calendar: calendar)
            ?? relativeDate(in: text, meetingDate: meetingDate, calendar: calendar)
        {
            return dayString(date, calendar: calendar)
        }
        // Drop legacy explanatory suffixes even if their date is malformed.
        return text.components(separatedBy: "（由会议日期").first ?? text
    }

    private static func explicitDate(in text: String, meetingDate: Date, calendar: Calendar) -> Date? {
        if let parts = captures(#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#, in: text) {
            return date(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]), calendar: calendar)
        }
        let digits = "0-9零〇一二两三四五六七八九十"
        if let parts = captures("(?:([\(digits)]+)年)?([\(digits)]+)月([\(digits)]+)[日号]", in: text) {
            let year =
                parts[0].isEmpty
                    ? calendar.component(.year, from: meetingDate) + (text.contains("明年") ? 1 : 0)
                    : number(parts[0])
            return date(year: year, month: number(parts[1]), day: number(parts[2]), calendar: calendar)
        }
        return nil
    }

    private static func relativeDate(in text: String, meetingDate: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: meetingDate)
        for (phrase, days) in [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0), ("当天", 0)]
            where text.contains(phrase)
        {
            return calendar.date(byAdding: .day, value: days, to: start)
        }
        let normalized = text.replacingOccurrences(of: "星期", with: "周").replacingOccurrences(
            of: "礼拜", with: "周"
        )
        guard let parts = captures("周([一二三四五六日天1-7])", in: normalized) else { return nil }
        let days = [
            "一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6,
            "1": 0, "2": 1, "3": 2, "4": 3, "5": 4, "6": 5, "7": 6
        ]
        guard let target = days[parts[0]] else { return nil }
        let current = (calendar.component(.weekday, from: start) + 5) % 7
        let offset: Int = if normalized.contains("下下周") {
            14 + target - current
        } else if normalized.contains("下周") {
            7 + target - current
        } else if normalized.contains("本周") || normalized.contains("这周") {
            target - current
        } else {
            (target - current + 7) % 7
        }
        return calendar.date(byAdding: .day, value: offset, to: start)
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1 ..< match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func number(_ text: String) -> Int? {
        if let value = Int(text) {
            return value
        }
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
            "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if text.contains("十") {
            let parts = text.components(separatedBy: "十")
            guard parts.count == 2,
                  let tens = parts[0].isEmpty ? 1 : parts[0].first.flatMap({ digits[$0] }),
                  let units = parts[1].isEmpty ? 0 : parts[1].first.flatMap({ digits[$0] })
            else { return nil }
            return tens * 10 + units
        }
        let values = text.compactMap { digits[$0] }
        guard values.count == text.count, !values.isEmpty else { return nil }
        return values.reduce(0) { $0 * 10 + $1 }
    }

    private static func date(year: Int?, month: Int?, day: Int?, calendar: Calendar) -> Date? {
        guard let year, let month, let day, (1 ... 12).contains(month), (1 ... 31).contains(day),
              let result = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        guard components.year == year, components.month == month, components.day == day else {
            return nil
        }
        return result
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
