import AppKit

/// Update prompts always belong to the main window, even when settings has focus.
@MainActor
final class JarvisUpdatePromptController {
    private(set) var isPresenting = false

    static func makeAlert(release: JarvisReleaseInfo, notes: [String] = []) -> NSAlert {
        let version = release.version.lowercased().hasPrefix("v") ? release.version : "v\(release.version)"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(version)"
        let restart = "安装完成后，Jarvis 将自动重启应用。"
        if notes.isEmpty {
            alert.informativeText = "暂时无法显示更新说明。\n\n" + restart
        } else {
            alert.informativeText = restart
            alert.accessoryView = releaseNotesView(notes)
        }
        alert.addButton(withTitle: "立马更新")
        alert.addButton(withTitle: "稍后更新")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert
    }

    private static func releaseNotesView(_ notes: [String]) -> NSView {
        let width: CGFloat = 380
        let maximumHeight: CGFloat = 180
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 14
        paragraph.paragraphSpacing = 6
        let contents = NSAttributedString(
            string: notes.map { "•  \($0)" }.joined(separator: "\n"),
            attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        )
        let requiredHeight = ceil(contents.boundingRect(
            with: NSSize(width: width - 20, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 8

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame.size = NSSize(width: width, height: min(requiredHeight, maximumHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = requiredHeight > maximumHeight
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 5, height: 4)
            textView.textStorage?.setAttributedString(contents)
        }
        scrollView.setAccessibilityLabel("本次更新")
        return scrollView
    }

    func present(
        release: JarvisReleaseInfo,
        loadNotes: @escaping @Sendable (String) async -> [String] = JarvisReleaseNotes.load,
        onInstall: @escaping @MainActor () -> Void
    ) {
        guard !isPresenting else { return }
        isPresenting = true
        Task { @MainActor [self] in
            let notes = await loadNotes(release.version)
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
            let alert = Self.makeAlert(release: release, notes: notes)
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
