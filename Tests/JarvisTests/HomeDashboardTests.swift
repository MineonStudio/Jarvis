import Darwin
@testable import Jarvis
import XCTest

@MainActor
final class HomeDashboardTests: XCTestCase {
    func testDashboardCanvasFitsSmallAndLargeWindowsWithoutScrolling() {
        for size in [CGSize(width: 593, height: 394), CGSize(width: 700, height: 440), CGSize(width: 1050, height: 600), CGSize(width: 1600, height: 1000)] {
            let layout = HomeDashboardLayout(size: size)
            XCTAssertGreaterThanOrEqual(layout.canvas.width, 900)
            XCTAssertGreaterThanOrEqual(layout.canvas.height, 620)
            XCTAssertEqual(layout.canvas.width * layout.scale, size.width, accuracy: 0.001)
            XCTAssertEqual(layout.canvas.height * layout.scale, size.height, accuracy: 0.001)
        }
    }

    func testTallWindowKeepsMonitoringCardsCompact() {
        let content: CGFloat = 1400
        let bands = HomeDashboardLayout.bands(contentHeight: content)
        XCTAssertEqual(bands.header, 60)
        XCTAssertEqual(bands.metrics, 104, accuracy: 0.001)
        XCTAssertEqual(bands.ranking, content * 0.19, accuracy: 0.001)
        XCTAssertEqual(
            bands.header + bands.metrics + bands.overview + bands.ranking + HomeDashboardLayout.bandSpacing,
            content,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(bands.ranking, 128)
        XCTAssertGreaterThan(bands.overview, bands.metrics)
    }

    func testCardHeightsAndRowGapsStayConsistentAcrossWindowSizes() {
        for content: CGFloat in [596, 604, 680, 900, 1400] {
            for showsGuidance in [false, true] {
                let bands = HomeDashboardLayout.bands(contentHeight: content, showsThermalGuidance: showsGuidance)
                XCTAssertEqual(bands.metrics, showsGuidance ? 136 : 104)
                XCTAssertGreaterThan(bands.overview, 240, "日历和系统概览在小窗口及高温提示下仍需完整展示")
                XCTAssertEqual(
                    bands.header + bands.metrics + bands.overview + bands.ranking + HomeDashboardLayout.bandSpacing,
                    content,
                    accuracy: 0.001
                )
            }
        }
    }

    func testCalendarRowsCapWhenTheCardIsTallAndShrinkWhenItIsShort() {
        XCTAssertEqual(HomeDashboardLayout.calendarRowHeight(availableHeight: 600, weeks: 6), 52)
        XCTAssertEqual(HomeDashboardLayout.calendarRowHeight(availableHeight: 180, weeks: 6), 30)
        XCTAssertEqual(HomeDashboardLayout.calendarRowHeight(availableHeight: 4, weeks: 6), 1)
        XCTAssertEqual(HomeDashboardLayout.calendarRowHeight(availableHeight: 40, weeks: 0), 40)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        value.firstWeekday = 2
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) else {
            XCTFail("Invalid test date")
            return .distantPast
        }
        return value
    }

    func testCalendarAlignsWeekdaysAndIncludesEveryDay() {
        let days = HomeDashboardFormatting.monthDays(containing: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(days.prefix(6).compactMap { $0 }.count, 0) // November 1 is Sunday.
        XCTAssertEqual(days.compactMap { $0 }.count, 30)
        XCTAssertEqual(days[6], date(2026, 11, 1, hour: 0))
        XCTAssertEqual(days.last, date(2026, 11, 30, hour: 0))
        let leap = HomeDashboardFormatting.monthDays(containing: date(2028, 2, 1), calendar: calendar)
        XCTAssertEqual(leap.compactMap { $0 }.count, 29)
    }

    func testGreetingUsesLocalHour() {
        XCTAssertEqual(HomeDashboardFormatting.greeting(at: date(2026, 11, 6, hour: 7), calendar: calendar), "上午好")
        XCTAssertEqual(HomeDashboardFormatting.greeting(at: date(2026, 11, 6, hour: 15), calendar: calendar), "下午好")
        XCTAssertEqual(HomeDashboardFormatting.greeting(at: date(2026, 11, 6, hour: 20), calendar: calendar), "晚上好")
        XCTAssertEqual(HomeDashboardFormatting.greeting(at: date(2026, 11, 6, hour: 2), calendar: calendar), "夜深了")
    }

    func testMonthNavigationStartsAtFirstDayAcrossYearAndLeapBoundaries() {
        XCTAssertEqual(
            HomeDashboardFormatting.shiftedMonth(from: date(2026, 12, 31), by: 1, calendar: calendar),
            date(2027, 1, 1, hour: 0)
        )
        XCTAssertEqual(
            HomeDashboardFormatting.shiftedMonth(from: date(2028, 3, 31), by: -1, calendar: calendar),
            date(2028, 2, 1, hour: 0)
        )
    }

    func testCPULoadUsesTickDeltasAndHandlesWraparound() {
        XCTAssertEqual(
            HomeSystemSampler.cpuFraction(previous: [10, 10, 10, 10], current: [20, 30, 80, 10]) ?? -1, 0.3,
            accuracy: 0.0001
        )
        XCTAssertNil(HomeSystemSampler.cpuFraction(previous: [0, 0, 0, 0], current: [0, 0, 0, 0]))
        XCTAssertNil(HomeSystemSampler.cpuFraction(previous: [], current: [1, 2, 3, 4]))
        let wrapped = HomeSystemSampler.cpuFraction(previous: [UInt32.max, 0, 0, 0], current: [1, 0, 2, 0])
        XCTAssertEqual(wrapped, 0.5)
    }

    func testNetworkRatesRejectCounterResetsAndZeroIntervals() {
        XCTAssertEqual(HomeSystemSampler.rate(previous: 100, current: 1100, elapsed: 2), 500)
        XCTAssertNil(HomeSystemSampler.rate(previous: 1100, current: 100, elapsed: 2))
        XCTAssertNil(HomeSystemSampler.rate(previous: 100, current: 1100, elapsed: 0))
    }

    func testDiskUsedAndPercentageShareTheSameCapacity() {
        let snapshot = HomeSystemSnapshot(diskAvailable: 700, diskTotal: 1000)
        XCTAssertEqual(snapshot.diskUsed, 300)
        XCTAssertEqual(snapshot.diskFraction, 0.3)
        XCTAssertEqual(HomeSystemSnapshot(diskAvailable: 1200, diskTotal: 1000).diskUsed, 0)
        XCTAssertNil(HomeSystemSnapshot(diskAvailable: 0, diskTotal: 0).diskUsed)
        XCTAssertNil(HomeSystemSnapshot(diskAvailable: nil, diskTotal: 1000).diskUsed)
    }

    func testUnavailableDataIsNotDisplayedAsZero() {
        XCTAssertEqual(HomeDashboardFormatting.percent(nil), "—")
        XCTAssertEqual(HomeDashboardFormatting.rate(nil), "—")
        XCTAssertEqual(HomeDashboardFormatting.rate(0), "0 B/s")
        XCTAssertEqual(HomeDashboardFormatting.rate(1024), "1.0 KB/s")
        XCTAssertEqual(HomeDashboardFormatting.rate(2 * 1024 * 1024), "2.0 MB/s")
        XCTAssertEqual(HomeDashboardFormatting.percent(.nan), "—")
        XCTAssertEqual(HomeDashboardFormatting.percent(2), "100%")
        XCTAssertEqual(HomeDashboardFormatting.uptime(2 * 86400 + 6 * 3600), "2 天 6 小时")
        let snapshot = HomeSystemSnapshot(memoryUsed: nil, diskAvailable: nil, diskTotal: nil)
        XCTAssertNil(snapshot.memoryFraction)
        XCTAssertNil(snapshot.diskFraction)
    }

    func testReturningHomePreservesRatesDuringWarmup() {
        let monitor = HomeSystemMonitor()
        monitor.record(HomeSystemSnapshot(cpu: 0.42, memoryUsed: 100, upload: 1024, download: 2048))

        // A fresh sampler has current memory but no CPU/network deltas yet.
        monitor.record(HomeSystemSnapshot(memoryUsed: 200), isBaseline: true)

        XCTAssertEqual(monitor.snapshot.cpu, 0.42)
        XCTAssertEqual(monitor.snapshot.upload, 1024)
        XCTAssertEqual(monitor.snapshot.download, 2048)
        XCTAssertEqual(monitor.snapshot.memoryUsed, 200)

        monitor.record(HomeSystemSnapshot(cpu: 0.25, upload: 100, download: 200))

        XCTAssertEqual(monitor.snapshot.cpu, 0.25)
        XCTAssertEqual(monitor.snapshot.upload, 100)
        XCTAssertEqual(monitor.snapshot.download, 200)
    }

    func testFirstVisitDoesNotInventRatesBeforeTheyAreMeasured() {
        let monitor = HomeSystemMonitor()
        monitor.record(HomeSystemSnapshot(memoryUsed: 200), isBaseline: true)

        XCTAssertNil(monitor.snapshot.cpu)
        XCTAssertNil(monitor.snapshot.upload)
        XCTAssertNil(monitor.snapshot.download)
    }

    func testUnavailableRatesAfterWarmupAreNotMaskedByCachedValues() {
        let monitor = HomeSystemMonitor()
        monitor.record(HomeSystemSnapshot(cpu: 0.42, upload: 1024, download: 2048))
        monitor.record(HomeSystemSnapshot())

        XCTAssertNil(monitor.snapshot.cpu)
        XCTAssertNil(monitor.snapshot.upload)
        XCTAssertNil(monitor.snapshot.download)
    }

    func testSystemSamplerReturnsRealBoundedResources() async throws {
        let sampler = HomeSystemSampler()
        let first = await sampler.sample()
        XCTAssertGreaterThan(first.memoryTotal, 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(first.memoryUsed), first.memoryTotal)
        XCTAssertGreaterThan(try XCTUnwrap(first.diskTotal), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(first.diskAvailable), try XCTUnwrap(first.diskTotal))
        // The kernel can cache host statistics for subsecond requests.
        var cpuValue: Double?
        for _ in 0 ..< 10 {
            try await Task.sleep(for: .milliseconds(200))
            cpuValue = await sampler.sample().cpu
            if cpuValue != nil {
                break
            }
        }
        let cpu = try XCTUnwrap(cpuValue)
        XCTAssertTrue((0 ... 1).contains(cpu))
    }
}
