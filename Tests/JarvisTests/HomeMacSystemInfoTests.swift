@testable import Jarvis
import XCTest

final class HomeMacSystemInfoTests: XCTestCase {
    func testSystemReportMatchesStartupPhysicalDriveAndIgnoresAttachedStorage() throws {
        let data = Data(#"""
        {
          "SPHardwareDataType": [{"machine_name":"Mac mini","machine_model":"Mac16,10","model_number":"MCYT4CH/A","chip_type":"Apple M4","physical_memory":"24 GB"}],
          "SPSoftwareDataType": [{"os_version":"macOS 27.2 (26B123)"}],
          "SPStorageDataType": [
            {"mount_point":"/Volumes/External","size_in_bytes":2000000000000,"physical_drive":{"device_name":"External"}},
            {"mount_point":"/","size_in_bytes":494384795648,"physical_drive":{"device_name":"APPLE SSD","medium_type":"ssd"}}
          ],
          "SPNVMeDataType": [{"_items":[
            {"device_model":"External","size_in_bytes":2000000000000},
            {"device_model":"APPLE SSD","size_in_bytes":500277792768}
          ]}]
        }
        """#.utf8)
        let info = try HomeMacSystemInfo.parse(data)
        XCTAssertEqual(info.modelName, "Mac mini")
        XCTAssertEqual(info.modelIdentifier, "Mac16,10")
        XCTAssertEqual(info.modelNumber, "MCYT4CH/A")
        XCTAssertEqual(info.chip, "Apple M4")
        XCTAssertEqual(info.memory, "24 GB")
        XCTAssertEqual(info.systemVersion, "macOS 27.2 (26B123)")
        XCTAssertEqual(info.storageBytes, 500_277_792_768)
        XCTAssertEqual(info.storageMedium, "ssd")
    }

    func testUnavailablePhysicalDriveFallsBackToStartupVolumeWithoutGuessing() throws {
        let data = Data(#"""
        {"SPStorageDataType":[{"mount_point":"/","size_in_bytes":494384795648}]}
        """#.utf8)
        let info = try HomeMacSystemInfo.parse(data)
        XCTAssertEqual(info.storageBytes, 494_384_795_648)
        XCTAssertNil(info.storageMedium)
        XCTAssertFalse(info.chip.isEmpty)
        XCTAssertFalse(info.memory.isEmpty)
        XCTAssertFalse(info.systemVersion.isEmpty)
        XCTAssertThrowsError(try HomeMacSystemInfo.parse(Data("invalid".utf8)))
    }
}
