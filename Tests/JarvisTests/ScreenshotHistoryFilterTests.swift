import Foundation
@testable import Jarvis
import XCTest

final class ScreenshotHistoryFilterTests: XCTestCase {
    func testHistoryFilterControlsShareTheirPresentationMetrics() {
        XCTAssertEqual(HistoryGridMetrics.historyPanelInset, 12)
        XCTAssertEqual(HistoryGridMetrics.historyFilterToGridSpacing, 12)
        XCTAssertEqual(HistoryGridMetrics.clipboardFilterToGridSpacing, 12)
        XCTAssertEqual(HistoryGridMetrics.clipboardGridSpacing, 12)
        XCTAssertEqual(
            HistoryGridMetrics.clipboardSearchFieldHeight,
            HistoryGridMetrics.topControlHeight
        )
        XCTAssertEqual(
            HistoryGridMetrics.topControlHeight,
            HistoryGridMetrics.clipboardActionButtonSize
        )
        XCTAssertEqual(
            HistoryGridMetrics.screenshotFilterBarHeight,
            HistoryGridMetrics.topControlHeight
        )
        XCTAssertEqual(
            ScreenshotTimeFilter.displayCases,
            [.threeDays, .sevenDays, .oneMonth, .all]
        )
        XCTAssertEqual(
            ClipboardTimeFilter.allCases,
            [.threeDays, .sevenDays, .oneMonth, .all]
        )
        XCTAssertEqual(ScreenshotTimeFilter.all.title, "全部时间")
    }

    func testTimeFiltersUseUpdatedAtAndCalendarBoundaries() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let items = try [
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))),
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now))),
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .month, value: -2, to: now))),
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .month, value: -7, to: now)))
        ]

        XCTAssertEqual(
            ScreenshotTimeFilterLogic.filteredItems(
                from: items,
                filter: .all,
                now: now,
                calendar: calendar
            ).count,
            4
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .threeDays,
                in: items,
                now: now,
                calendar: calendar
            ),
            1
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .sevenDays,
                in: items,
                now: now,
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .oneMonth,
                in: items,
                now: now,
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .halfYear,
                in: items,
                now: now,
                calendar: calendar
            ),
            3
        )
    }

    func testSearchMatchesRecognizedTextInsideTheSelectedTimeRange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let recent = item(updatedAt: now.addingTimeInterval(-3600), contentHash: "recent")
        let old = item(updatedAt: now.addingTimeInterval(-10 * 24 * 3600), contentHash: "old")
        let blank = item(updatedAt: now.addingTimeInterval(-3600), contentHash: "blank")
        let unindexed = item(updatedAt: now.addingTimeInterval(-3600))
        let items = [recent, old, blank, unindexed]
        let imageText = [
            "recent": "这里有大模型",
            "old": "这里有大模型",
            "blank": ""
        ]

        XCTAssertEqual(
            ScreenshotTimeFilterLogic.filteredItems(
                from: items,
                filter: .threeDays,
                searchText: "大模型",
                imageTextByHash: imageText,
                now: now,
                calendar: calendar
            ).map(\.id),
            [recent.id]
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.filteredItems(
                from: items,
                filter: .all,
                searchText: "大模型",
                imageTextByHash: imageText,
                now: now,
                calendar: calendar
            ).map(\.id),
            [recent.id, old.id]
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.filteredItems(
                from: items,
                filter: .threeDays,
                now: now,
                calendar: calendar
            ).map(\.id),
            [recent.id, blank.id, unindexed.id]
        )
        XCTAssertTrue(
            ScreenshotTimeFilterLogic.filteredItems(
                from: [blank, unindexed],
                filter: .all,
                searchText: "大",
                imageTextByHash: imageText
            ).isEmpty
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.filteredItems(
                from: [recent],
                filter: .all,
                searchText: "api",
                imageTextByHash: ["recent": "使用 API"]
            ).map(\.id),
            [recent.id]
        )
    }

    private func item(updatedAt: Date, contentHash: String? = nil) -> ScreenshotHistoryItem {
        ScreenshotHistoryItem(
            id: UUID(),
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            fileName: "screenshot-\(UUID().uuidString).png",
            contentHash: contentHash
        )
    }
}
