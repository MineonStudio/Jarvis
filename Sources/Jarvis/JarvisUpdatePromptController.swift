import AppKit

/// Update prompts always belong to the main window, even when settings has focus.
@MainActor
final class JarvisUpdatePromptController {
    private(set) var isPresenting = false

    static func makeAlert(release: JarvisReleaseInfo) -> NSAlert {
        let version = release.version.lowercased().hasPrefix("v") ? release.version : "v\(release.version)"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(version)"
        alert.informativeText = "Jarvis 有新版本可用。立马更新将下载更新，并在完成后重启应用。"
        alert.addButton(withTitle: "立马更新")
        alert.addButton(withTitle: "稍后更新")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert
    }

    func present(release: JarvisReleaseInfo, onInstall: @escaping @MainActor () -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        Task { @MainActor [self] in
            if Self.mainWindow(in: NSApp.windows)?.isVisible != true {
                JarvisMenuBarController.shared.reopenMainWindow(preservingSelection: true)
            }
            // Recreating a closed SwiftUI window takes a turn of the run loop.
            for _ in 0 ..< 20 {
                if Self.mainWindow(in: NSApp.windows) != nil {
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let window = Self.mainWindow(in: NSApp.windows) else {
                isPresenting = false
                JarvisLog.error(category: .update, event: "update.prompt.mainWindowUnavailable")
                return
            }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            let alert = Self.makeAlert(release: release)
            alert.beginSheetModal(for: window) { [self] response in
                isPresenting = false
                if response == .alertFirstButtonReturn {
                    onInstall()
                }
            }
        }
    }

    static func mainWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first {
            !($0 is NSPanel) && (
                $0.identifier?.rawValue == JarvisAppIdentity.mainWindowSceneID
                    || $0.frameAutosaveName == JarvisMainWindowController.frameAutosaveName
            )
        }
    }
}
