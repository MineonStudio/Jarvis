import AppKit
import ApplicationServices
@testable import Jarvis
import XCTest

final class WindowDragLayoutActivationTests: XCTestCase {
    func testEnableWaitsForPermissionAndCompletesOnlyOnce() {
        var activation = WindowDragLayoutActivation()
        XCTAssertFalse(activation.request(hasPermission: false))
        XCTAssertTrue(activation.awaitingPermission)
        XCTAssertFalse(activation.receivePermission(granted: false))
        XCTAssertTrue(activation.receivePermission(granted: true))
        XCTAssertFalse(activation.awaitingPermission)
        XCTAssertFalse(activation.receivePermission(granted: true))
    }

    func testCancellingPreventsALaterGrantFromEnablingTheFeature() {
        var activation = WindowDragLayoutActivation()
        XCTAssertFalse(activation.request(hasPermission: false))
        activation.cancel()
        XCTAssertFalse(activation.receivePermission(granted: true))
        XCTAssertTrue(activation.request(hasPermission: true))
        XCTAssertFalse(activation.awaitingPermission)
    }
}

@MainActor
final class WindowDragLayoutAuthorizationTests: XCTestCase {
    func testAuthorizationActivelyRequestsTheNativeSystemPrompt() {
        var requestCount = 0
        let granted = JarvisPrivacyPermissionAccess.requestAccessibilityAccess { options in
            requestCount += 1
            let key = "AXTrustedCheckOptionPrompt"
            XCTAssertEqual((options as? [String: Bool])?[key], true)
            return false
        }
        XCTAssertFalse(granted)
        XCTAssertEqual(requestCount, 1)
    }

    func testEnablePromptUsesTheSharedPermissionContentInSettings() {
        let prompt = JarvisTaskPermissionPrompt(permission: .accessibility, presentation: .settingsWindow)
        XCTAssertEqual(prompt.title, JarvisTaskPermissionPrompt(permission: .accessibility).title)
        XCTAssertEqual(prompt.message, JarvisTaskPermissionPrompt(permission: .accessibility).message)
        XCTAssertEqual(prompt.presentation, .settingsWindow)
    }
}
