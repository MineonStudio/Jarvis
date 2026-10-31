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
        private weak var window: NSWindow?
        private weak var toolbar: NSView?
        private weak var optionsView: NSView?
        private var toolbarAutoresizingMask: NSView.AutoresizingMask = []
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var activationObserver: NSObjectProtocol?
        private weak var anchorButton: NSButton?

        init(recorder: ScreenRecordingCoordinator) {
            self.recorder = recorder
        }

        @objc func showOptions(_ sender: NSButton) {
            if optionsView != nil {
                close(); return
            }
            guard let window = sender.window, let toolbar = window.contentView else { return }
            recorder.panelController?.showModeHint(nil)
            window.orderFrontRegardless()
            window.makeKey()
            let anchor = window.convertToScreen(sender.convert(sender.bounds, to: nil))
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor.insetBy(dx: -400, dy: -500)
            let width = min(ScreenRecordingOptionsLayout.width(microphoneNames: recorder.microphones.map(\.localizedName)), visible.width - 16)
            let options = ScreenRecordingOptionsPopover(recorder: recorder, width: width, height: 1)
            let measurement = NSHostingView(rootView: options.content.frame(width: width).fixedSize(horizontal: false, vertical: true))
            let height = min(ceil(measurement.fittingSize.height), visible.height - 16)
            let x = min(max(anchor.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
            let above = anchor.maxY + 8
            let y = min(max(above + height <= visible.maxY ? above : anchor.minY - height - 8, visible.minY + 8), visible.maxY - height - 8)
            let optionsFrame = CGRect(x: x, y: y, width: width, height: height)
            let toolbarFrame = window.frame
            let expandedFrame = toolbarFrame.union(optionsFrame)
            let hostingView = NSHostingView(rootView: ScreenRecordingOptionsPopover(recorder: recorder, width: width, height: height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12)))
            hostingView.sizingOptions = []

            // Keep native glass and pickers in the same key window. A separate
            // key panel dims the launcher's native glass regardless of SwiftUI's
            // controlActiveState environment value.
            self.window = window
            self.toolbar = toolbar
            optionsView = hostingView
            anchorButton = sender
            toolbarAutoresizingMask = toolbar.autoresizingMask
            toolbar.autoresizingMask = []
            let container = ScreenRecordingOptionsContainer(frame: CGRect(origin: .zero, size: expandedFrame.size), toolbar: toolbar)
            window.contentView = container
            container.addSubview(toolbar)
            window.setFrame(expandedFrame, display: false)
            toolbar.frame = toolbarFrame.offsetBy(dx: -expandedFrame.minX, dy: -expandedFrame.minY)
            hostingView.frame = optionsFrame.offsetBy(dx: -expandedFrame.minX, dy: -expandedFrame.minY)
            container.addSubview(hostingView)
            installDismissalMonitors()
        }

        private func installDismissalMonitors() {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp, .keyDown]) { [weak self] event in
                var consumed = false
                MainActor.assumeIsolated {
                    guard let self, let optionsView = self.optionsView else { return }
                    if event.type == .keyDown {
                        guard event.keyCode == JarvisKeyCode.escape else { return }
                        self.close()
                        consumed = true
                        return
                    }
                    if event.window === self.window {
                        if optionsView.bounds.contains(optionsView.convert(event.locationInWindow, from: nil)) {
                            return
                        }
                        if let anchorButton = self.anchorButton,
                           anchorButton.bounds.contains(anchorButton.convert(event.locationInWindow, from: nil))
                        {
                            return
                        }
                        // Let toolbar buttons finish handling mouse-up before
                        // shrinking the window changes their event coordinates.
                        if event.type == .leftMouseUp || event.type == .rightMouseUp {
                            DispatchQueue.main.async { [weak self] in self?.close() }
                        }
                    } else {
                        self.close()
                    }
                }
                return consumed ? nil : event
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
            if let window, let toolbar, optionsView != nil {
                let frame = window.convertToScreen(toolbar.frame)
                optionsView?.removeFromSuperview()
                toolbar.removeFromSuperview()
                window.contentView = toolbar
                window.setFrame(frame, display: false)
                toolbar.frame = CGRect(origin: .zero, size: frame.size)
                toolbar.autoresizingMask = toolbarAutoresizingMask
                window.makeFirstResponder(toolbar)
            }
            optionsView = nil
            toolbar = nil
            window = nil
            anchorButton = nil
        }
    }
}

/// Both surfaces share one responder chain and one native active appearance.
final class ScreenRecordingOptionsContainer: NSView {
    let toolbar: NSView

    init(frame: CGRect, toolbar: NSView) {
        self.toolbar = toolbar
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
