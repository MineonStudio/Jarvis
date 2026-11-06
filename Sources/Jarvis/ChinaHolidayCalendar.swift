import Foundation

enum ChinaHolidayKind: String, Codable, Sendable {
    case festival, rest, work
    var priority: Int {
        self == .work ? 3 : (self == .rest ? 2 : 1)
    }
}

struct ChinaHolidayDay: Codable, Equatable, Sendable {
    let name: String
    let kind: ChinaHolidayKind
    var isWorkday: Bool {
        kind == .work
    }

    var label: String {
        kind == .festival ? name : "\(name)·\(isWorkday ? "班" : "休")"
    }

    init(name: String, kind: ChinaHolidayKind) {
        self.name = name; self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case name, kind, isWorkday }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decodeIfPresent(ChinaHolidayKind.self, forKey: .kind)
            ?? (values.decode(Bool.self, forKey: .isWorkday) ? .work : .rest)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(kind, forKey: .kind)
    }
}

struct ChinaHolidaySnapshot: Codable, Sendable {
    let source: String
    let fetchedAt: Date
    let days: [String: ChinaHolidayDay]
}

enum ChinaHolidayCalendar {
    static let source = URL(string: "https://calendars.icloud.com/holidays/cn_zh.ics")!
    static let festivalNames: Set<String> = [
        "元旦", "妇女节", "劳动节", "青年节", "儿童节", "建党节", "建军节", "国庆节",
        "除夕", "春节", "正月初二", "正月初三", "元宵节", "清明", "端午节", "七夕节", "中秋节", "重阳节"
    ]

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parse dated events plus the feed's simple YEARLY/COUNT recurrences.
    /// Keep the recurrence limits intact; annual fallback is a separate calendar rule.
    static func parse(_ data: Data) throws -> [String: ChinaHolidayDay] {
        guard let text = String(data: data, encoding: .utf8),
              text.contains("BEGIN:VCALENDAR"), text.contains("END:VCALENDAR")
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var result: [String: ChinaHolidayDay] = [:]
        var event: [String: String]?
        var alarm = false
        for line in unfoldedLines(text) {
            if line == "BEGIN:VEVENT" {
                event = [:]; continue
            }
            if line == "BEGIN:VALARM" {
                alarm = true; continue
            }
            if line == "END:VALARM" {
                alarm = false; continue
            }
            guard !alarm else { continue }
            if line == "END:VEVENT" {
                defer { event = nil }
                if let event {
                    append(event, to: &result, calendar: calendar)
                }
            } else if event != nil, let colon = line.firstIndex(of: ":") {
                let property = line[..<colon].split(separator: ";", maxSplits: 1)[0]
                event?[String(property)] = String(line[line.index(after: colon)...])
            }
        }
        guard !result.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    private static func date(_ value: String?, calendar: Calendar) -> Date? {
        guard let value, value.count == 8, value.allSatisfy(\.isNumber),
              let year = Int(value.prefix(4)), let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2)),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              key(for: date, calendar: calendar).replacingOccurrences(of: "-", with: "") == value else { return nil }
        return date
    }

    private static func append(_ event: [String: String], to result: inout [String: ChinaHolidayDay], calendar: Calendar) {
        guard event["STATUS"] != "CANCELLED",
              let title = event["SUMMARY"], let start = date(event["DTSTART"], calendar: calendar),
              let end = date(event["DTEND"], calendar: calendar) ?? calendar.date(byAdding: .day, value: 1, to: start),
              let span = calendar.dateComponents([.day], from: start, to: end).day,
              (1 ... 31).contains(span), let day = holiday(title),
              let occurrences = occurrenceCount(event["RRULE"], kind: day.kind) else { return }
        for yearOffset in 0 ..< occurrences {
            guard let occurrence = calendar.date(byAdding: .year, value: yearOffset, to: start) else { continue }
            for offset in 0 ..< span {
                guard let current = calendar.date(byAdding: .day, value: offset, to: occurrence) else { continue }
                let key = key(for: current, calendar: calendar)
                if (result[key]?.kind.priority ?? 0) < day.kind.priority {
                    result[key] = day
                }
            }
        }
    }

    private static func holiday(_ title: String) -> ChinaHolidayDay? {
        let kind: ChinaHolidayKind = title.hasSuffix("（班）") ? .work : (title.hasSuffix("（休）") ? .rest : .festival)
        let name = (kind == .festival ? title : String(title.dropLast(3))).replacingOccurrences(of: "\\,", with: ",")
        guard kind != .festival || festivalNames.contains(name) else { return nil }
        return ChinaHolidayDay(name: name, kind: kind)
    }

    private static func occurrenceCount(_ recurrence: String?, kind: ChinaHolidayKind) -> Int? {
        guard let recurrence else { return 1 }
        let fields = Dictionary(recurrence.split(separator: ";").compactMap { part -> (String, String)? in
            let pair = part.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { _, last in last })
        guard kind == .festival, fields["FREQ"] == "YEARLY", fields["INTERVAL"] == nil || fields["INTERVAL"] == "1",
              let count = fields["COUNT"].flatMap(Int.init), (1 ... 100).contains(count),
              Set(fields.keys).isSubset(of: ["FREQ", "COUNT", "INTERVAL"]) else { return nil }
        return count
    }

    private static func unfoldedLines(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
        return lines
    }
}
