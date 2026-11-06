@testable import Jarvis
import XCTest

final class HomeMacModelYearTests: XCTestCase {
    private func catalog() throws -> HomeMacModelYear.Catalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/MacModels/model-years.json"))
        return try JSONDecoder().decode(HomeMacModelYear.Catalog.self, from: data)
    }

    func testAllMacFamiliesHaveVerifiedYears() throws {
        let catalog = try catalog()
        let examples = [
            "Mac16,10": "2024 年款", "MacBookPro18,3": "2021 年款",
            "Mac15,12": "2024 年款", "Mac16,2": "2024 年款",
            "Mac16,9": "2025 年款", "Mac14,8": "2023 年款", "MacBook10,1": "2017 年款",
            "Mac17,5": "2026 年款"
        ]
        XCTAssertEqual(catalog.sources.count, 8)
        XCTAssertGreaterThanOrEqual(catalog.models.count, 150)
        for (identifier, expected) in examples {
            XCTAssertEqual(HomeMacModelYear.label(identifier: identifier, modelNumber: nil, catalog: catalog), expected)
        }
    }

    func testPartNumberDisambiguatesSharedIdentifiersWithoutGuessing() throws {
        let catalog = try catalog()
        XCTAssertEqual(HomeMacModelYear.label(identifier: "MacBookAir7,2", modelNumber: "MQD32CH/A", catalog: catalog), "2017 年款")
        XCTAssertEqual(HomeMacModelYear.label(identifier: "MacBookAir7,2", modelNumber: "MJVE2LL/A", catalog: catalog), "2015 年款")
        XCTAssertEqual(HomeMacModelYear.label(identifier: "MacBookAir7,2", modelNumber: nil, catalog: catalog), "2015／2017 年款")
        XCTAssertEqual(HomeMacModelYear.label(identifier: "MacBookAir7,2", modelNumber: "unknown", catalog: catalog), "2015／2017 年款")
        XCTAssertNil(HomeMacModelYear.label(identifier: "Mac999,99", modelNumber: "MQD32CH/A", catalog: catalog))
    }

    func testCatalogPartYearsStayWithinModelYears() throws {
        for record in try catalog().models.values {
            XCTAssertFalse(record.years.isEmpty)
            XCTAssertEqual(record.years, Array(Set(record.years)).sorted())
            for years in record.parts.values {
                XCTAssertTrue(Set(years).isSubset(of: record.years))
            }
        }
    }
}
