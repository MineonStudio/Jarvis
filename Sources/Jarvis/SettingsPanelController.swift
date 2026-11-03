import AppKit
import SwiftUI

/// A standalone utility panel, matching the F3 clipboard panel. Its hosting
/// view belongs only to this window and never enters the main window's tree.
@MainActor
final class SettingsPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private weak var appModel: AppModel?

    func show(app: AppModel) {
        appModel = app
        show {
            AnyView(SettingsPanelView().environment(app).jarvisAccentAware())
        }
    }

    func show(makeContent: () -> AnyView) {
        if panel == nil {
            makePanel(content: makeContent())
        }
        guard let panel else { return }
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        } else if !panel.isVisible {
            panel.center()
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        JarvisLog.info(category: .window, event: "settings.window.opened")
    }

    func close() {
        panel?.close()
    }

    private func makePanel(content: AnyView) {
        let panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: SettingsLayout.defaultWindowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("Jarvis.SettingsPanel")
        panel.title = "设置"
        JarvisWindowAppearance.configureTransparentTitlebar(for: panel)
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .default
        panel.collectionBehavior = [.canJoinAllSpaces]
        JarvisWindowAppearance.configureStandardControls(for: panel)
        panel.minSize = SettingsLayout.minimumWindowSize
        panel.delegate = self
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
    }

    func windowWillClose(_: Notification) {
        if appModel?.taskPermissionPrompt?.presentation == .settingsWindow {
            appModel?.dismissTaskPermissionPrompt()
        }
        JarvisLog.info(category: .window, event: "settings.window.closed")
    }

    func windowWillEnterFullScreen(_: Notification) {
        panel?.level = .normal
    }

    func windowDidExitFullScreen(_: Notification) {
        panel?.level = .floating
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        window.level = .floating
    }
}

private final class SettingsPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

private struct SettingsPanelView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsView()
            .jarvisTheme(app.themePreference, systemColorScheme: app.systemColorScheme)
            .overlay {
                if let prompt = app.taskPermissionPrompt, prompt.presentation == .settingsWindow {
                    JarvisTaskPermissionOverlay(prompt: prompt)
                }
            }
            .jarvisToastOverlay(app.toastMessage)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
    }
}
