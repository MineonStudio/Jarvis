import AppKit
import SwiftUI

struct ScreenRecordingOptionsButton: NSViewRepresentable {
    let recorder: ScreenRecordingCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(recorder: recorder)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "选项", target: context.coordinator, action: #selector(Coordinator.showOptions(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ])
        button.contentTintColor = .secondaryLabelColor
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        button.imagePosition = .imageRight
        button.imageScaling = .scaleNone
        button.setAccessibilityLabel("录制选项")
        return button
    }

    func updateNSView(_: NSButton, context _: Context) {}

    static func dismantleNSView(_: NSButton, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject {
        let recorder: ScreenRecordingCoordinator
        private var panel: ScreenRecordingOptionsPanel?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var activationObserver: NSObjectProtocol?
        private weak var anchorButton: NSButton?

        init(recorder: ScreenRecordingCoordinator) {
            self.recorder = recorder
        }

        @objc func showOptions(_ sender: NSButton) {
            if panel?.isVisible == true {
                close(); return
            }
            guard let window = sender.window else { return }
            recorder.panelController?.showModeHint(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self, weak sender, weak window] in
                guard let self, let sender, let window, sender.window === window, window.isVisible else { return }
                let anchor = window.convertToScreen(sender.convert(sender.bounds, to: nil))
                let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor.insetBy(dx: -400, dy: -500)
                let width = min(ScreenRecordingOptionsLayout.width(microphoneNames: recorder.microphones.map(\.localizedName)), visible.width - 16)
                let options = ScreenRecordingOptionsPopover(recorder: recorder, width: width, height: 1)
                let measurement = NSHostingView(rootView: options.content.frame(width: width).fixedSize(horizontal: false, vertical: true))
                let height = min(ceil(measurement.fittingSize.height), visible.height - 16)
                let x = min(max(anchor.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
                let above = anchor.maxY + 8
                let y = min(max(above + height <= visible.maxY ? above : anchor.minY - height - 8, visible.minY + 8), visible.maxY - height - 8)
                let panel = ScreenRecordingOptionsPanel(
                    contentRect: CGRect(x: x, y: y, width: width, height: height),
                    styleMask: [.borderless], backing: .buffered, defer: false
                )
                panel.title = "屏幕录制选项"
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.hidesOnDeactivate = false
                panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.popUpMenu.rawValue, window.level.rawValue + 1))
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.onCancel = { [weak self] in self?.close() }
                panel.contentView = NSHostingView(rootView: ScreenRecordingOptionsPopover(recorder: recorder, width: width, height: height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12)))
                self.panel = panel
                anchorButton = sender
                panel.makeKeyAndOrderFront(nil)
                installDismissalMonitors()
            }
        }

        private func installDismissalMonitors() {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel, event.window !== panel else { return }
                    if let anchorButton = self.anchorButton, event.window === anchorButton.window,
                       anchorButton.bounds.contains(anchorButton.convert(event.locationInWindow, from: nil))
                    {
                        return
                    }
                    self.close()
                }
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.close() } }
        }

        func close() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
            }
            if let activationObserver {
                NotificationCenter.default.removeObserver(activationObserver)
            }
            localMonitor = nil; globalMonitor = nil; activationObserver = nil
            panel?.orderOut(nil); panel?.close(); panel = nil
            anchorButton = nil
        }
    }
}

private final class ScreenRecordingOptionsPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == JarvisKeyCode.escape {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
