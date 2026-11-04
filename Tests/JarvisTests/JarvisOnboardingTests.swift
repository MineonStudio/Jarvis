@testable import Jarvis
import XCTest

@MainActor
final class JarvisOnboardingTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let suite = "JarvisOnboardingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Unable to create isolated defaults for onboarding tests.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }

    func testNewInstallationStartsWithExactlyOnePermissionPerPage() {
        withDefaults { defaults in
            let state = JarvisOnboardingState(defaults: defaults)
            XCTAssertFalse(state.isCompleted)
            for permission in JarvisRequiredPermission.allCases {
                XCTAssertEqual(state.step.permission, permission)
                state.advance()
            }
            XCTAssertEqual(state.step, .welcome)
            XCTAssertNil(state.step.permission)
            XCTAssertFalse(state.isCompleted)
            state.advance()
            XCTAssertEqual(state.step, .welcome)
            state.finish()
            XCTAssertTrue(JarvisOnboardingState(defaults: defaults).isCompleted)
        }
    }

    func testInterruptedFirstLaunchResumesEvenAfterInstallationIsRecorded() {
        withDefaults { defaults in
            let state = JarvisOnboardingState(defaults: defaults)
            state.advance()
            state.advance()
            defaults.set("development", forKey: JarvisInstallSource.defaultsKey)
            let restored = JarvisOnboardingState(defaults: defaults)
            XCTAssertEqual(restored.step, .microphone)
            XCTAssertFalse(restored.isCompleted)
            restored.goBack()
            XCTAssertEqual(restored.step, .accessibility)
        }
    }

    func testExistingInstallationKeepsNormalLaunchAndCanReplay() {
        withDefaults { defaults in
            defaults.set("direct-download", forKey: JarvisInstallSource.defaultsKey)
            let state = JarvisOnboardingState(defaults: defaults)
            XCTAssertTrue(state.isCompleted)
            state.restart()
            XCTAssertFalse(state.isCompleted)
            XCTAssertEqual(state.step, .screenCapture)
            XCTAssertFalse(JarvisOnboardingState(defaults: defaults).isCompleted)
        }
    }

    func testCannotFinishBeforeWelcomeOrGoBackBeforeFirstPage() {
        withDefaults { defaults in
            let state = JarvisOnboardingState(defaults: defaults)
            state.goBack()
            state.finish()
            XCTAssertEqual(state.step, .screenCapture)
            XCTAssertFalse(state.isCompleted)
        }
    }

    func testInvalidSavedStepFallsBackToFirstPage() {
        withDefaults { defaults in
            defaults.set(99, forKey: JarvisOnboardingState.stepKey)
            XCTAssertEqual(JarvisOnboardingState(defaults: defaults).step, .screenCapture)
        }
    }

    func testPreviousFinalPagesResumeAtWelcomeInShortenedFlow() {
        withDefaults { defaults in
            for index in [3, 4] {
                defaults.set(index, forKey: JarvisOnboardingState.stepKey)
                let state = JarvisOnboardingState(defaults: defaults)
                XCTAssertEqual(state.step, .welcome)
                XCTAssertNil(state.step.permission)
                state.goBack()
                XCTAssertEqual(state.step, .microphone)
            }
            XCTAssertEqual(JarvisOnboardingStep.allCases.count, 4)
        }
    }
}
