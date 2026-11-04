import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

enum JarvisPrivacyPermission: Hashable {
    case screenCapture
    case accessibility
    case microphone

    var settingsAnchor: String {
        switch self {
        case .screenCapture: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        case .microphone: "Privacy_Microphone"
        }
    }
}

enum JarvisRequiredPermission: String, CaseIterable, Identifiable, Equatable {
    case screenCapture
    case accessibility
    case microphone

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenCapture: "屏幕录制"
        case .accessibility: "辅助功能"
        case .microphone: "麦克风"
        }
    }

    var systemImage: String {
        switch self {
        case .screenCapture: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .microphone: "mic.fill"
        }
    }

    var privacyPermission: JarvisPrivacyPermission {
        switch self {
        case .screenCapture: .screenCapture
        case .accessibility: .accessibility
        case .microphone: .microphone
        }
    }
}

enum JarvisPrivacyPermissionAccess {
    static func isScreenCaptureTrusted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func isMicrophoneTrusted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func requestMicrophoneAccess(
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                completion(granted)
            }
        }
    }

    @discardableResult
    @MainActor
    static func requestAccessibilityAccess(
        using request: (CFDictionary?) -> Bool = AXIsProcessTrustedWithOptions
    ) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return request(options)
    }

    @discardableResult
    @MainActor
    static func openSettings(for permission: JarvisPrivacyPermission) -> Bool {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(permission.settingsAnchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)"
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }
}
