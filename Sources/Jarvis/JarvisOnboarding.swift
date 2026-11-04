import Foundation
import Observation

enum JarvisOnboardingLayout {
    static let columnWidth: CGFloat = 400
    static let columnSpacing: CGFloat = 48
    static let contentInset: CGFloat = 40
    static let sectionSpacing: CGFloat = 28
}

enum JarvisOnboardingStep: Int, CaseIterable, Identifiable {
    case screenCapture, accessibility, microphone, welcome

    var id: Int {
        rawValue
    }

    var permission: JarvisRequiredPermission? {
        switch self {
        case .screenCapture: .screenCapture
        case .accessibility: .accessibility
        case .microphone: .microphone
        case .welcome: nil
        }
    }

    var title: String {
        switch self {
        case .screenCapture: "把屏幕上的灵感留在手边，随手截图、标注、翻译或录屏。"
        case .accessibility: "让窗口各就各位，用拖拽轻松布局，为手头的事腾出空间。"
        case .microphone: "专心交流，把会议录音、语音转写与纪要整理交给 Jarvis。"
        case .welcome: "欢迎使用 Jarvis。日常工具都在一起，少一点琐碎，多一点专注。"
        }
    }
}

/// Persist navigation separately from authorization. Skipping a page never
/// grants access, and permission changes never dismiss the welcome page.
@MainActor
@Observable
final class JarvisOnboardingState {
    static let completedKey = "jarvis.onboarding.completed"
    static let stepKey = "jarvis.onboarding.step"
    private(set) var step: JarvisOnboardingStep
    private(set) var isCompleted: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedStep = defaults.integer(forKey: Self.stepKey)
        // The old five-page flow ended at index 4. Both its last permission
        // page (3) and welcome page (4) now resume at the welcome page (3).
        step = JarvisOnboardingStep(rawValue: savedStep) ?? (savedStep == 4 ? .welcome : .screenCapture)
        if defaults.object(forKey: Self.completedKey) != nil {
            isCompleted = defaults.bool(forKey: Self.completedKey)
        } else {
            // Existing installations retain their normal launch behavior.
            isCompleted = defaults.object(forKey: JarvisInstallSource.defaultsKey) != nil
            defaults.set(isCompleted, forKey: Self.completedKey)
        }
    }

    func advance() {
        guard let next = JarvisOnboardingStep(rawValue: step.rawValue + 1) else { return }
        move(to: next)
    }

    func goBack() {
        guard let previous = JarvisOnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous)
    }

    func finish() {
        guard step == .welcome else { return }
        isCompleted = true
        defaults.set(true, forKey: Self.completedKey)
    }

    func restart() {
        isCompleted = false
        defaults.set(false, forKey: Self.completedKey)
        move(to: .screenCapture)
    }

    private func move(to step: JarvisOnboardingStep) {
        self.step = step
        defaults.set(step.rawValue, forKey: Self.stepKey)
    }
}
