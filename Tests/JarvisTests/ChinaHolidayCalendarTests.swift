@testable import Jarvis
import XCTest

final class ChinaHolidayCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return value
    }

    private func entry(_ year: Int, _ month: Int, _ day: Int) -> ChinaHolidayDay? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            XCTFail("Invalid test date")
            return nil
        }
        return ChinaHolidayCalendar.entry(for: date, calendar: calendar, subscribedDays: [:])
    }

    func testFestivalRulesWorkBeforeAndAfterSubscriptionCoverageWithoutInventingDaysOff() {
        XCTAssertEqual(entry(2020, 1, 25)?.label, "春节")
        XCTAssertEqual(entry(2030, 2, 3)?.label, "春节")
        XCTAssertEqual(entry(2030, 2, 2)?.label, "除夕")
        XCTAssertEqual(entry(2030, 6, 5)?.label, "端午节")
        XCTAssertEqual(entry(2030, 9, 12)?.label, "中秋节")
        XCTAssertEqual(entry(2040, 10, 1)?.label, "国庆节")
        XCTAssertEqual(entry(2040, 10, 1)?.kind, .festival)
        XCTAssertNil(entry(2040, 10, 2))
        XCTAssertEqual(entry(2020, 10, 1)?.name, "国庆节·中秋节")
    }

    func testLeapMonthDoesNotDuplicateLunarFestivalAndQingmingIsNotFixed() {
        XCTAssertNil(entry(2009, 6, 27)) // Leap fifth lunar month, day five.
        XCTAssertEqual(entry(2030, 4, 5)?.label, "清明")
        XCTAssertEqual(entry(2024, 4, 4)?.label, "清明")
        XCTAssertEqual(ChinaFestivalRules.qingmingDay(in: 2027), 5)
        XCTAssertEqual(ChinaFestivalRules.qingmingDay(in: 2028), 4)
    }

    func testParsesLimitedYearlyRecurrenceAndPreservesOfficialRestPriority() throws {
        let data = Data("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20241001
        SUMMARY:国庆节
        RRULE:FREQ=YEARLY;COUNT=6
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261001
        DTEND;VALUE=DATE:20261008
        SUMMARY:国庆节（休）
        END:VEVENT
        END:VCALENDAR
        """.utf8)
        let days = try ChinaHolidayCalendar.parse(data)
        XCTAssertEqual(days["2026-10-01"]?.label, "国庆节·休")
        XCTAssertEqual(days["2029-10-01"]?.label, "国庆节")
        XCTAssertNil(days["2030-10-01"])
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 10, day: 1)))
        XCTAssertEqual(ChinaHolidayCalendar.entry(for: date, calendar: calendar, subscribedDays: days)?.label, "国庆节")
    }

    func testExpandsAppleRestRangesAndIncludesSingleWorkday() throws {
        let data = Data("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261001
        DTEND;VALUE=DATE:20261008
        SUMMARY;LANGUAGE=zh_CN:国庆节（休）
        BEGIN:VALARM
        SUMMARY:提醒
        END:VALARM
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261010
        SUMMARY;LANGUAGE=zh_CN:国庆节（班）
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261008
        SUMMARY:寒露
        END:VEVENT
        END:VCALENDAR
        """.utf8)
        let days = try ChinaHolidayCalendar.parse(data)
        XCTAssertEqual(days.count, 8)
        XCTAssertEqual(days["2026-10-01"]?.label, "国庆节·休")
        XCTAssertEqual(days["2026-10-07"]?.label, "国庆节·休")
        XCTAssertNil(days["2026-10-08"])
        XCTAssertEqual(days["2026-10-10"]?.label, "国庆节·班")
        XCTAssertEqual(days["2026-10-10"]?.isWorkday, true)
    }

    func testUnfoldsLinesAndExpandsAcrossYearBoundary() throws {
        let data = Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20231230\r\nDTEND;VALUE=DATE:20240102\r\nSUMMARY;LANGUAGE=zh_CN:元\r\n 旦（休）\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8)
        let days = try ChinaHolidayCalendar.parse(data)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days["2024-01-01"]?.label, "元旦·休")
        XCTAssertNil(days["2024-01-02"])
    }

    func testRejectsEmptyOrInvalidSubscriptionWithoutReplacingCache() {
        XCTAssertThrowsError(try ChinaHolidayCalendar.parse(Data("<html>unavailable</html>".utf8)))
        XCTAssertThrowsError(try ChinaHolidayCalendar.parse(Data("BEGIN:VCALENDAR\nEND:VCALENDAR".utf8)))
        XCTAssertThrowsError(try ChinaHolidayCalendar.parse(Data("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260230
        SUMMARY:春节（休）
        END:VEVENT
        END:VCALENDAR
        """.utf8)))
    }

    func testBundledOfflineDatesIncludeRestAndMakeupWorkdays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Calendar/china-holidays.json"))
        let snapshot = try JSONDecoder().decode(ChinaHolidaySnapshot.self, from: data)
        XCTAssertEqual(snapshot.source, ChinaHolidayCalendar.source.absoluteString)
        XCTAssertEqual(snapshot.days["2026-09-25"]?.label, "中秋节·休")
        XCTAssertEqual(snapshot.days["2026-10-07"]?.label, "国庆节·休")
        XCTAssertEqual(snapshot.days["2026-10-10"]?.label, "国庆节·班")
        XCTAssertNil(snapshot.days["2026-11-07"])
    }
}
