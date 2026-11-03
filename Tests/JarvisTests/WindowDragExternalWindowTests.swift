import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class WindowDragExternalWindowTests: XCTestCase {
    func testIndependentAppIsDetectedWithoutResolvingAXDuringDrag() async throws {
        let fixture = try await fixtureWindow()
        let pointer = CGPoint(x: fixture.midX, y: fixture.maxY - 15)
        let target = try XCTUnwrap(WindowDragTarget.capture(at: pointer, eventWindow: nil))
        XCTAssertNil(target.nativeWindow)
        XCTAssertNil(target.accessibilityWindow, "AX must be deferred until mouse-up")
        XCTAssertEqual(try XCTUnwrap(target.frame), fixture)
    }

    func testMissingPermissionRequestsAuthorizationInsteadOfSilentlyFailing() async throws {
        guard !JarvisPrivacyPermissionAccess.isAccessibilityTrusted() else {
            throw XCTSkip("This regression specifically exercises an untrusted process")
        }
        let fixture = try await fixtureWindow()
        let target = try XCTUnwrap(WindowDragTarget.capture(
            at: CGPoint(x: fixture.midX, y: fixture.maxY - 15), eventWindow: nil
        ))
        var permissionRequests = 0
        var feedback = ""
        let controller = WindowLayoutController { feedback = $0 }
        controller.onAccessibilityRequired = { permissionRequests += 1 }
        try controller.apply(.halfRight, to: target, on: XCTUnwrap(NSScreen.main))
        XCTAssertEqual(permissionRequests, 1)
        XCTAssertTrue(feedback.contains("辅助功能权限"))
        XCTAssertEqual(try XCTUnwrap(target.frame), fixture)
    }

    private func fixtureWindow() async throws -> CGRect {
        _ = NSApplication.shared
        guard let raw = ProcessInfo.processInfo.environment["JARVIS_WINDOW_LAYOUT_FIXTURE_PID"],
              let processID = Int(raw)
        else {
            throw XCTSkip("Run script/test_window_layout_external.sh for cross-process tests")
        }
        for _ in 0 ..< 30 {
            let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            if let info = list.first(where: { ($0[kCGWindowOwnerPID as String] as? Int) == processID }),
               let windowID = info[kCGWindowNumber as String] as? Int,
               let bounds = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: bounds)
            {
                let frame = WindowLayoutCoordinates.flipped(rect, primaryDisplayTop: NSScreen.screens.first?.frame.maxY ?? 0)
                let point = CGPoint(x: frame.midX, y: frame.maxY - 15)
                if NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == windowID {
                    return frame
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Fixture did not expose an unobstructed window")
        throw NSError(domain: "WindowLayoutFixture", code: 1)
    }
}
