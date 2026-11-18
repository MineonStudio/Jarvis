@testable import Jarvis
import XCTest

final class JustifiedGalleryLayoutTests: XCTestCase {
    func testMixedMediaFillsTheRowAndKeepsEachAspectRatio() throws {
        let ratios: [CGFloat] = [16 / 9, 9 / 16, 4 / 3, 16 / 9, 16 / 9]
        let rows = JustifiedGalleryLayout.rows(aspectRatios: ratios, availableWidth: 900)
        let row = try XCTUnwrap(rows.first)

        XCTAssertEqual(row.indices, 0 ..< 4)
        XCTAssertEqual(row.widths.reduce(0, +) + JustifiedGalleryLayout.spacing * 3, 900, accuracy: 0.001)
        for (width, ratio) in zip(row.widths, ratios[row.indices]) {
            XCTAssertEqual(width / row.height, ratio, accuracy: 0.001)
        }
    }

    func testLastRowKeepsTheDefaultWallpaperSizeAndScalesWithZoom() throws {
        let ratio = JustifiedGalleryLayout.aspectRatio(width: 1080, height: 1920)
        let regular = try XCTUnwrap(JustifiedGalleryLayout.rows(aspectRatios: [ratio], availableWidth: 900).first)
        let large = try XCTUnwrap(JustifiedGalleryLayout.rows(
            aspectRatios: [ratio], availableWidth: 900, scale: 1.16
        ).first)

        XCTAssertEqual(regular.height, 158 * 1.20, accuracy: 0.001)
        XCTAssertEqual(regular.widths[0], regular.height * ratio, accuracy: 0.001)
        XCTAssertEqual(large.height, regular.height * 1.16, accuracy: 0.001)
    }

    func testSinglePanoramaFitsANarrowViewport() throws {
        let row = try XCTUnwrap(JustifiedGalleryLayout.rows(aspectRatios: [8], availableWidth: 280).first)

        XCTAssertEqual(row.widths[0], 280, accuracy: 0.001)
        XCTAssertEqual(row.height, 35, accuracy: 0.001)
        XCTAssertEqual(JustifiedGalleryLayout.aspectRatio(width: 0, height: 0), 16 / 9, accuracy: 0.001)
    }
}
