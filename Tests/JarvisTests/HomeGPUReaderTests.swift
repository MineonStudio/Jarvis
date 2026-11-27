@testable import Jarvis
import XCTest

@MainActor
final class HomeGPUReaderTests: XCTestCase {
    func testUsesWholeDeviceUtilizationInsteadOfRendererOrTilerLoad() {
        let statistics: [String: Any] = [
            "Device Utilization %": 30,
            "Renderer Utilization %": 29,
            "Tiler Utilization %": 12
        ]
        XCTAssertEqual(HomeGPUReader.fraction(from: statistics), 0.3)
        XCTAssertEqual(HomeGPUReader.fraction(from: ["GPU Activity(%)": 42.5]), 0.425)
        XCTAssertEqual(HomeGPUReader.fraction(from: ["Device Utilization %": 0]), 0)
        XCTAssertEqual(HomeGPUReader.fraction(from: ["Device Utilization %": 100]), 1)
    }

    func testRejectsUnavailableAndMalformedUtilization() {
        XCTAssertNil(HomeGPUReader.fraction(from: [:]))
        for invalid: Any in [-1, 101, Double.nan, Double.infinity, true, "30"] {
            XCTAssertNil(HomeGPUReader.fraction(from: ["Device Utilization %": invalid]))
        }
        XCTAssertNil(HomeGPUReader.fraction(from: ["Renderer Utilization %": 50]))
        XCTAssertEqual(HomeGPUReader.fraction(from: ["Device Utilization %": -1, "GPU Activity(%)": 25]), 0.25)
    }

    func testGPUUsageUpdatesImmediatelyAndUnavailableReadingsClear() {
        let monitor = HomeSystemMonitor()
        monitor.record(HomeSystemSnapshot(cpu: 0.5, gpu: 0.3))
        monitor.record(HomeSystemSnapshot(gpu: 0.4), isBaseline: true)
        XCTAssertEqual(monitor.snapshot.cpu, 0.5)
        XCTAssertEqual(monitor.snapshot.gpu, 0.4)

        monitor.record(HomeSystemSnapshot(), isBaseline: true)
        XCTAssertNil(monitor.snapshot.gpu, "GPU 无需等待差值采样，读取失败应显示不可用")
    }
}
