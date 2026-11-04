import AppKit
import SwiftUI

/// Independent settings content with normal window stacking.
@MainActor
final class SettingsPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private weak var appModel: AppModel?
    private var permissionRefreshTask: Task<Void, Never>?

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
        panel.makeKeyAndOrderFront(nil)
        startRefreshingPermissionStatus()
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
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .default
        JarvisWindowAppearance.configureStandardControls(for: panel)
        panel.minSize = SettingsLayout.minimumWindowSize
        panel.delegate = self
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
    }

    func windowWillClose(_: Notification) {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = nil
        if appModel?.taskPermissionPrompt?.presentation == .settingsWindow {
            appModel?.dismissTaskPermissionPrompt()
        }
        JarvisLog.info(category: .window, event: "settings.window.closed")
    }

    func windowDidBecomeKey(_: Notification) {
        // Nonactivating panels can regain focus without didBecomeActive.
        appModel?.refreshPermissionStatus()
    }

    private func startRefreshingPermissionStatus() {
        permissionRefreshTask?.cancel()
        appModel?.refreshPermissionStatus()
        guard appModel != nil else { return }
        // Keep tracking revocations while System Settings is in front. Stop
        // when this panel closes, and restart when it is opened again.
        permissionRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled, self?.panel?.isVisible == true else { return }
                self?.appModel?.refreshPermissionStatus()
            }
        }
    }

    func windowWillEnterFullScreen(_: Notification) {
        panel?.level = .normal
    }

    func windowDidExitFullScreen(_: Notification) {
        panel?.level = .normal
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        window.level = .normal
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
