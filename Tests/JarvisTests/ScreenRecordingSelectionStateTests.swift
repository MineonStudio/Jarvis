import AppKit
@testable import Jarvis
import XCTest

final class ScreenRecordingSelectionStateTests: XCTestCase {
    @MainActor
    func testRegionIsDiscardedWhenSwitchingModesAndStartingAnotherSelection() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ScreenRecordingCoordinator(repository: ScreenRecordingRepository(root: root))
        recorder.mode = .region
        recorder.region = CGRect(x: 20, y: 30, width: 300, height: 200)
        recorder.mode = .window
        XCTAssertNil(recorder.region)
        recorder.mode = .region
        recorder.region = CGRect(x: 20, y: 30, width: 300, height: 200)
        recorder.selectRegion()
        XCTAssertNil(recorder.region)
    }

    @MainActor
    func testRegionDoesNotSurviveDismissalOrSessionCompletion() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ScreenRecordingCoordinator(repository: ScreenRecordingRepository(root: root))
        recorder.mode = .region
        recorder.region = CGRect(x: 20, y: 30, width: 300, height: 200)
        recorder.dismissToolbar()
        XCTAssertNil(recorder.region)
        recorder.region = CGRect(x: 20, y: 30, width: 300, height: 200)
        recorder.finishSession()
        XCTAssertNil(recorder.region)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-selection-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
