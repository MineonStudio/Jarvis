@testable import Jarvis
import XCTest

@MainActor
final class HomeTemperatureTests: XCTestCase {
    private func floatBytes(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return (0 ..< 4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
    }

    func testDecodesSMCTemperatureFormats() {
        XCTAssertEqual(
            HomeTemperatureReader.decodeTemperature(type: HomeTemperatureReader.fourCC("flt "), bytes: floatBytes(63.5)),
            63.5
        )
        XCTAssertEqual(
            HomeTemperatureReader.decodeTemperature(type: HomeTemperatureReader.fourCC("sp78"), bytes: [0x3F, 0x80]),
            63.5
        )
    }

    func testRejectsUnavailableMalformedAndInvalidSensorReadings() {
        let floatType = HomeTemperatureReader.fourCC("flt ")
        for invalid: Float in [0, -1, 151, .nan, .infinity] {
            XCTAssertNil(HomeTemperatureReader.decodeTemperature(type: floatType, bytes: floatBytes(invalid)))
        }
        XCTAssertNil(HomeTemperatureReader.decodeTemperature(type: floatType, bytes: []))
        XCTAssertNil(HomeTemperatureReader.decodeTemperature(type: floatType, bytes: [1, 2]))
        XCTAssertNil(HomeTemperatureReader.decodeTemperature(type: HomeTemperatureReader.fourCC("ui32"), bytes: floatBytes(60)))
        XCTAssertNil(HomeTemperatureReader.decodeTemperature(type: HomeTemperatureReader.fourCC("sp78"), bytes: [0xFF, 0x00]))
    }

    func testOnlyKnownChipGenerationsUseTheirOwnSensorMappings() {
        let m4 = HomeTemperatureReader.sensorKeys(for: "Apple M4")
        XCTAssertTrue(m4.cpu.contains("Te05"))
        XCTAssertTrue(m4.cpu.contains("Tp01"))
        XCTAssertFalse(m4.cpu.contains("Tf04"))
        XCTAssertTrue(HomeTemperatureReader.sensorKeys(for: "Apple M4 Pro").cpu.contains("Tp01"))
        XCTAssertTrue(HomeTemperatureReader.sensorKeys(for: "Apple M3 Pro").cpu.contains("Tf04"))
        XCTAssertTrue(HomeTemperatureReader.sensorKeys(for: "Unknown").cpu.isEmpty)
        XCTAssertTrue(HomeTemperatureReader.sensorKeys(for: "Apple M9").gpu.isEmpty)
        XCTAssertTrue(HomeTemperatureReader.sensorKeys(for: "Apple M10").cpu.isEmpty)
    }

    func testFormatsTemperaturesAndKeepsUnavailableValuesDistinct() {
        XCTAssertEqual(HomeDashboardFormatting.temperature(63.6), "64°C")
        XCTAssertEqual(HomeDashboardFormatting.temperature(nil), "—")
        XCTAssertEqual(HomeDashboardFormatting.temperature(.nan), "—")
        XCTAssertEqual(HomeDashboardFormatting.temperature(0), "—")
    }

    func testTemperatureSamplesUpdateSnapshotAndClearUnavailableReadings() {
        let monitor = HomeSystemMonitor()
        monitor.record(HomeSystemSnapshot(temperatures: HomeTemperatures(cpu: 74, gpu: 55)))
        XCTAssertEqual(monitor.snapshot.temperatures, HomeTemperatures(cpu: 74, gpu: 55))

        monitor.record(HomeSystemSnapshot())
        XCTAssertNil(monitor.snapshot.temperatures.cpu)
        XCTAssertNil(monitor.snapshot.temperatures.gpu)
    }

    func testThermalStatusFollowsAllFourSystemStates() {
        XCTAssertEqual(HomeThermalStatus(.nominal), .normal)
        XCTAssertEqual(HomeThermalStatus(.fair), .warm)
        XCTAssertEqual(HomeThermalStatus(.serious), .hot)
        XCTAssertEqual(HomeThermalStatus(.critical), .critical)
    }

    func testActionableGuidanceOnlyAppearsForHighThermalPressure() {
        XCTAssertNil(HomeThermalStatus.normal.guidance)
        XCTAssertNil(HomeThermalStatus.warm.guidance)
        XCTAssertNil(HomeThermalStatus.unknown.guidance)
        XCTAssertEqual(HomeThermalStatus.hot.guidance, "温度较高，建议减少高负载任务。")
        XCTAssertEqual(HomeThermalStatus.critical.guidance, "需要降温，请暂停高负载任务。")
        XCTAssertEqual(HomeThermalStatus.unknown.title, "未知")
    }

    func testThermalStatusDoesNotUseFixedCelsiusThresholds() {
        let monitor = HomeSystemMonitor()
        monitor.record(HomeSystemSnapshot(temperatures: HomeTemperatures(cpu: 95, gpu: 90), thermalStatus: .normal))
        XCTAssertEqual(monitor.snapshot.thermalStatus, .normal)
        XCTAssertEqual(monitor.snapshot.thermalStatus.temperatureReminder(for: 95), "温度正常")
        XCTAssertNil(monitor.snapshot.thermalStatus.guidance)

        monitor.record(HomeSystemSnapshot(temperatures: HomeTemperatures(cpu: 70, gpu: 65), thermalStatus: .hot))
        XCTAssertEqual(monitor.snapshot.thermalStatus, .hot)
        XCTAssertNotNil(monitor.snapshot.thermalStatus.guidance)

        monitor.record(HomeSystemSnapshot(thermalStatus: .critical))
        XCTAssertEqual(monitor.snapshot.thermalStatus, .critical, "传感器不可读时仍保留系统散热警告")
    }

    func testTemperatureRemindersHandleEveryStatusAndUnavailableSensors() {
        XCTAssertEqual(HomeThermalStatus.normal.temperatureReminder(for: 60), "温度正常")
        XCTAssertEqual(HomeThermalStatus.warm.temperatureReminder(for: 60), "温度偏高")
        XCTAssertEqual(HomeThermalStatus.hot.temperatureReminder(for: nil), "温度较高")
        XCTAssertEqual(HomeThermalStatus.critical.temperatureReminder(for: nil), "需要降温")
        XCTAssertEqual(HomeThermalStatus.unknown.temperatureReminder(for: 60), "状态未知")
        for invalid in [nil, 0, -1, 151, Double.nan, .infinity] {
            XCTAssertEqual(HomeThermalStatus.normal.temperatureReminder(for: invalid), "温度不可用")
        }
    }
}
