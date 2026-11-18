import AppKit
@testable import Jarvis
import XCTest

/// 固定比例宫格的列数、列宽和卡片高度。
final class HistoryGridLayoutTests: XCTestCase {
    private let spacing = HistoryGridMetrics.clipboardGridSpacing

    private func width(available: CGFloat, target: CGFloat) -> CGFloat {
        HistoryGridColumns.cardWidth(availableWidth: available, targetWidth: target, spacing: spacing)
    }

    /// 一行正好铺满：n 张卡 + (n-1) 条缝 = 可用宽度。
    func testCardsFillTheRowExactly() {
        let target: CGFloat = 280
        for available in stride(from: 320.0, through: 2400.0, by: 37.0) {
            let card = width(available: available, target: target)
            let columns = HistoryGridColumns.columns(availableWidth: available, targetWidth: target, spacing: spacing)
            let used = CGFloat(columns) * card + CGFloat(columns - 1) * spacing
            XCTAssertEqual(used, available, accuracy: 0.01, "可用 \(available)：没铺满，右边留了 \(available - used)")
        }
    }

    /// 卡片大小贴着用户选的档位：最多比目标大一半，也不会小得离谱。
    func testCardWidthStaysNearTheTarget() {
        let target: CGFloat = 280
        for available in stride(from: 320.0, through: 2400.0, by: 23.0) {
            let card = width(available: available, target: target)
            XCTAssertLessThanOrEqual(card, target * 1.5, "可用 \(available)：卡片大得离谱")
            XCTAssertGreaterThanOrEqual(card, target * 0.66, "可用 \(available)：卡片比目标小太多")
        }
    }

    /// 窗口窄到放不下一张卡时按可用宽度收，别撑破容器。
    func testNarrowWindowShrinksTheCard() {
        XCTAssertLessThanOrEqual(width(available: 180, target: 280), 180)
        XCTAssertGreaterThan(width(available: 180, target: 280), 0)
    }

    /// 没量到宽度时（首帧）退回目标宽度，别算出一个奇怪的数。
    func testUnknownWidthFallsBackToTheTarget() {
        XCTAssertEqual(width(available: 0, target: 280), 280, accuracy: 0.001)
    }

    /// 比例恒为 16:9——这次改动唯一不能动的东西。
    func testCardHeightKeepsTheAspectRatio() {
        for cardWidth in [120.0, 200.0, 280.0, 411.5] as [CGFloat] {
            XCTAssertEqual(
                HistoryGridLayout.cardHeight(forCardWidth: cardWidth),
                cardWidth * 9 / 16,
                accuracy: 0.001
            )
        }
    }
}
