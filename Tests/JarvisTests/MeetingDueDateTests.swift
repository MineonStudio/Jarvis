@testable import Jarvis
import XCTest

final class MeetingDueDateTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = .gmt
        return result
    }

    private func resolved(_ text: String, year: Int = 2026, month: Int = 11, day: Int = 6) -> String {
        guard let anchor = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            XCTFail("Invalid test date")
            return ""
        }
        return MeetingDueDate.label(text, meetingDate: anchor, calendar: calendar)
    }

    func testSpokenMonthAndDay() {
        XCTAssertEqual(resolved("十一月十五号前"), "2026-11-15")
        XCTAssertEqual(resolved("11月15日之前"), "2026-11-15")
        XCTAssertEqual(resolved("二〇二七年一月五号"), "2027-01-05")
        XCTAssertEqual(resolved("明年一月五号"), "2027-01-05")
    }

    func testRelativeDeadlinesUseMeetingDay() {
        XCTAssertEqual(resolved("下周三之前"), "2026-11-11")
        XCTAssertEqual(resolved("下星期一"), "2026-11-09")
        XCTAssertEqual(resolved("本周日"), "2026-11-08")
        XCTAssertEqual(resolved("周三前"), "2026-11-11")
        XCTAssertEqual(resolved("明天"), "2026-11-07")
        XCTAssertEqual(resolved("后天"), "2026-11-08")
        XCTAssertEqual(resolved("大后天"), "2026-11-09")
    }

    func testCalendarBoundaries() {
        XCTAssertEqual(resolved("明天", month: 12, day: 31), "2027-01-01")
        XCTAssertEqual(resolved("下周一", month: 12, day: 31), "2027-01-04")
        XCTAssertEqual(resolved("后天", year: 2028, month: 2, day: 28), "2028-03-01")
    }

    func testLegacyAnnotationUsesDeadlineRatherThanMeetingDate() {
        XCTAssertEqual(resolved("下周三之前（由会议日期 2026-11-06 换算为 2026-11-11）"), "2026-11-11")
        XCTAssertEqual(resolved("2026-11-15"), "2026-11-15")
    }

    func testVagueAndInvalidDatesAreNotInvented() {
        XCTAssertEqual(resolved("春节前"), "春节前")
        XCTAssertEqual(resolved("未提及"), "未提及")
        XCTAssertEqual(resolved("2026-02-30"), "2026-02-30")
        XCTAssertEqual(resolved("二月三十号"), "二月三十号")
    }
}
