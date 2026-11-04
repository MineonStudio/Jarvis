import AppKit
import Foundation

enum JarvisPermissionPromptPresentation: Equatable {
    case mainWindow
    case settingsWindow
}

struct JarvisTaskPermissionPrompt: Equatable {
    let permission: JarvisRequiredPermission
    var presentation: JarvisPermissionPromptPresentation = .mainWindow

    var title: String {
        switch permission {
        case .screenCapture: "截图和会议记录需要屏幕录制权限"
        case .accessibility: "窗口布局需要辅助功能权限"
        case .microphone: "会议记录和网页功能需要麦克风权限"
        }
    }

    var message: String {
        switch permission {
        case .screenCapture: "macOS 需要授予屏幕录制权限，Jarvis 才能截图，并采集会议的系统音频。"
        case .accessibility: "macOS 需要授予辅助功能权限，Jarvis 才能调整其他应用窗口的位置和大小。"
        case .microphone: "macOS 需要授予麦克风权限，Jarvis 才能录取会议声音或使用网页麦克风功能。"
        }
    }
}

extension AppModel {
    func isRequiredPermissionGranted(_ permission: JarvisRequiredPermission) -> Bool {
        switch permission {
        case .screenCapture: screenCapturePermissionGranted
        case .accessibility: accessibilityPermissionGranted
        case .microphone: microphonePermissionGranted
        }
    }

    func clearAllPrivacyPermissionsAndRestart() {
        // 在退出之前同步做重置：失败时弹框告知并停下来，否则用户在应用
        // 已经退出的情况下看不到任何失败提示。
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? JarvisAppIdentity.bundleIdentifier
        do {
            try JarvisPrivacyPermissionReset.reset(bundleIdentifier: bundleIdentifier)
        } catch {
            let alert = NSAlert()
            alert.messageText = "权限重置失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        shouldRelaunchAfterTermination = true
        NSApp.terminate(nil)
    }

    func performPermissionResetAndRelaunchIfNeeded() {
        guard shouldRelaunchAfterTermination else { return }
        shouldRelaunchAfterTermination = false
        relaunchCurrentApp()
    }

    func cancelPermissionResetAndRelaunch() {
        shouldRelaunchAfterTermination = false
    }

    private func relaunchCurrentApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            showToast("重启失败")
        }
    }

    func promptForTaskPermission(
        _ permission: JarvisRequiredPermission,
        presentation: JarvisPermissionPromptPresentation = .mainWindow
    ) {
        refreshPermissionStatus()
        guard !isRequiredPermissionGranted(permission) else { return }
        taskPermissionPrompt = JarvisTaskPermissionPrompt(permission: permission, presentation: presentation)
        if presentation == .mainWindow {
            JarvisMenuBarController.shared.reopenMainWindow()
        }
    }

    func dismissTaskPermissionPrompt() {
        if taskPermissionPrompt?.permission == .accessibility {
            windowDragLayoutActivation.cancel()
            accessibilityPermissionPollTask?.cancel()
            accessibilityPermissionPollTask = nil
        }
        taskPermissionPrompt = nil
    }

    func handleTaskPermissionPromptAction() {
        guard let prompt = taskPermissionPrompt else { return }
        // Hand off to macOS without keeping our explanation over the window.
        // Do not use dismissTaskPermissionPrompt(): authorizing a pending
        // window-layout activation must still enable it when access is granted.
        taskPermissionPrompt = nil
        requestRequiredPermission(prompt.permission)
    }

    func refreshPermissionStatus() {
        screenCapturePermissionGranted = screenshotController.hasScreenCaptureAccess
        accessibilityPermissionGranted = windowLayoutController?.isAccessibilityTrusted ?? false
        microphonePermissionGranted = JarvisPrivacyPermissionAccess.isMicrophoneTrusted()
        completePendingWindowDragLayoutEnableIfAllowed()
        if let prompt = taskPermissionPrompt, isRequiredPermissionGranted(prompt.permission) {
            taskPermissionPrompt = nil
        }
        if accessibilityPermissionGranted {
            accessibilityPermissionPollTask?.cancel()
            accessibilityPermissionPollTask = nil
        }
    }

    func requestRequiredPermission(_ permission: JarvisRequiredPermission) {
        switch permission {
        case .screenCapture:
            _ = requestScreenCapturePermission()
        case .accessibility:
            requestAccessibilityPermission()
        case .microphone:
            requestMicrophonePermission()
        }
    }

    @discardableResult
    func requestScreenCapturePermission() -> Bool {
        let granted = screenshotController.requestScreenCaptureAccess()
        refreshPermissionStatus()
        if !granted {
            screenshotController.openScreenCaptureSettings()
            showToast("请在系统设置的屏幕录制中开启Jarvis")
        } else {
            showToast("屏幕录制权限已开启")
        }
        return granted
    }

    func requestAccessibilityPermission() {
        let granted = windowLayoutController?.requestAccessibilityAccess() ?? false
        refreshPermissionStatus()
        statusMessage = granted
            ? "辅助功能权限已开启"
            : "已向 macOS 请求辅助功能权限，请完成系统授权"
        showToast(statusMessage)
        guard !granted else { return }
        accessibilityPermissionPollTask?.cancel()
        accessibilityPermissionPollTask = Task { @MainActor [weak self] in
            for _ in 0 ..< 240 {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                self?.refreshPermissionStatus()
                if self?.accessibilityPermissionGranted == true {
                    return
                }
            }
            self?.accessibilityPermissionPollTask = nil
        }
    }

    func requestMicrophonePermission() {
        JarvisPrivacyPermissionAccess.requestMicrophoneAccess { [weak self] granted in
            guard let self else { return }
            refreshPermissionStatus()
            if granted, taskPermissionPrompt?.permission == .microphone {
                taskPermissionPrompt = nil
            }
            statusMessage = granted
                ? "麦克风权限已开启"
                : "请在系统设置中开启麦克风权限"
            showToast(statusMessage)
            if !granted {
                JarvisPrivacyPermissionAccess.openSettings(for: .microphone)
            }
        }
    }
}
