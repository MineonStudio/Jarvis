import AppKit
import Foundation

enum JarvisAutomaticUpdatePreference {
    static let key = "jarvis.update.automatic.enabled"
    static let defaultValue = true

    static func load(from defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            defaults.set(defaultValue, forKey: key)
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}

extension AppModel {
    func updateAutomaticUpdatesEnabled(_ enabled: Bool) {
        automaticUpdatesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: JarvisAutomaticUpdatePreference.key)
        configureAutomaticUpdates()
    }

    /// Owned by the application, so closing the main window does not stop checks.
    func configureAutomaticUpdates() {
        automaticUpdateTask?.cancel()
        automaticUpdateTask = nil
        guard automaticUpdatesEnabled else { return }

        automaticUpdateTask = Task { @MainActor [weak self] in
            do {
                // Let launch finish before starting network work or presenting a prompt.
                try await Task.sleep(for: .seconds(3))
                while !Task.isCancelled {
                    guard let enabled = self?.automaticUpdatesEnabled, enabled else { return }
                    self?.checkForUpdates(automatically: true)
                    try await Task.sleep(for: .seconds(6 * 60 * 60))
                }
            } catch {
                // Disabling the preference or releasing the model cancels the schedule.
            }
        }
    }

    func checkForUpdates(automatically: Bool = false) {
        guard !updatePromptController.isPresenting else { return }
        switch updateState {
        case .checking, .downloading, .readyToInstall, .installing:
            return
        default:
            break
        }
        let previousState = updateState
        updateState = .checking
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let release = try await updateService.checkForLatestRelease()
                guard !automatically || automaticUpdatesEnabled else {
                    updateState = previousState
                    return
                }
                let hasNewVersion = updateService.isNewer(
                    release,
                    than: JarvisAppVersion.shortVersion,
                    build: JarvisAppVersion.build
                )
                if hasNewVersion {
                    updateState = .available(release)
                    if !automatically || lastPromptedUpdate != release {
                        lastPromptedUpdate = release
                        updatePromptController.present(release: release) { [weak self] in
                            self?.downloadAndInstallUpdate()
                        }
                    }
                } else {
                    updateState = .upToDate
                    if !automatically {
                        showToast(JarvisFeedbackCopy.latestVersion)
                    }
                }
            } catch {
                guard !automatically else {
                    updateState = previousState
                    JarvisLog.error(category: .update, event: "release.check.failed", error: error)
                    return
                }
                let message = Self.updateFailureMessage(error)
                updateState = .failed(message: message)
                showToast(message)
                JarvisLog.error(category: .update, event: "release.check.failed", error: error)
            }
        }
    }

    func downloadAndInstallUpdate() {
        guard case let .available(release) = updateState else { return }
        updateState = .downloading(version: release.version)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                updateState = .downloading(version: release.version)
                try await updateService.downloadAndInstall(release)
                updateState = .installing(version: release.version)
                try await Task.sleep(for: .milliseconds(250))
                NSApp.terminate(nil)
            } catch {
                let message = Self.updateFailureMessage(error)
                updateState = .failed(message: message)
                showToast(message)
                JarvisLog.error(category: .update, event: "install.prepare.failed", error: error)
            }
        }
    }

    @discardableResult
    func launchPreparedUpdateInstaller() -> Bool {
        true
    }

    private static func updateFailureMessage(_ error: Error) -> String {
        if let updateError = error as? JarvisUpdateError {
            return updateError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                return "网络超时，请稍后重试"
            case .badServerResponse, .resourceUnavailable:
                return "更新服务器没有返回有效结果"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
